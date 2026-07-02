import ComposableArchitecture
import DesignSystem
import KanjiDetail
import KanjiListFeature
import Practice
import Reminders
import Review
import SharedModels
import SwiftUI
import TestMode
import Worksheet
import WritingCanvas

/// The app shell. Three destinations — 오늘 / 사전 / 설정 — plus a full-screen
/// study session presented over everything. It adapts to the size class:
/// - **regular** (iPad): a `NavigationSplitView` (sidebar destinations → content).
/// - **compact** (iPhone): a bottom `TabView`.
/// Both attach the same `.fullScreenCover` for the immersive study session.
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
        .fullScreenCover(
            item: $store.scope(state: \.session, action: \.session)
        ) { sessionStore in
            SessionCover(store: store, sessionStore: sessionStore)
        }
    }
}

/// The full-screen study session: the mode view inside its own NavigationStack
/// with a single ✕ that returns to Home. No sidebar/tabs while studying.
private struct SessionCover: View {
    let store: StoreOf<RootFeature>
    let sessionStore: StoreOf<RootFeature.Session>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    var body: some View {
        NavigationStack {
            sessionView(sessionStore)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.send(.session(.dismiss)) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .accessibilityLabel(L.close[appLanguage])
                    }
                }
        }
        .tint(Palette.accent)
    }
}

@ViewBuilder
private func sessionView(_ store: StoreOf<RootFeature.Session>) -> some View {
    switch store.case {
    case let .worksheet(s):
        WorksheetView(store: s)
    case let .test(s):
        TestView(store: s)
    case let .practice(s):
        PracticeView(store: s)
    }
}

/// The shared destination builder for the dictionary navigation stack.
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

// MARK: - Regular width (iPad): split view

struct RegularRootView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    private var destinationBinding: Binding<RootFeature.Destination?> {
        Binding(
            get: { store.destination },
            set: { if let d = $0 { store.send(.destinationSelected(d)) } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: destinationBinding) {
                Label(L.today[appLanguage], systemImage: "sun.max")
                    .tag(RootFeature.Destination.home)
                Label(L.study[appLanguage], systemImage: "pencil.and.outline")
                    .tag(RootFeature.Destination.study)
                Label(L.dictionary[appLanguage], systemImage: "character.book.closed")
                    .tag(RootFeature.Destination.dictionary)
                Label(L.settings[appLanguage], systemImage: "gearshape")
                    .tag(RootFeature.Destination.settings)
            }
            .navigationTitle("漢字")
        } detail: {
            detailColumn
        }
    }

    @ViewBuilder private var detailColumn: some View {
        switch store.destination {
        case .home:
            NavigationStack { HomeView(store: store) }
        case .study:
            NavigationStack { StudyHubView(store: store) }
        case .dictionary:
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                DictionaryColumn(store: store)
            } destination: { store in
                pathDestination(store)
            }
        case .settings:
            NavigationStack {
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            }
        }
    }
}

// MARK: - Compact width (iPhone): tab bar

struct CompactRootView: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    private var tabBinding: Binding<RootFeature.Destination> {
        Binding(get: { store.destination }, set: { store.send(.destinationSelected($0)) })
    }

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack {
                HomeView(store: store)
            }
            .tag(RootFeature.Destination.home)
            .tabItem { Label(L.today[appLanguage], systemImage: "sun.max") }

            NavigationStack {
                StudyHubView(store: store)
            }
            .tag(RootFeature.Destination.study)
            .tabItem { Label(L.study[appLanguage], systemImage: "pencil.and.outline") }

            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                DictionaryColumn(store: store)
            } destination: { store in
                pathDestination(store)
            }
            .tag(RootFeature.Destination.dictionary)
            .tabItem { Label(L.dictionary[appLanguage], systemImage: "character.book.closed") }

            NavigationStack {
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            }
            .tag(RootFeature.Destination.settings)
            .tabItem { Label(L.settings[appLanguage], systemImage: "gearshape") }
        }
    }
}

// MARK: - Dictionary

/// The 사전 root: level browse + search, with a segmented toggle to the 단어장
/// (wordbook). Tapping a level opens its kanji list; tapping a kanji/word drills.
private struct DictionaryColumn: View {
    @Bindable var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @State private var showWordbook = false

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    private var searching: Bool {
        !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if searching {
                KanjiCardList(
                    items: store.review.kanji.elements.filter { searchMatches($0, store.searchText) },
                    onSelect: { store.send(.kanjiSelected($0)) })
            } else if showWordbook {
                WordReviewHubView(wordStore: store.scope(state: \.wordReview, action: \.wordReview))
            } else {
                levelList
            }
        }
        .navigationTitle(L.dictionary[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: searchBinding, prompt: L.searchPrompt[appLanguage])
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $showWordbook) {
                    Text(L.kanji[appLanguage]).tag(false)
                    Text(L.words[appLanguage]).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
    }

    private var levelList: some View {
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
