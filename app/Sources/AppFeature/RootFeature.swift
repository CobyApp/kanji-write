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
    }

    /// A full-screen study session launched from Home.
    @Reducer(state: .equatable)
    public enum Session {
        case worksheet(WorksheetFeature)
        case practice(PracticeFeature)
        case quiz(QuizFeature)
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
        case bookmarksAppeared
        case bookmarksLoaded([Int])
        case startStudy
        case startPractice
        case startQuiz(level: String)
        case path(StackActionOf<Path>)
        case sessionPath(StackActionOf<Path>)
        case session(PresentationAction<Session.Action>)
    }

    @Dependency(\.kanjiBookmarkStore) var kanjiBookmarkStore

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
                let items = studyOrder(state.review.kanji.elements, level: level.level)
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

            // Word dictionary → drill into a selected word's detail.
            case let .path(.element(id: _, action: .wordDictionary(.wordSelected(word)))):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none

            case .bookmarksAppeared:
                return .run { send in await send(.bookmarksLoaded(await kanjiBookmarkStore.load())) }
            case let .bookmarksLoaded(ids):
                state.bookmarkedIDs = ids
                return .none

            // Dictionary browse (from the study hub) → drill into a level / a searched kanji.
            case let .path(.element(id: _, action: .dictionary(.levelSelected(level)))):
                let items = studyOrder(state.review.kanji.elements, level: level.level)
                state.path.append(
                    .kanjiList(KanjiListPathFeature.State(
                        title: level.label, kanji: items, glosses: state.review.glosses)))
                return .none
            case let .path(.element(id: _, action: .dictionary(.kanjiSelected(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none

            case let .wordReview(.wordTapped(word)):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none

            // Home session launchers → full-screen cover. Start each with a fresh
            // in-session navigation stack.
            case .startStudy:
                state.sessionPath.removeAll()
                state.session = .worksheet(WorksheetFeature.State())
                return .none
            case .startPractice:
                state.sessionPath.removeAll()
                state.session = .practice(PracticeFeature.State())
                return .none
            case let .startQuiz(level):
                state.sessionPath.removeAll()
                // QuizFeature reads today's / due kanji fresh from the store itself.
                state.session = .quiz(QuizFeature.State(level: level))
                return .none

            // Tapping a word / kanji while studying drills into its detail on the
            // in-session stack (stays inside the full-screen session).
            case .session(.presented(.worksheet(.closeTapped))):
                state.sessionPath.removeAll()
                state.session = nil
                return .none
            case let .session(.presented(.worksheet(.wordTapped(word)))):
                state.sessionPath.append(.word(WordDetailFeature.State(word: word)))
                return .none
            case let .session(.presented(.worksheet(.kanjiTapped(kanji)))):
                state.sessionPath.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case .session(.dismiss):
                state.sessionPath.removeAll()
                return .none

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

            // Dictionary drill routing.
            case let .path(.element(id: _, action: .kanjiList(.kanjiTapped(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
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
