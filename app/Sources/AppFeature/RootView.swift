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
    /// First-run setup shown once. Installs from before onboarding existed
    /// already chose a plan, so they skip it (see `needsOnboarding`).
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var showOnboarding = false

    public init(store: StoreOf<RootFeature>) {
        self.store = store
    }

    /// A fresh install, as opposed to an update from before onboarding: those
    /// already have a study plan saved.
    private var needsOnboarding: Bool {
        !onboardingDone && UserDefaults.standard.object(forKey: "targetLevel") == nil
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
            if showOnboarding {
                OnboardingView {
                    onboardingDone = true
                    withAnimation(.easeOut(duration: 0.25)) { showOnboarding = false }
                }
                .transition(.opacity)
                .zIndex(4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.session != nil)
        .animation(.easeOut(duration: 0.2), value: store.showSettings)
        .tint(Palette.accent)
        // The palette is a fixed light pastel set with no dark variants. Left to
        // follow the system, dark mode put system controls (pickers, steppers,
        // the drawing canvas's ink) in dark styling on white cards — strokes
        // drawn in white on a white canvas vanished.
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
        .task {
            if needsOnboarding {
                appLanguage = OnboardingView.deviceLanguage
                showOnboarding = true
            } else {
                onboardingDone = true
            }
            store.send(.onAppear)
        }
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
                        CircleButton("xmark") { closeTapped() }
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

    /// The ✕ is context-aware for the 칸켄 hub: while playing a section it steps
    /// back to the section list; otherwise (hub, other sessions) it closes.
    /// ✕ steps back one level rather than always leaving: out of a running
    /// section to the hub, out of a writing run to its range picker. The level
    /// and range you just set are right there, and the next run nearly always
    /// reuses them — dropping to Home would make you walk back in every time.
    private func closeTapped() {
        switch sessionStore.case {
        case let .kanken(kanken) where kanken.isPlaying:
            kanken.send(.exitToHub)
        case let .practice(practice) where practice.phase != .setup:
            practice.send(.exitToSetup)
        default:
            store.send(.session(.dismiss))
        }
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
    case let .kanken(s):
        KankenExamView(store: s)
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
    case let .yojiDictionary(s):
        YojiDictionaryView(store: s)
    case let .yojiDetail(s):
        YojiDetailView(store: s)
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
                NavHeader(title: title, onBack: { dismiss() }) { GridToggleButton() }
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
                            .popInRow(index, step: 0.05)
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
                NavHeader(title: L.kanjiDictionary[appLanguage], onBack: { dismiss() }) { GridToggleButton() }
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
    @AppStorage("dictGridMode") private var gridMode = false
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .compact ? 120 : 150), spacing: 12)]
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if store.isSearching {
                wordList(store.visibleResults)
            } else {
                VStack(spacing: 12) {
                    levelChips
                    wordList(store.visibleWords)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                NavHeader(title: (store.expressions ? L.expressionDictionary : L.wordDictionary)[appLanguage],
                          onBack: { dismiss() }) { GridToggleButton() }
                SearchField(text: searchBinding,
                            placeholder: (store.expressions ? L.expressionSearchPrompt : L.wordSearchPrompt)[appLanguage])
                    .padding(.horizontal, 16)
                    .readableWidth(sizeClass)
            }
            .padding(.bottom, 6)
            .background(Palette.background)
        }
        .task { store.send(.onAppear) }
    }

    /// A horizontal scrolling row of level chips — handles 漢検's ten levels
    /// (10級〜1級) without the cramping a segmented picker would force on iPhone.
    private var levelChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(examType.levels, id: \.self) { level in
                    let selected = store.level == level
                    Button { store.send(.levelSelected(level)) } label: {
                        Text(level)
                            .font(.kawaii(14, weight: .bold))
                            .foregroundStyle(selected ? .white : Palette.ink)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(selected ? Palette.accent : Palette.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                selected ? .clear : Palette.ink.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(.bouncy)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .readableWidth(sizeClass)
    }

    @ViewBuilder
    private func wordList(_ words: [WordEntry]) -> some View {
        ScrollView {
            if words.isEmpty {
                Text(L.noWordsFound[appLanguage])
                    .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
            } else if gridMode {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(words) { word in wordGridCell(word) }
                }
                .padding(16)
                .readableWidth(sizeClass)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(words) { word in wordRow(word) }
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func wordRow(_ word: WordEntry) -> some View {
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

    /// A compact grid cell: reading (furigana) + word + meaning, each on a single
    /// line that shrinks to fit the cell width so every card is the same height.
    private func wordGridCell(_ word: WordEntry) -> some View {
        Button { store.send(.wordSelected(word)) } label: {
            VStack(spacing: 4) {
                if !word.reading.isEmpty {
                    Text(word.reading)
                        .font(.kawaii(10, weight: .semibold)).foregroundStyle(Palette.pink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                Text(word.surface)
                    .font(.kawaiiJP(22, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.4)
                if let meaning = wordMeaningText(word, appLanguage), !meaning.isEmpty {
                    Text(meaning)
                        .font(.kawaii(12, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(.vertical, 14).padding(.horizontal, 8)
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }
}

// MARK: - 사자성어(四字熟語) dictionary

/// The 四字熟語 dictionary: a per-級 chip filter + search, each row showing the
/// idiom with its reading and meaning. Read-only (no drill-in).
private struct YojiDictionaryView: View {
    @Bindable var store: StoreOf<YojiDictionaryFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 12) {
                if !store.isSearching { levelChips }
                list
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                NavHeader(title: L.yojiDictionary[appLanguage], onBack: { dismiss() })
                SearchField(text: searchBinding, placeholder: L.yojiSearchPrompt[appLanguage])
                    .padding(.horizontal, 16)
                    .readableWidth(sizeClass)
            }
            .padding(.bottom, 6)
            .background(Palette.background)
        }
        .task { store.send(.onAppear) }
    }

    /// A horizontal chip row: 전체 + each 級 present in the data.
    private var levelChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(L.allLevels[appLanguage], selected: store.level == nil) {
                    store.send(.levelSelected(nil))
                }
                ForEach(store.levels, id: \.self) { level in
                    chip(level, selected: store.level == level) {
                        store.send(.levelSelected(level))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .readableWidth(sizeClass)
    }

    private func chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kawaii(14, weight: .bold))
                .foregroundStyle(selected ? .white : Palette.ink)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(selected ? Palette.accent : Palette.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    selected ? .clear : Palette.ink.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.bouncy)
    }

    @ViewBuilder
    private var list: some View {
        ScrollView {
            if store.visible.isEmpty {
                Text(L.noYojiFound[appLanguage])
                    .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.visible) { yoji in row(yoji) }
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ yoji: Yojijukugo) -> some View {
        Button { store.send(.yojiSelected(yoji)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(yoji.yoji)
                        .font(.kawaiiJP(24, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
                    Text(yoji.reading)
                        .font(.kawaii(13)).foregroundStyle(Palette.pink)
                    Spacer(minLength: 0)
                    Text(yoji.level)
                        .font(.kawaii(11, weight: .bold)).foregroundStyle(Palette.lavender)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.lavenderSoft).clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                }
                if let meaning = yoji.meaning(appLanguage), !meaning.isEmpty {
                    Text(meaning)
                        .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }
}

/// The 四字熟語 detail: the idiom, reading, meaning, and its four kanji as cards
/// that drill into the full kanji detail.
private struct YojiDetailView: View {
    @Bindable var store: StoreOf<YojiDetailFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    if !store.kanji.isEmpty {
                        KanjiCardList(items: store.kanji, glosses: [:],
                                      onSelect: { store.send(.kanjiTapped($0)) })
                    }
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            NavHeader(title: L.yojiDictionary[appLanguage], onBack: { dismiss() })
                .background(Palette.background)
        }
        .safeAreaInset(edge: .bottom) {
            if store.siblings.count > 1 {
                HStack(spacing: 12) {
                    yojiNavButton(L.prev[appLanguage], icon: "chevron.left", trailingIcon: false,
                                  enabled: store.hasPrev) { store.send(.showSibling(delta: -1)) }
                    yojiNavButton(L.next[appLanguage], icon: "chevron.right", trailingIcon: true,
                                  enabled: store.hasNext) { store.send(.showSibling(delta: 1)) }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
                .readableWidth(sizeClass)
                .background(Palette.background)
            }
        }
        .task { store.send(.onAppear) }
    }

    private func yojiNavButton(_ title: String, icon: String, trailingIcon: Bool,
                               enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !trailingIcon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title).font(.kawaii(16, weight: .bold, language: appLanguage))
                if trailingIcon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
            }
            .foregroundStyle(enabled ? .white : Palette.inkSoft)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(enabled ? Palette.accent : Palette.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(enabled ? .clear : Palette.ink.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            Text(store.yoji.yoji)
                .font(.kawaiiJP(44, weight: .bold)).japaneseGlyphs().foregroundStyle(Palette.ink)
            Text(store.yoji.reading)
                .font(.kawaii(16, weight: .bold)).foregroundStyle(Palette.pink)
            if let meaning = store.yoji.meaning(appLanguage), !meaning.isEmpty {
                Text(meaning)
                    .font(.kawaii(15, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Text(store.yoji.level)
                .font(.kawaii(11, weight: .bold)).foregroundStyle(Palette.lavender)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Palette.lavenderSoft).clipShape(Capsule())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 16)
        .roundedCard()
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
    // Shared with the dictionary header's grid/list toggle.
    @AppStorage("dictGridMode") private var gridMode = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .compact ? 112 : 138), spacing: 12)]
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                if items.isEmpty {
                    Text(L.noKanjiFound[appLanguage])
                        .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
                } else if gridMode {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, kanji in
                            gridCell(kanji, tint: Palette.tint(index))
                                .popInRow(index)
                        }
                    }
                    .padding(16)
                    .readableWidth(sizeClass)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, kanji in
                            KanjiListRow(kanji: kanji,
                                         meaning: kanjiGloss(glosses[kanji.id] ?? [:], appLanguage),
                                         tint: Palette.tint(index),
                                         language: appLanguage) { onSelect(kanji) }
                                .popInRow(index, step: 0.04)
                        }
                    }
                    .padding(16)
                    .readableWidth(sizeClass)
                }
            }
        }
    }

    /// A compact grid cell: glyph tile + meaning + 음/훈 readings.
    private func gridCell(_ kanji: Kanji, tint: (soft: Color, accent: Color)) -> some View {
        Button { onSelect(kanji) } label: {
            VStack(spacing: 6) {
                PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent, size: 54, fontSize: 30)
                if let meaning = kanjiGloss(glosses[kanji.id] ?? [:], appLanguage), !meaning.isEmpty {
                    Text(meaning)
                        .font(.kawaii(12, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                VStack(spacing: 3) {
                    if !kanji.onReadings.isEmpty {
                        gridReading(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
                    }
                    if !kanji.kunReadings.isEmpty {
                        gridReading(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
                    }
                }
            }
            // Uniform min height + top alignment so cards line up whether a kanji
            // has one reading row or two.
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .top)
            .padding(.vertical, 14).padding(.horizontal, 6)
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }

    /// A tiny 음/훈 reading line for a grid cell (label chip + truncated reading).
    private func gridReading(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.kawaii(9, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1).background(accent).clipShape(Capsule())
            Text(readings.prefix(3).joined(separator: "、"))
                .font(.kawaiiJP(11, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// The dictionary header's grid/list toggle — round button bound to the shared
/// `dictGridMode` flag.
struct GridToggleButton: View {
    @AppStorage("dictGridMode") private var gridMode = false
    var body: some View {
        CircleButton(gridMode ? "list.bullet" : "square.grid.2x2", size: 34) {
            withAnimation(.easeInOut(duration: 0.2)) { gridMode.toggle() }
        }
    }
}
