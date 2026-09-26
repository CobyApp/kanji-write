import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import Practice
import Reminders
import Review
import SharedModels
import TestMode
import Worksheet
import WritingCanvas

@Reducer
public struct RootFeature {
    /// One screen on the navigation stack, all reached from the single Home
    /// dashboard: the dictionary browse, a level's kanji list, kanji → word
    /// detail, and the writing canvas.
    @Reducer(state: .equatable)
    public enum Path {
        case kanjiList(KanjiListPathFeature)
        case kanji(KanjiDetailFeature)
        case word(WordDetailFeature)
        case writing(KanjiWritingFeature)
        case dictionary(DictionaryFeature)
        case wordDictionary(WordDictionaryFeature)
        case yojiDictionary(YojiDictionaryFeature)
        case yojiDetail(YojiDetailFeature)
        case stats(StatsFeature)
    }

    /// A full-screen study session launched from Home.
    @Reducer(state: .equatable)
    public enum Session {
        case worksheet(WorksheetFeature)
        case practice(PracticeFeature)
        case quiz(QuizFeature)
        case kanken(KankenExamFeature)
    }

    @ObservableState
    public struct State: Equatable {
        // Data source (kanji / records / today) powering Home's plan summary and
        // due count; also the dictionary's kanji list.
        public var review = ReviewFeature.State()
        // The wordbook (reached from the dictionary).
        public var wordReview = WordReviewFeature.State()
        // Settings (plan / language / reminder).
        public var reminder = ReminderFeature.State()

        // Settings sheet presented from the Home toolbar.
        public var showSettings = false
        // 단어장 관리 overlay presented from the Home 단어장 launcher.
        public var showWordbook = false
        // Bookmarked kanji ids (loaded on Home appear).
        public var bookmarkedIDs: [Int] = []
        // 오답노트 entries due today at the plan's level (Home's 오답 복습 tile).
        public var wrongDue = 0
        public var wrongDueLevel: String?
        public var path = StackState<Path.State>()
        // The active full-screen study session, if any.
        @Presents public var session: Session.State?
        // Navigation stack *inside* the study session (tapping a word/kanji while
        // studying drills into its detail without leaving the session).
        public var sessionPath = StackState<Path.State>()

        public init() {}
    }

    public enum Action {
        case onAppear
        case review(ReviewFeature.Action)
        case wordReview(WordReviewFeature.Action)
        case reminder(ReminderFeature.Action)
        case setShowSettings(Bool)
        case setShowWordbook(Bool)
        case removeBookmarkedKanji(Int)
        case kanjiSelected(Kanji)
        case levelSelected(KanjiLevel)
        case openDictionary
        case openWordDictionary
        case openExpressionDictionary
        case openYojiDictionary
        case openStats(level: String)
        case bookmarksAppeared
        case bookmarksLoaded([Int])
        case refreshWrongDue(level: String)
        case wrongDueLoaded(Int)
        case startWrongNoteReview(level: String, language: AppLanguage)
        case startStudy(pullAhead: Bool)
        case startPractice(mode: PracticeFeature.State.Mode, favorites: Bool = false)
        case startQuiz(level: String, planned: [Int])
        case startKanken(level: String)
        case path(StackActionOf<Path>)
        case sessionPath(StackActionOf<Path>)
        case session(PresentationAction<Session.Action>)
    }

