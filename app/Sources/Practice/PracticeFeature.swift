import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// A writing test. The learner picks a level and a range, then for each item
/// sees only its meaning + readings and writes the answer from memory on a blank
/// canvas. Nothing is auto-graded: at the end every answer is shown next to the
/// real one so the learner checks at a glance.
///
/// Two modes share all of this. 한자쓰기 tests a single kanji; 단어쓰기 tests a
/// whole word, which is the harder and more practical skill — knowing 学 and 校
/// separately is not the same as producing 学校 on demand.

/// One thing to write: the answer, and the clues shown in its place.
public struct PracticeItem: Equatable, Identifiable {
    public let id: Int
    /// What the learner has to write — a kanji, or a whole word.
    public let answer: String
    /// Meanings by language key, shown instead of the answer.
    public let glosses: [String: String]
    /// Kana reading, shown for words (a kanji shows 음/훈 lines instead).
    public let reading: String?
    public let onReadings: [String]
    public let kunReadings: [String]
    /// The 部首 glyph, for a single kanji. A word or an idiom has no one radical.
    public let radical: String?
    /// Set only when the answer is a single kanji, so the 힌트 can show its
    /// stroke order. A multi-kanji word has no single stroke-order animation.
    public let strokeOrderKanjiID: Int?

    public init(id: Int, answer: String, glosses: [String: String], reading: String? = nil,
                onReadings: [String] = [], kunReadings: [String] = [],
                radical: String? = nil, strokeOrderKanjiID: Int? = nil) {
        self.id = id
        self.answer = answer
        self.glosses = glosses
        self.reading = reading
        self.onReadings = onReadings
        self.kunReadings = kunReadings
        self.radical = radical
        self.strokeOrderKanjiID = strokeOrderKanjiID
    }
}
/// The setup choices worth surviving the sheet being dismissed. Someone working
/// through 1級 200 kanji at a time should not have to re-pick the level and
/// re-drag the range every single session.
public struct PracticeSettings: Equatable, Codable, Sendable {
    public var mode: String
    public var level: String
    public var start: Int
    public var end: Int
    /// Drawing from 즐겨찾기 rather than a 급수 range. Optional so a settings blob
    /// written before the scope existed still decodes.
    public var useFavorites: Bool?
}

@Reducer
public struct PracticeFeature {
    @ObservableState
    public struct State: Equatable {
        public enum Phase: Equatable { case setup, testing, review }
        /// 한자쓰기 vs 단어쓰기 — same flow, different thing to write.
        public enum Mode: String, Equatable, CaseIterable { case kanji, word, yoji }
        public var phase: Phase = .setup
        public var mode: Mode = .kanji

        /// All kanji + glosses (loaded on appear).
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var glossesByID: [Int: [String: String]] = [:]
        /// Level vocabulary for 단어쓰기, reloaded when the level changes.
        public var words: [WordEntry] = []
        /// Level 四字熟語 for 사자성어쓰기.
        public var yojijukugo: [Yojijukugo] = []

        /// Draw from the 즐겨찾기 list instead of a level range.
        public var useFavorites = false
        /// mode raw value → favourited item ids.
        public var favorites: [String: [Int]] = [:]
        /// The favourites resolved to items, for the current mode. Empty until
        /// the lookup returns, which is why it is not computed.
        public var favoriteItems: [PracticeItem] = []

        /// Chosen level + range.
        public var level = "N5"
        /// Inclusive 0-based range within levelItems. `count` follows from it —
        /// picking "51st to 80th" is how you actually resume a long 級, and a
        /// start-plus-length control makes you do that arithmetic yourself.
        public var start = 0
        public var end = 19

        /// What is being tested this run, in study order.
        public var questions: [PracticeItem] = []
        public var index = 0
        /// Per-question PKDrawing data (question index → serialized drawing).
        public var drawings: [Int: Data] = [:]
        /// 힌트: the answer kanji and its stroke order, hidden until asked for.
        /// Reset on every navigation so the next question starts covered.
        public var hintShown = false
        /// nil until the fetch returns. Empty means the fetch came back with no
        /// stroke data — the two must not look alike, or the fallback glyph
        /// flashes for a frame before the animation replaces it.
        public var hintStrokes: [String]?

        public init() {}

        /// Back to the first 20, for when the level or mode changes and the old
        /// indices no longer mean anything.
        mutating func resetRange() {
            start = 0
            end = 19
            clampRange()
        }

