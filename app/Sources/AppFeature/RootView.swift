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

    public var body: some View {
        ZStack {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                HomeView(store: store)
            } destination: { store in
                pathDestination(store)
            }

            // Study / quiz / practice and settings are presented as full-screen
            // in-app overlays rather than a .fullScreenCover / .sheet: buttons
            // inside Mac Catalyst modal presentations are unreliable, so their
            // close buttons could fail. Plain buttons in the normal hierarchy
            // (like these) always respond.
            if let sessionStore = store.scope(state: \.session, action: \.session.presented) {
                SessionCover(store: store, sessionStore: sessionStore)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
                    .zIndex(2)
            }
            if store.showSettings {
                settingsOverlay
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.session != nil)
        .animation(.easeOut(duration: 0.2), value: store.showSettings)
        .tint(Palette.accent)
        .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
        .task { store.send(.onAppear) }
    }

    /// Settings as a full-screen overlay with the shared header (✕ top-left +
    /// title) — the same presentation as the study-plan overlay.
    private var settingsOverlay: some View {
        ReminderView(store: store.scope(state: \.reminder, action: \.reminder))
            .safeAreaInset(edge: .top) {
                OverlayHeader(title: L.settings[appLanguage]) {
                    store.send(.setShowSettings(false))
                }
            }
            .background(Palette.background.ignoresSafeArea())
    }
}

/// The full-screen study session: the mode view inside its own NavigationStack
/// with a single ✕ that returns to Home. The ✕ is a plain in-content button (via
/// a top safe-area inset), not a toolbar item — toolbar buttons are unreliable
/// on Mac Catalyst. No sidebar/tabs while studying.
private struct SessionCover: View {
    @Bindable var store: StoreOf<RootFeature>
    let sessionStore: StoreOf<RootFeature.Session>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack(path: $store.scope(state: \.sessionPath, action: \.sessionPath)) {
            sessionView(sessionStore)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top) {
                    HStack {
                        CircleButton("xmark") { store.send(.session(.dismiss)) }
                            .accessibilityLabel(L.close[appLanguage])
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .readableWidth(sizeClass)
                    .padding(.top, 6).padding(.bottom, 2)
                }
        } destination: { store in
            pathDestination(store)
        }
        .tint(Palette.accent)
        .background(Palette.background.ignoresSafeArea())
    }
}

@ViewBuilder
private func sessionView(_ store: StoreOf<RootFeature.Session>) -> some View {
    switch store.case {
    case let .worksheet(s):
        WorksheetView(store: s)
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
        KanjiListPathView(title: s.title, items: s.kanji, glosses: s.glosses,
                          onSelect: { s.send(.kanjiTapped($0)) })
    case let .kanji(s):
        KanjiDetailView(store: s)
    case let .word(s):
        WordDetailView(store: s)
    case let .writing(s):
        KanjiWritingView(store: s)
    case let .dictionary(s):
        DictionaryPathView(store: s)
    case let .wordDictionary(s):
        WordDictionaryView(store: s)
    }
}

/// A pushed level's kanji list (from the 사전 or a level tap) with the shared
/// custom back header — matches every other pushed screen (no system back bar).
private struct KanjiListPathView: View {
    let title: String
    let items: [Kanji]
    var glosses: [Int: [String: String]] = [:]
    let onSelect: (Kanji) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        KanjiCardList(items: items, glosses: glosses, onSelect: onSelect)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                NavHeader(title: title) { dismiss() }
                    .background(Palette.background)
            }
    }
}

/// The localized meaning of a word, falling back to English.
func wordMeaningText(_ word: WordEntry, _ language: AppLanguage) -> String? {
    switch language {
    case .ko: word.meaningKo ?? word.meaningEn
    case .ja: word.meaningJa ?? word.meaningEn
    case .zh: word.meaningZh ?? word.meaningEn
    case .en: word.meaningEn
    }
}

// MARK: - Dictionary (opened from the 학습 hub)

/// The 사전 browse: level list + search over its own kanji snapshot. Tapping a
/// level or a searched kanji delegates up to `RootFeature`, which pushes next.
private struct DictionaryPathView: View {
    @Bindable var store: StoreOf<DictionaryFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

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
                    .readableWidth(sizeClass)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                NavHeader(title: L.kanjiDictionary[appLanguage]) { dismiss() }
                SearchField(text: searchBinding, placeholder: L.searchPrompt[appLanguage])
                    .padding(.horizontal, 16)
                    .readableWidth(sizeClass)
            }
            .padding(.bottom, 6)
            .background(Palette.background)
        }
    }
}

// MARK: - Word dictionary (opened from Home)

/// The 단어사전 browse: a level picker listing that level's words (common first),
/// or a full-word search. Selecting a word delegates up to push its detail.
private struct WordDictionaryView: View {
    @Bindable var store: StoreOf<WordDictionaryFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }
    private var levelBinding: Binding<String> {
        Binding(get: { store.level }, set: { store.send(.levelSelected($0)) })
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if store.isSearching {
                wordList(store.searchResults)
            } else {
                VStack(spacing: 12) {
                    Picker("", selection: levelBinding) {
                        ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.top, 12)
                    .readableWidth(sizeClass)
                    wordList(store.words)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                NavHeader(title: L.wordDictionary[appLanguage]) { dismiss() }
                SearchField(text: searchBinding, placeholder: L.wordSearchPrompt[appLanguage])
                    .padding(.horizontal, 16)
                    .readableWidth(sizeClass)
            }
            .padding(.bottom, 6)
            .background(Palette.background)
        }
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private func wordList(_ words: [WordEntry]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(words) { word in
                    Button { store.send(.wordSelected(word)) } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                RubyWord(word.surface, reading: word.reading, size: 22)
                                if let meaning = wordMeaningText(word, appLanguage), !meaning.isEmpty {
                                    Text(meaning).font(.kawaii(14, language: appLanguage))
                                        .foregroundStyle(Palette.inkSoft)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        .roundedCard()
                    }
                    .buttonStyle(.bouncy)
                }
                if words.isEmpty {
                    Text(L.noWordsFound[appLanguage])
                        .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
                }
            }
            .padding(16)
            .readableWidth(sizeClass)
        }
        .scrollIndicators(.hidden)
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
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, kanji in
                        KanjiListRow(kanji: kanji,
                                     meaning: kanjiGloss(glosses[kanji.id] ?? [:], appLanguage),
                                     tint: Palette.tint(index),
                                     language: appLanguage) { onSelect(kanji) }
                            .popIn(delay: min(Double(index), 6) * 0.04)
                    }
                    if items.isEmpty {
                        Text(L.noKanjiFound[appLanguage])
                            .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
                    }
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
        }
    }
}
