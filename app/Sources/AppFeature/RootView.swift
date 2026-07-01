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
/// - **regular** (iPad, full-width): a 3-column `NavigationSplitView`.
/// - **compact** (iPhone, Slide Over): a bottom `TabView`, each tab a
///   `NavigationStack` that pushes the selected kanji's detail → writing canvas.
///
/// Both layouts read the same `RootFeature` store; only navigation differs.
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

// MARK: - Regular width (iPad): 3-column split view

struct RegularRootView: View {
    @Bindable var store: StoreOf<RootFeature>

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
            detailColumn
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: sidebarBinding) {
            Section {
                Label("学習", systemImage: "pencil.and.outline")
                    .tag(RootFeature.SidebarSelection.study)
            }
            Section("一覧") {
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
                Label("設定", systemImage: "gearshape")
                    .tag(RootFeature.SidebarSelection.settings)
            }
        }
        .navigationTitle("漢字")
        .searchable(text: searchBinding, placement: .sidebar, prompt: "漢字・読みで検索")
    }

    // MARK: Content

    @ViewBuilder private var contentColumn: some View {
        if !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            KanjiCardList(
                items: store.review.kanji.elements.filter { searchMatches($0, store.searchText) },
                onSelect: { store.send(.kanjiSelected($0)) })
                .navigationTitle("検索")
        } else {
            switch store.sidebar {
            case .study, .none:
                StudyHubView(reviewStore: store.scope(state: \.review, action: \.review))
            case .settings:
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            case let .level(id):
                let level = levels().first { $0.id == id }
                KanjiCardList(
                    items: level.map { kanjiIn(store.review.kanji.elements, in: $0) } ?? [],
                    onSelect: { store.send(.kanjiSelected($0)) })
                    .navigationTitle(level?.label ?? "一覧")
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detailColumn: some View {
        NavigationStack {
            Group {
                if let detailStore = store.scope(state: \.detail, action: \.detail.presented) {
                    KanjiDetailView(store: detailStore)
                } else {
                    ZStack {
                        Palette.background.ignoresSafeArea()
                        ContentUnavailableView("漢字を選んでください",
                                               systemImage: "hand.tap",
                                               description: Text("一覧や学習から漢字を選ぶと\nここに表示されます"))
                    }
                }
            }
            .navigationDestination(
                item: $store.scope(state: \.writing, action: \.writing)
            ) { writingStore in
                KanjiWritingView(store: writingStore)
            }
        }
    }
}

// MARK: - Compact width (iPhone): tab bar + navigation stacks

struct CompactRootView: View {
    @Bindable var store: StoreOf<RootFeature>

    private var tabBinding: Binding<RootFeature.Tab> {
        Binding(get: { store.tab }, set: { store.send(.tabSelected($0)) })
    }

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack {
                StudyHubView(reviewStore: store.scope(state: \.review, action: \.review))
                    .kanjiNavigation(store: store)
            }
            .tag(RootFeature.Tab.study)
            .tabItem { Label("学習", systemImage: "pencil.and.outline") }

            NavigationStack {
                BrowseColumn(store: store)
                    .kanjiNavigation(store: store)
            }
            .tag(RootFeature.Tab.browse)
            .tabItem { Label("一覧", systemImage: "square.grid.2x2") }

            NavigationStack {
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            }
            .tag(RootFeature.Tab.settings)
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}

/// The compact 一覧 tab root: a level drill-down (or search results), each level
/// pushing its kanji list.
private struct BrowseColumn: View {
    @Bindable var store: StoreOf<RootFeature>

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
        .navigationTitle("一覧")
        .searchable(text: searchBinding, prompt: "漢字・読みで検索")
        .navigationDestination(for: KanjiLevel.self) { level in
            KanjiCardList(
                items: kanjiIn(store.review.kanji.elements, in: level),
                onSelect: { store.send(.kanjiSelected($0)) })
                .navigationTitle(level.label)
        }
    }

    private var levelList: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(levels()) { level in
                        let count = kanjiIn(store.review.kanji.elements, in: level).count
                        NavigationLink(value: level) {
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

/// A scrolling list of kanji cards, reused by the search results and every
/// level list across both layouts.
struct KanjiCardList: View {
    let items: [Kanji]
    let onSelect: (Kanji) -> Void

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
                        Text("該当する漢字がありません")
                            .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
    }
}

/// Attaches the detail → writing push chain to a compact tab's stack. Both tabs
/// that open kanji share `RootFeature`'s single detail/writing state;
/// `tabSelected` clears it on switch so it never leaks between stacks.
private struct KanjiNavigation: ViewModifier {
    @Bindable var store: StoreOf<RootFeature>

    func body(content: Content) -> some View {
        content.navigationDestination(
            item: $store.scope(state: \.detail, action: \.detail)
        ) { detailStore in
            KanjiDetailView(store: detailStore)
                .navigationDestination(
                    item: $store.scope(state: \.writing, action: \.writing)
                ) { writingStore in
                    KanjiWritingView(store: writingStore)
                }
        }
    }
}

private extension View {
    func kanjiNavigation(store: StoreOf<RootFeature>) -> some View {
        modifier(KanjiNavigation(store: store))
    }
}
