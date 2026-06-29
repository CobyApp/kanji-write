import ComposableArchitecture
import DesignSystem
import KanjiDetail
import KanjiListFeature
import Reminders
import Review
import SharedModels
import SwiftUI
import WritingCanvas

public struct RootView: View {
    @Bindable public var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("classification") private var classification: Classification = .jlpt

    public init(store: StoreOf<RootFeature>) {
        self.store = store
    }

    private var sidebarBinding: Binding<RootFeature.SidebarSelection?> {
        Binding(get: { store.sidebar }, set: { store.send(.sidebarSelected($0)) })
    }

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
                .navigationBarTitleDisplayMode(.inline)
        } detail: {
            detailColumn
        }
        .tint(Palette.accent)
        .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
        .task { store.send(.onAppear) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: sidebarBinding) {
            Section {
                Label("学習", systemImage: "pencil.and.outline")
                    .tag(RootFeature.SidebarSelection.study)
            }
            Section("一覧") {
                ForEach(levels(for: classification)) { level in
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
            kanjiListColumn(
                title: "検索",
                items: store.review.kanji.elements.filter { searchMatches($0, store.searchText) })
        } else {
            switch store.sidebar {
            case .study, .none:
                StudyHubView(reviewStore: store.scope(state: \.review, action: \.review))
            case .settings:
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            case let .level(id):
                let level = levels(for: classification).first { $0.id == id }
                kanjiListColumn(
                    title: level?.label ?? "一覧",
                    items: level.map { kanjiIn(store.review.kanji.elements, in: $0) } ?? [])
            }
        }
    }

    private func kanjiListColumn(title: String, items: [Kanji]) -> some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, kanji in
                        let tint = Palette.tint(index)
                        Button { store.send(.kanjiSelected(kanji)) } label: {
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
        .navigationTitle(title)
    }

    // MARK: Detail

    @ViewBuilder private var detailColumn: some View {
        NavigationStack {
            Group {
                if let detailStore = store.scope(state: \.detail, action: \.detail) {
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
