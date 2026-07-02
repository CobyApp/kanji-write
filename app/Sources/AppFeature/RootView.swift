import ComposableArchitecture
import DesignSystem
import KanjiDetail
import KanjiListFeature
import Reminders
import Review
import SharedModels
import SwiftUI
import WritingCanvas

/// The app shell. It adapts to the horizontal size class:
/// - **regular** (iPad, full-width): a 3-column `NavigationSplitView` whose
///   detail column is the navigation stack.
/// - **compact** (iPhone, Slide Over): a bottom `TabView`, each tab a
///   `NavigationStack` that drills kanji ↔ word ↔ writing to any depth.
public struct RootView: View {
    @Bindable public var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(store: StoreOf<RootFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if sizeClass == .compact {
                CompactRootView(store: store)
            } else {
                RegularRootView(store: store)
            }
        }
        .tint(Palette.accent)
        .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
        .task { store.send(.onAppear) }
    }
}

/// The shared destination builder for every navigation stack (both layouts).
@ViewBuilder
func pathDestination(_ store: StoreOf<RootFeature.Path>) -> some View {
    switch store.case {
    case let .kanjiList(s):
        KanjiCardList(items: s.kanji, onSelect: { s.send(.kanjiTapped($0)) })
            .navigationTitle(s.title)
    case let .kanji(s):
        KanjiDetailView(store: s)
    case let .word(s):
        WordDetailView(store: s)
    case let .writing(s):
        KanjiWritingView(store: s)
    }
}

// MARK: - Regular width (iPad): 3-column split view

struct RegularRootView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    private var sidebarBinding: Binding<RootFeature.SidebarSelection?> {
        Binding(get: { store.sidebar }, set: { store.send(.sidebarSelected($0)) })
    }

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
                .navigationBarTitleDisplayMode(.inline)
        } detail: {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                ZStack {
                    Palette.background.ignoresSafeArea()
                    ContentUnavailableView(L.pickKanji[appLanguage],
                                           systemImage: "hand.tap",
                                           description: Text(L.pickKanjiHint[appLanguage]))
                }
            } destination: { store in
                pathDestination(store)
            }
        }
    }

    private var sidebar: some View {
        List(selection: sidebarBinding) {
            Section {
                Label(L.study[appLanguage], systemImage: "pencil.and.outline")
                    .tag(RootFeature.SidebarSelection.study)
                Label(L.words[appLanguage], systemImage: "character.book.closed")
                    .tag(RootFeature.SidebarSelection.words)
            }
            Section(L.browse[appLanguage]) {
                ForEach(levels()) { level in
                    let count = kanjiIn(store.review.kanji.elements, in: level).count
                    HStack {
                        Text(level.label).font(.kawaii(16, weight: .semibold))
                        Spacer()
                        Text("\(count)").font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
                    }
                    .tag(RootFeature.SidebarSelection.level(level.id))
                }
            }
            Section {
                Label(L.settings[appLanguage], systemImage: "gearshape")
                    .tag(RootFeature.SidebarSelection.settings)
            }
        }
        .navigationTitle(L.kanji[appLanguage])
        .searchable(text: searchBinding, placement: .sidebar, prompt: L.searchPrompt[appLanguage])
    }

    @ViewBuilder private var contentColumn: some View {
        if !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            KanjiCardList(
                items: store.review.kanji.elements.filter { searchMatches($0, store.searchText) },
                onSelect: { store.send(.kanjiSelected($0)) })
                .navigationTitle(L.search[appLanguage])
        } else {
            switch store.sidebar {
            case .study, .none:
                StudyHubView(reviewStore: store.scope(state: \.review, action: \.review))
            case .words:
                WordReviewHubView(wordStore: store.scope(state: \.wordReview, action: \.wordReview))
            case .settings:
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            case let .level(id):
                let level = levels().first { $0.id == id }
                KanjiCardList(
                    items: level.map { kanjiIn(store.review.kanji.elements, in: $0) } ?? [],
                    onSelect: { store.send(.kanjiSelected($0)) })
                    .navigationTitle(level?.label ?? L.browse[appLanguage])
            }
        }
    }
}

// MARK: - Compact width (iPhone): tab bar + navigation stacks

struct CompactRootView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    private var tabBinding: Binding<RootFeature.Tab> {
        Binding(get: { store.tab }, set: { store.send(.tabSelected($0)) })
    }

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                StudyHubView(reviewStore: store.scope(state: \.review, action: \.review))
            } destination: { store in
                pathDestination(store)
            }
            .tag(RootFeature.Tab.study)
            .tabItem { Label(L.study[appLanguage], systemImage: "pencil.and.outline") }

            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                WordReviewHubView(wordStore: store.scope(state: \.wordReview, action: \.wordReview))
            } destination: { store in
                pathDestination(store)
            }
            .tag(RootFeature.Tab.words)
            .tabItem { Label(L.words[appLanguage], systemImage: "character.book.closed") }

            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                BrowseColumn(store: store)
            } destination: { store in
                pathDestination(store)
            }
            .tag(RootFeature.Tab.browse)
            .tabItem { Label(L.browse[appLanguage], systemImage: "square.grid.2x2") }

            NavigationStack {
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            }
            .tag(RootFeature.Tab.settings)
            .tabItem { Label(L.settings[appLanguage], systemImage: "gearshape") }
        }
    }
}

/// The compact 一覧 tab root: a level drill-down (or search results). Tapping a
/// level opens its kanji list on the stack.
private struct BrowseColumn: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    private var searching: Bool {
        !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Group {
            if searching {
                KanjiCardList(
                    items: store.review.kanji.elements.filter { searchMatches($0, store.searchText) },
                    onSelect: { store.send(.kanjiSelected($0)) })
            } else {
                levelList
            }
        }
        .navigationTitle(L.browse[appLanguage])
        .searchable(text: searchBinding, prompt: L.searchPrompt[appLanguage])
    }

    private var levelList: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(levels()) { level in
                        let count = kanjiIn(store.review.kanji.elements, in: level).count
                        Button { store.send(.levelSelected(level)) } label: {
                            HStack(spacing: 14) {
                                Text(level.label)
                                    .font(.kawaii(17, weight: .semibold)).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(count)").font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            .roundedCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Shared

/// A scrolling list of kanji cards, reused by search results and every level list.
struct KanjiCardList: View {
    let items: [Kanji]
    let onSelect: (Kanji) -> Void
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, kanji in
                        let tint = Palette.tint(index)
                        Button { onSelect(kanji) } label: {
                            HStack(spacing: 14) {
                                PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                                           size: 48, fontSize: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kanji.onReadings.joined(separator: "、"))
                                        .font(.kawaii(14, weight: .semibold)).foregroundStyle(Palette.ink)
                                    Text(kanji.kunReadings.joined(separator: "、"))
                                        .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
                                }
                                Spacer()
                            }
                            .roundedCard()
                        }
                        .buttonStyle(.plain)
                    }
                    if items.isEmpty {
                        Text(L.noKanjiFound[appLanguage])
                            .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
    }
}
