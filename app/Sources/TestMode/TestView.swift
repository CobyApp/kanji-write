import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

/// The kanji gloss for the selected language, falling back deterministically.
/// (Reimplemented inline so TestMode does not depend on KanjiDetail.)
private func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
}

/// A quick recall review over FSRS-due kanji: read the meaning, recall the glyph
/// in your head (no large writing), reveal, then self-grade pass/fail. A compact
/// progress grid shows the whole due set at a glance.
public struct TestView: View {
    @Bindable public var store: StoreOf<TestFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<TestFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle(L.test[appLanguage])
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        if store.isFinished {
            doneCard
        } else if let kanji = store.current {
            ScrollView {
                VStack(spacing: 16) {
                    progressGrid
                    promptCard
                    if store.revealed {
                        answerCard(kanji)
                        gradeButtons
                    } else {
                        showAnswerButton
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.revealed)
            }
        }
    }

    // MARK: Progress — a compact dot grid of the whole due set

    private var progressGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(L.test[appLanguage], accent: Palette.lavender)
                Spacer()
                Text("\(min(store.index + 1, store.queue.count)) / \(store.queue.count)")
                    .font(.kawaii(15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.inkSoft)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 26), spacing: 8)], spacing: 8) {
                ForEach(Array(store.queue.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(dotColor(index))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Palette.accent,
                                                 lineWidth: index == store.index ? 2.5 : 0))
                }
            }
        }
        .roundedCard()
    }

    private func dotColor(_ index: Int) -> Color {
        if index < store.index { return Palette.mint }        // graded
        if index == store.index { return Palette.lavender }   // current
        return Palette.inkSoft.opacity(0.2)                    // upcoming
    }

    // MARK: Prompt (meaning only; the glyph stays hidden until reveal)

    private var promptCard: some View {
        VStack(spacing: 10) {
            Text(L.testPrompt[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
            Text(localizedGloss(store.glosses, appLanguage) ?? "…")
                .font(.kawaii(26, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .roundedCard()
    }

    private var showAnswerButton: some View {
        Button { store.send(.showAnswerTapped) } label: {
            Text(L.showAnswer[appLanguage])
                .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Palette.lavender).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func answerCard(_ kanji: Kanji) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PastelTile(kanji.literal, soft: Palette.lavenderSoft, accent: Palette.lavender,
                           size: 72, fontSize: 44)
                SpeakButton(kanji.literal)
            }
            if !kanji.onReadings.isEmpty {
                readingRow(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
            }
            if !kanji.kunReadings.isEmpty {
                readingRow(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
            }
        }
        .frame(maxWidth: .infinity).transition(.scale.combined(with: .opacity))
        .roundedCard()
    }

    private func readingRow(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.kawaii(13, weight: .bold)).foregroundStyle(accent)
                .frame(width: 34, alignment: .leading)
            Text(readings.joined(separator: "、"))
                .font(.kawaii(16)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gradeButtons: some View {
        HStack(spacing: 12) {
            gradeButton(L.fail[appLanguage], Palette.pink) { store.send(.graded(pass: false)) }
            gradeButton(L.pass[appLanguage], Palette.mint) { store.send(.graded(pass: true)) }
        }
    }

    private func gradeButton(_ label: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(color).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var doneCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Sparkles()
                Text("🎉").font(.system(size: 52)).celebrate()
            }
            .frame(height: 80)
            Text(L.nothingDue[appLanguage])
                .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text(L.seeTomorrow[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard()
        .padding(16)
    }
}