        /// Keep the range inside the level, which can shrink under it when the
        /// level or mode changes.
        ///
        /// Does nothing while the level looks empty: 단어/사자성어 load their
        /// data asynchronously, so clamping against a not-yet-loaded list
        /// collapses the range to 1~1 and it never grows back.
        mutating func clampRange() {
            guard levelCount > 0 else { return }
            let last = levelCount - 1
            start = min(start, last)
            end = min(max(end, start), last)
        }

        /// The level's kanji in study order (JLPT → strokes → id).
        public var levelKanji: [Kanji] {
            studyOrder(kanji.elements, exam: ExamType.current, level: level)
                .filter(\.hasVerifiedStrokeOrder)
        }
        /// Every item available at this level, in the current mode.
        public var levelItems: [PracticeItem] {
            switch mode {
            case .kanji:
                return levelKanji.map { k in
                    PracticeItem(
                        id: k.id, answer: k.literal, glosses: glossesByID[k.id] ?? [:],
                        onReadings: k.onReadings, kunReadings: k.kunReadings,
                        radical: k.radicalGlyph, strokeOrderKanjiID: k.id)
                }
            case .yoji:
                return yojijukugo.map { y in
                    PracticeItem(
                        id: y.id, answer: y.yoji,
                        glosses: ["ja": y.meaningJa, "ko": y.meaningKo]
                            .compactMapValues { $0 },
                        reading: y.reading)
                }
            case .word:
                // Single-kanji entries would just be the 한자쓰기 test again.
                return words
                    .filter { $0.surface.count >= 2 }
                    .map { w in
                        PracticeItem(
                            id: w.id, answer: w.surface,
                            glosses: [
                                "ko": w.meaningKo, "ja": w.meaningJa,
                                "zh": w.meaningZh, "en": w.meaningEn,
                            ].compactMapValues { $0 },
                            reading: w.reading)
                    }
            }
        }
        public var levelCount: Int { levelItems.count }
        /// Largest valid start index.
        public var maxStart: Int { max(0, levelCount - 1) }
        /// How many items the chosen range covers.
        public var count: Int { max(0, min(end, levelCount - 1) - start + 1) }
        public var current: PracticeItem? {
            questions.indices.contains(index) ? questions[index] : nil
        }
        public var isLast: Bool { index >= questions.count - 1 }
        /// Exclusive range end (clamped) for the summary label.
        public var rangeEnd: Int { min(end + 1, levelCount) }

        /// The favourited ids for whichever mode is selected.
        public var favoriteIDs: [Int] { favorites[mode.rawValue] ?? [] }
        public var favoriteCount: Int { favoriteIDs.count }
        public func isFavorite(_ item: PracticeItem) -> Bool {
            favoriteIDs.contains(item.id)
        }
        /// How many items a run would hold, whichever scope is active.
        public var runCount: Int { useFavorites ? favoriteItems.count : count }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([Kanji], [Int: [String: String]])
        case restored(PracticeSettings)
        case levelSelected(String)
        case modeSelected(State.Mode)
        case wordsLoaded([WordEntry])
        case yojiLoaded([Yojijukugo])
        case setStart(Double)
        case setEnd(Double)
        case startTest
        case saveDrawing(Data)   // commit the current canvas into `drawings`
        case next
        case prev
        case toggleHint
        case hintStrokesLoaded([String])
        case finish              // → review
        case restart             // → setup
        case exitToSetup         // closing a run goes back to the range picker
        case favoritesLoaded([String: [Int]])
        case toggleFavorite(PracticeItem)
        case setUseFavorites(Bool)
        case favoriteItemsLoaded([PracticeItem])
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.practiceFavoriteStore) var favoriteStore

    static let settingsKey = "practiceSettings"

    /// Remember the setup for next time. UserDefaults is the right home: it is
    /// a UI preference, not study data, and losing it costs nothing.
    private func persist(_ state: State) -> Effect<Action> {
        let settings = PracticeSettings(
            mode: state.mode.rawValue, level: state.level,
            start: state.start, end: state.end, useFavorites: state.useFavorites)
        return .run { _ in
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
        }
    }

    private func restoreSettings() -> Effect<Action> {
        .run { send in
            guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
                  let settings = try? JSONDecoder().decode(PracticeSettings.self, from: data)
            else { return }
            await send(.restored(settings))
        }
    }

    /// 단어쓰기 needs the level's vocabulary; 한자쓰기 already has every kanji.
    private func loadWords(_ level: String) -> Effect<Action> {
        .run { send in
            let words = (try? await dictionaryClient.quizWords(level, 400)) ?? []
            await send(.wordsLoaded(words))
        }
    }

