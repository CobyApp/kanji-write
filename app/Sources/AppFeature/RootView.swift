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

/// The app shell — one Home dashboard holding every feature. Details (kanji /
/// word / dictionary / writing) push onto a single navigation stack; study,
/// review, and practice open as full-screen sessions; settings is a sheet.
/// No tab bar or sidebar.
public struct RootView: View {
    @Bindable public var store: StoreOf<RootFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<RootFeature>) {
        self.store = store
    }

    private var settingsShown: Binding<Bool> {
        Binding(get: { store.showSettings }, set: { store.send(.setShowSettings($0)) })
    }

    public var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            HomeView(store: store)
        } destination: { store in
            pathDestination(store)
        }
        .tint(Palette.accent)
        .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
        .task { store.send(.onAppear) }
        .fullScreenCover(
            item: $store.scope(state: \.session, action: \.session)
        ) { sessionStore in
            SessionCover(store: store, sessionStore: sessionStore)
        }
        .sheet(isPresented: settingsShown) {
            NavigationStack {
                ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L.close[appLanguage]) { store.send(.setShowSettings(false)) }
                        }
                    }
            }
            .tint(Palette.accent)
            .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
        }
    }
}

/// The full-screen study session: the mode view inside its own NavigationStack
/// with a single ✕ that returns to Home. No sidebar/tabs while studying.
private struct SessionCover: View {
    @Bindable var store: StoreOf<RootFeature>
    let sessionStore: StoreOf<RootFeature.Session>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    var body: some View {
        NavigationStack(path: $store.scope(state: \.sessionPath, action: \.sessionPath)) {
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
        } destination: { store in
            pathDestination(store)
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
    case let .quiz(s):
        QuizView(store: s)
    }
}

/// The shared destination builder for the dictionary navigation stack.
@ViewBuilder
func pathDestination(_ store: StoreOf<RootFeature.Path>) -> some View {
    switch store.case {
    case let .kanjiList(s):
        KanjiCardList(items: s.kanji, glosses: s.glosses, onSelect: { s.send(.kanjiTapped($0)) })
            .navigationTitle(s.title)
            .navigationBarTitleDisplayMode(.inline)
    case let .kanji(s):
        KanjiDetailView(store: s)
    case let .word(s):
        WordDetailView(store: s)
    case let .writing(s):
        KanjiWritingView(store: s)
    case let .dictionary(s):
        DictionaryPathView(store: s)
    }
}

// MARK: - Dictionary (opened from the 학습 hub)

/// The 사전 browse: level list + search over its own kanji snapshot. Tapping a
/// level or a searched kanji delegates up to `RootFeature`, which pushes next.
private struct DictionaryPathView: View {
    @Bindable var store: StoreOf<DictionaryFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                KanjiCardList(items: store.searchResults, glosses: store.glosses,
                              onSelect: { store.send(.kanjiSelected($0)) })
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(levels().enumerated()), id: \.element.id) { index, level in
                            let count = kanjiIn(store.kanji, in: level).count
                            let tint = Palette.tint(index)
                            Button { store.send(.levelSelected(level)) } label: {
                                HStack(spacing: 14) {
                                    Circle().fill(tint.accent).frame(width: 10, height: 10)
                                    Text(level.label)
                                        .font(.kawaii(17, weight: .bold)).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text("\(count)").font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Palette.inkSoft)
                                }
                                .roundedCard()
                            }
                            .buttonStyle(.bouncy)
                            .popIn(delay: Double(index) * 0.05)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(L.dictionary[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: searchBinding, prompt: L.searchPrompt[appLanguage])
    }
}

// MARK: - Shared

/// The kanji's meaning for the selected language, falling back deterministically.
func kanjiGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
}

/// A scrolling list of kanji cards, reused by search results and every level list.
/// Each row leads with the kanji's meaning (뜻음) in the selected language for
/// easier memorization, with the Japanese on/kun readings underneath.
struct KanjiCardList: View {
    let items: [Kanji]
    var glosses: [Int: [String: String]] = [:]
    let onSelect: (Kanji) -> Void
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, kanji in
                        let tint = Palette.tint(index)
                        let meaning = kanjiGloss(glosses[kanji.id] ?? [:], appLanguage)
                        let readings = (kanji.onReadings + kanji.kunReadings).joined(separator: "、")
                        Button { onSelect(kanji) } label: {
                            HStack(spacing: 14) {
                                PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent,
                                           size: 48, fontSize: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    if let meaning, !meaning.isEmpty {
                                        Text(meaning)
                                            .font(.kawaii(15, weight: .bold, language: appLanguage))
                                            .foregroundStyle(Palette.ink)
                                    }
                                    if !readings.isEmpty {
                                        Text(readings)
                                            .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
                                    }
                                }
                                Spacer()
                            }
                            .roundedCard()
                        }
                        .buttonStyle(.bouncy)
                        .popIn(delay: min(Double(index), 6) * 0.04)
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
