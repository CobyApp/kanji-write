import ComposableArchitecture
import DictionaryClient
import SharedModels

/// A browsable level within a classification (one JLPT level or one school grade).
public struct KanjiLevel: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case jlpt(String)  // "N5" … "N1"
        case grade(Int)    // 1…6 (小学), 8 (中学)
    }

    public let kind: Kind
    public init(kind: Kind) { self.kind = kind }

    public var id: String {
        switch kind {
        case let .jlpt(level): "jlpt:\(level)"
        case let .grade(grade): "grade:\(grade)"
        }
    }

    public var label: String {
        switch kind {
        case let .jlpt(level): level
        case .grade(8): "中学"
        case let .grade(grade): "小\(grade)"
        }
    }
}

/// The ordered levels for a classification.
public func levels(for classification: Classification) -> [KanjiLevel] {
    switch classification {
    case .jlpt:
        ["N5", "N4", "N3", "N2", "N1"].map { KanjiLevel(kind: .jlpt($0)) }
    case .grade:
        [1, 2, 3, 4, 5, 6, 8].map { KanjiLevel(kind: .grade($0)) }
    }
}

/// The kanji belonging to a level.
public func kanjiIn(_ all: [Kanji], in level: KanjiLevel) -> [Kanji] {
    all.filter { k in
        switch level.kind {
        case let .jlpt(l): k.jlptLevel == l
        case let .grade(g): k.grade == g
        }
    }
}

/// Free-text match: the literal, or any on/kun reading (kun dots ignored).
public func searchMatches(_ k: Kanji, _ query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return false }
    if k.literal.contains(q) { return true }
    let readings = (k.onReadings + k.kunReadings).map { $0.replacingOccurrences(of: ".", with: "") }
    return readings.contains { $0.contains(q) }
}

@Reducer
public struct KanjiListFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var isLoading = false
        public var loadError: String?
        public var selectedLevel: KanjiLevel?
        public var searchText: String = ""
        public init() {}

        /// Kanji in the selected level (empty if no level chosen).
        public var levelKanji: [Kanji] {
            guard let selectedLevel else { return [] }
            return kanjiIn(kanji.elements, in: selectedLevel)
        }

        /// Search results across all kanji (used when `searchText` is non-empty).
        public var searchResults: [Kanji] {
            kanji.elements.filter { searchMatches($0, searchText) }
        }

        public var isSearching: Bool {
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public enum Action: Equatable {
        case onAppear
        case kanjiLoaded([Kanji])
        case loadFailed(String)
        case kanjiTapped(Kanji)
        case levelSelected(KanjiLevel)
        case levelCleared
        case searchChanged(String)
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.kanji.isEmpty else { return .none }
                state.isLoading = true
                state.loadError = nil
                return .run { send in
                    do {
                        await send(.kanjiLoaded(try await dictionaryClient.allKanji()))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
            case let .kanjiLoaded(kanji):
                state.isLoading = false
                state.kanji = IdentifiedArray(uniqueElements: kanji)
                return .none
            case let .loadFailed(message):
                state.isLoading = false
                state.loadError = message
                return .none
            case .kanjiTapped:
                return .none
            case let .levelSelected(level):
                state.selectedLevel = level
                return .none
            case .levelCleared:
                state.selectedLevel = nil
                return .none
            case let .searchChanged(text):
                state.searchText = text
                return .none
            }
        }
    }
}