    private func loadYoji(_ level: String) -> Effect<Action> {
        .run { send in
            let items = (try? await dictionaryClient.examYojijukugo(level, 400)) ?? []
            await send(.yojiLoaded(items))
        }
    }

    /// Turn favourited ids back into items.
    ///
    /// A favourite outlives the level it was marked in, so this cannot filter
    /// `levelItems` — 熟語 favourited while working 2級 would vanish the moment
    /// the learner moved to 準1級. Kanji are all in memory; words and idioms are
    /// looked up.
    private func loadFavoriteItems(
        _ mode: State.Mode, _ ids: [Int],
        kanji: IdentifiedArrayOf<Kanji>, glosses: [Int: [String: String]]
    ) -> Effect<Action> {
        guard !ids.isEmpty else { return .send(.favoriteItemsLoaded([])) }
        switch mode {
        case .kanji:
            let items = ids.compactMap { id -> PracticeItem? in
                guard let k = kanji[id: id] else { return nil }
                return PracticeItem(
                    id: k.id, answer: k.literal, glosses: glosses[k.id] ?? [:],
                    onReadings: k.onReadings, kunReadings: k.kunReadings,
                    radical: k.radicalGlyph, strokeOrderKanjiID: k.id)
            }
            return .send(.favoriteItemsLoaded(items))
        case .word:
            return .run { send in
                var items: [PracticeItem] = []
                for id in ids {
                    guard let w = try? await dictionaryClient.word(id) else { continue }
                    items.append(PracticeItem(
                        id: w.id, answer: w.surface,
                        glosses: [
                            "ko": w.meaningKo, "ja": w.meaningJa,
                            "zh": w.meaningZh, "en": w.meaningEn,
                        ].compactMapValues { $0 },
                        reading: w.reading))
                }
                await send(.favoriteItemsLoaded(items))
            }
        case .yoji:
            return .run { send in
                let all = (try? await dictionaryClient.allYojijukugo()) ?? []
                let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
                let items = ids.compactMap { id -> PracticeItem? in
                    guard let y = byID[id] else { return nil }
                    return PracticeItem(
                        id: y.id, answer: y.yoji,
                        glosses: ["ja": y.meaningJa, "ko": y.meaningKo,
                                  "zh": y.meaningZh, "en": y.meaningEn]
                            .compactMapValues { $0 },
                        reading: y.reading)
                }
                await send(.favoriteItemsLoaded(items))
            }
        }
    }