    @Dependency(\.kanjiBookmarkStore) var kanjiBookmarkStore
    @Dependency(\.wrongNoteStore) var wrongNoteStore
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.review, action: \.review) { ReviewFeature() }
        Scope(state: \.wordReview, action: \.wordReview) { WordReviewFeature() }
        Scope(state: \.reminder, action: \.reminder) { ReminderFeature() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.review(.onAppear))

            case let .setShowSettings(show):
                state.showSettings = show
                return .none

            case let .setShowWordbook(show):
                state.showWordbook = show
                // Refresh the saved words each time it opens (words may have been
                // added from a detail screen since last time).
                return show ? .send(.wordReview(.onAppear)) : .none

            case let .removeBookmarkedKanji(id):
                state.bookmarkedIDs.removeAll { $0 == id }
                let ids = state.bookmarkedIDs
                return .run { _ in await kanjiBookmarkStore.save(ids) }

            case let .kanjiSelected(kanji):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none

            case let .levelSelected(level):
                let items = studyOrder(state.review.kanji.elements, exam: ExamType.current, level: level.level)
                state.path.append(
                    .kanjiList(KanjiListPathFeature.State(
                        title: level.label, kanji: items, glosses: state.review.glosses)))
                return .none

            // Open the dictionary browse from the study hub (pushed onto its stack).
            case .openDictionary:
                state.path.append(.dictionary(DictionaryFeature.State(
                    kanji: state.review.kanji.elements, glosses: state.review.glosses)))
                return .none

            case .openWordDictionary:
                state.path.append(.wordDictionary(WordDictionaryFeature.State()))
                return .none

            case .openExpressionDictionary:
                state.path.append(.wordDictionary(WordDictionaryFeature.State(expressions: true)))
                return .none

            case .openYojiDictionary:
                state.path.append(.yojiDictionary(YojiDictionaryFeature.State()))
                return .none

            case let .openStats(level):
                state.path.append(.stats(StatsFeature.State(
                    exam: ExamType.of(level: level), level: level,
                    kanji: state.review.kanji.elements, records: state.review.records.elements,
                    today: state.review.today)))
                return .none

            // Word dictionary → drill into a selected word's detail, carrying the
            // visible list for prev/next.
            case let .path(.element(id: id, action: .wordDictionary(.wordSelected(word)))):
                var siblings: [WordEntry] = []
                if case let .wordDictionary(dict)? = state.path[id: id] {
                    siblings = dict.isSearching ? dict.visibleResults : dict.visibleWords
                }
                let idx = siblings.firstIndex(of: word) ?? 0
                state.path.append(.word(WordDetailFeature.State(word: word, siblings: siblings, index: idx)))
                return .none

            // 四字熟語 dictionary → idiom detail; idiom detail → a constituent kanji.
            case let .path(.element(id: id, action: .yojiDictionary(.yojiSelected(yoji)))):
                var siblings: [Yojijukugo] = []
                if case let .yojiDictionary(dict)? = state.path[id: id] { siblings = dict.visible }
                let idx = siblings.firstIndex(of: yoji) ?? 0
                state.path.append(.yojiDetail(YojiDetailFeature.State(yoji: yoji, siblings: siblings, index: idx)))
                return .none
            case let .path(.element(id: _, action: .yojiDetail(.kanjiTapped(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none

            case .bookmarksAppeared:
                return .run { send in await send(.bookmarksLoaded(await kanjiBookmarkStore.load())) }
            case let .bookmarksLoaded(ids):
                state.bookmarkedIDs = ids
                return .none

            case let .refreshWrongDue(level):
                state.wrongDueLevel = level
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    let due = await wrongNoteStore.load()
                        .filter { $0.belongs(to: level) && $0.isDue(on: today) }
                    await send(.wrongDueLoaded(due.count))
                }
            case let .wrongDueLoaded(count):
                state.wrongDue = count
                return .none

            case let .startWrongNoteReview(level, language):
                state.sessionPath.removeAll()
                state.session = .kanken(KankenExamFeature.State(level: level, language: language))
                // Straight into today's notebook review rather than the hub.
                return .concatenate(
                    .send(.session(.presented(.kanken(.onAppear(level: level, language: language))))),
                    .send(.session(.presented(.kanken(.selectWrongNote)))))

            // Dictionary browse (from the study hub) → drill into a level / a searched kanji.
            case let .path(.element(id: _, action: .dictionary(.levelSelected(level)))):
                let items = studyOrder(state.review.kanji.elements, exam: ExamType.current, level: level.level)
                state.path.append(
                    .kanjiList(KanjiListPathFeature.State(
                        title: level.label, kanji: items, glosses: state.review.glosses)))
                return .none
            case let .path(.element(id: id, action: .dictionary(.kanjiSelected(kanji)))):
                var siblings: [Kanji] = []
                if case let .dictionary(dict)? = state.path[id: id] { siblings = dict.searchResults }
                let idx = siblings.firstIndex(of: kanji) ?? 0
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji, siblings: siblings, index: idx)))
                return .none

            case let .wordReview(.wordTapped(word)):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none

            // Home session launchers → full-screen cover. Start each with a fresh
            // in-session navigation stack.
            case let .startStudy(pullAhead):
                state.sessionPath.removeAll()
                state.session = .worksheet(WorksheetFeature.State(pullAhead: pullAhead))
                return .none
            case let .startPractice(mode, favorites):
                state.sessionPath.removeAll()
                var practice = PracticeFeature.State()
                practice.mode = mode
                // Opening 즐겨찾기 from Home forces the scope on, so the tile lands
                // where it says it will rather than on whatever was last used.
                practice.useFavorites = favorites
                state.session = .practice(practice)
                return .none
            case let .startQuiz(level, planned):
                state.sessionPath.removeAll()
                // QuizFeature reads today's studied / due kanji fresh from the
                // store; `planned` lets it also quiz today's not-yet-studied kanji.
                state.session = .quiz(QuizFeature.State(level: level, plannedIDs: planned))
                return .none
            case let .startKanken(level):
                state.sessionPath.removeAll()
                state.session = .kanken(KankenExamFeature.State(level: level))
                return .none

            // Tapping a word / kanji while studying drills into its detail on the
            // in-session stack (stays inside the full-screen session).
            case .session(.presented(.worksheet(.closeTapped))):
                state.sessionPath.removeAll()
                state.session = nil
                // Refresh home progress with what was just learned.
                return .send(.review(.reloadRecords))
            case let .session(.presented(.worksheet(.wordTapped(word)))):
                state.sessionPath.append(.word(WordDetailFeature.State(word: word)))
                return .none
            case let .session(.presented(.worksheet(.kanjiTapped(kanji)))):
                state.sessionPath.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case .session(.dismiss):
                state.sessionPath.removeAll()
                // A study / quiz session may have updated SRS records — refresh
                // home progress so it doesn't need an app restart.
                if let level = state.wrongDueLevel {
                    return .merge(.send(.review(.reloadRecords)), .send(.refreshWrongDue(level: level)))
                }
                return .send(.review(.reloadRecords))

            // In-session drilling (word → kanji → writing), mirroring the
            // dictionary stack.
            case let .sessionPath(.element(id: _, action: .kanji(.wordTapped(word)))):
                state.sessionPath.append(.word(WordDetailFeature.State(word: word)))
                return .none
            case let .sessionPath(.element(id: _, action: .word(.kanjiTapped(kanji)))):
                state.sessionPath.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .sessionPath(.element(id: _, action: .kanjiList(.kanjiTapped(kanji)))):
                state.sessionPath.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .sessionPath(.element(id: id, action: .kanji(.writeTapped))):
                guard case let .kanji(detail)? = state.sessionPath[id: id] else { return .none }
                state.sessionPath.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                return .none

            // Dictionary drill routing. Carry the level's kanji list into the
            // detail so it can step prev/next without returning to the list.
            case let .path(.element(id: id, action: .kanjiList(.kanjiTapped(kanji)))):
                var siblings: [Kanji] = []
                if case let .kanjiList(list)? = state.path[id: id] { siblings = list.kanji }
                let idx = siblings.firstIndex(of: kanji) ?? 0
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji, siblings: siblings, index: idx)))
                return .none
            case let .path(.element(id: _, action: .kanji(.wordTapped(word)))):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none
            case let .path(.element(id: _, action: .word(.kanjiTapped(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .path(.element(id: id, action: .kanji(.writeTapped))):
                guard case let .kanji(detail)? = state.path[id: id] else { return .none }
                state.path.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                return .none

            // Reset clears the store files (in ReminderFeature); also drop the
                // in-memory records so Home / Study / word list update immediately.
            case .reminder(.resetProgress):
                state.review.records.removeAll()
                state.wordReview.records.removeAll()
                state.wordReview.words.removeAll()
                return .none

            case .review, .wordReview, .reminder, .path, .sessionPath, .session:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .forEach(\.sessionPath, action: \.sessionPath)
        .ifLet(\.$session, action: \.session)
    }
}