    /// Whichever extra dataset the mode needs; 한자쓰기 needs none.
    private func loadFor(_ mode: State.Mode, _ level: String) -> Effect<Action> {
        switch mode {
        case .kanji: return .none
        case .word: return loadWords(level)
        case .yoji: return loadYoji(level)
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.kanji.isEmpty else { return .none }
                return .merge(
                    .run { send in
                        let all = (try? await dictionaryClient.allKanji()) ?? []
                        let glosses = (try? await dictionaryClient.allGlosses()) ?? [:]
                        await send(.loaded(all, glosses))
                    },
                    .run { send in await send(.favoritesLoaded(await favoriteStore.load())) },
                    restoreSettings())

            case let .restored(settings):
                state.mode = State.Mode(rawValue: settings.mode) ?? .kanji
                state.level = settings.level
                state.start = settings.start
                state.end = settings.end
                // `useFavorites` is false on a fresh state, so a true here can
                // only have been set by the 즐겨찾기 tile on the way in — and that
                // has to win over whatever scope was last used.
                if !state.useFavorites {
                    state.useFavorites = settings.useFavorites ?? false
                }
                return .merge(
                    loadFor(state.mode, settings.level),
                    loadFavoriteItems(state.mode, state.favoriteIDs,
                                      kanji: state.kanji, glosses: state.glossesByID))

            case let .loaded(all, glosses):
                defer { state.clampRange() }
                state.kanji = IdentifiedArray(uniqueElements: all)
                state.glossesByID = glosses
                // Keep the chosen level valid for the current exam (e.g. after
                // switching JLPT↔漢検 the old "N5" wouldn't exist under 漢検).
                if !ExamType.current.levels.contains(state.level) {
                    state.level = ExamType.current.defaultLevel
                }
                // Favourites load in parallel with the kanji list and usually win
                // the race, and a kanji favourite can only be resolved once the
                // list is here. Without this the setup screen showed "1 항목" from
                // the stored ids while the run stayed empty and 테스트 시작 sat
                // there disabled.
                return loadFavoriteItems(state.mode, state.favoriteIDs,
                                         kanji: state.kanji, glosses: state.glossesByID)

            case let .levelSelected(level):
                state.level = level
                state.resetRange()       // a new level's range starts at the top
                return .merge(persist(state), loadFor(state.mode, level))

            case let .setEnd(value):
                state.end = min(Int(value.rounded()), max(0, state.levelCount - 1))
                // Dragging the end below the start would invert the range.
                state.start = min(state.start, state.end)
                return persist(state)

            case let .setStart(value):
                state.start = max(0, min(Int(value.rounded()), state.maxStart))
                state.end = max(state.end, state.start)
                return persist(state)

            case let .modeSelected(mode):
                state.mode = mode
                state.resetRange()
                state.favoriteItems = []
                return .merge(
                    persist(state), loadFor(mode, state.level),
                    loadFavoriteItems(mode, state.favoriteIDs,
                                      kanji: state.kanji, glosses: state.glossesByID))

            case let .wordsLoaded(words):
                state.words = words
                state.clampRange()
                return .none

            case let .yojiLoaded(items):
                state.yojijukugo = items
                state.clampRange()
                return .none

            case .startTest:
                if state.useFavorites {
                    guard !state.favoriteItems.isEmpty else { return .none }
                    state.questions = state.favoriteItems
                    state.index = 0
                    state.drawings = [:]
                    state.hintShown = false
                    state.hintStrokes = nil
                    state.phase = .testing
                    return .none
                }
                let lk = state.levelItems
                guard !lk.isEmpty else { return .none }
                // Clamp both ends against what this level actually holds, and
                // slice from those. Taking the start from the clamped range but
                // the length from the remembered one mixes two different lists
                // and could produce an empty run.
                let first = min(max(0, state.start), lk.count - 1)
                let last = min(max(first, state.end), lk.count - 1)
                state.start = first
                state.end = last
                state.questions = Array(lk[first...last])
                state.index = 0
                state.drawings = [:]
                state.hintShown = false
                state.hintStrokes = nil
                state.phase = .testing
                return .none

            case let .saveDrawing(data):
                state.drawings[state.index] = data
                return .none

            case .toggleHint:
                state.hintShown.toggle()
                guard state.hintShown, state.hintStrokes == nil else { return .none }
                guard let id = state.current?.strokeOrderKanjiID else {
                    // A word or an idiom has no single stroke-order animation.
                    // Resolve to "none available" now rather than leaving the
                    // hint spinning on a fetch that will never be made.
                    state.hintStrokes = []
                    return .none
                }
                return .run { [id] send in
                    let paths = (try? await dictionaryClient.strokeOrder(id)) ?? []
                    await send(.hintStrokesLoaded(paths))
                }

            case let .hintStrokesLoaded(paths):
                state.hintStrokes = paths
                return .none

            case .next:
                if state.index < state.questions.count - 1 { state.index += 1 }
                state.hintShown = false
                state.hintStrokes = nil
                return .none

            case .prev:
                if state.index > 0 { state.index -= 1 }
                state.hintShown = false
                state.hintStrokes = nil
                return .none

            case .finish:
                state.phase = .review
                return .none

            case .exitToSetup:
                state.phase = .setup
                state.questions = []
                state.drawings = [:]
                state.index = 0
                state.hintShown = false
                state.hintStrokes = nil
                return .none

            case let .favoritesLoaded(byMode):
                state.favorites = byMode
                return loadFavoriteItems(state.mode, state.favoriteIDs,
                                         kanji: state.kanji, glosses: state.glossesByID)

            case let .toggleFavorite(item):
                var ids = state.favoriteIDs
                if let at = ids.firstIndex(of: item.id) {
                    ids.remove(at: at)
                } else {
                    ids.append(item.id)
                }
                state.favorites[state.mode.rawValue] = ids
                // Keep the resolved list in step so the count on the setup screen
                // is right the moment the learner goes back to it.
                if let at = state.favoriteItems.firstIndex(where: { $0.id == item.id }) {
                    state.favoriteItems.remove(at: at)
                } else {
                    state.favoriteItems.append(item)
                }
                let byMode = state.favorites
                return .run { _ in await favoriteStore.save(byMode) }

            case let .setUseFavorites(on):
                state.useFavorites = on
                return persist(state)

            case let .favoriteItemsLoaded(items):
                state.favoriteItems = items
                return .none

            case .restart:
                state.phase = .setup
                state.questions = []
                state.drawings = [:]
                state.index = 0
                return .none
            }
        }
    }
}
