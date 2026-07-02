import ComposableArchitecture
import DesignSystem
import PencilKit
import SharedModels
import SwiftUI
import WritingCanvas

/// The kanji gloss for the selected language, falling back deterministically.
/// (Reimplemented inline so TestMode does not depend on KanjiDetail.)
private func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
}

/// Full-screen flashcard quiz over FSRS-due kanji: read the meaning, recall the
/// glyph on the Pencil canvas, reveal the answer, then self-grade pass/fail.
public struct TestView: View {
    @Bindable public var store: StoreOf<TestFeature>
    @State private var drawing = PKDrawing()
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass

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
        .onChange(of: store.clearToken) { _, _ in drawing = PKDrawing() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isFinished {
            doneCard
        } else if let kanji = store.current {
            ScrollView {
                VStack(spacing: 16) {
                    progressCard
                    promptCard
                    // Recall-by-writing is iPad-only; iPhone is a flip card.
                    if sizeClass != .compact {
                        canvasCard(kanji)
                    }
                    if store.revealed {
                        answerCard(kanji)
                        gradeButtons
                    } else {
                        showAnswerButton
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Progress

    private var progressCard: some View {
        HStack(spacing: 8) {
            SectionHeader(L.test[appLanguage], accent: Palette.lavender)
            Spacer()
            Text("\(min(store.index + 1, store.queue.count)) / \(store.queue.count)")
                .font(.kawaii(15, weight: .bold)).monospacedDigit()
                .foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    // MARK: Prompt (meaning shown; readings hidden until reveal)

    private var promptCard: some View {
        VStack(spacing: 10) {
            Text(L.testPrompt[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
            Text(localizedGloss(store.glosses, appLanguage) ?? "…")
                .font(.kawaii(24, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .roundedCard()
    }

    // MARK: Recall canvas (NO stroke guide while recalling)

    private func canvasCard(_ kanji: Kanji) -> some View {
        VStack(spacing: 10) {
            SectionHeader(L.worksheetWrite[appLanguage], accent: Palette.mint)
            ZStack {
                // Faint guide appears only after the answer is revealed.
                if store.revealed {
                    GuideStrokes(paths: store.strokePaths)
                }
                PencilCanvasView(drawing: $drawing)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Palette.mint.opacity(0.35), lineWidth: 1.5))
            HStack {
                Spacer()
                Button(L.clearWriting[appLanguage]) { drawing = PKDrawing() }
                    .font(.kawaii(13, weight: .bold))
                    .foregroundStyle(Palette.pink)
                    .disabled(drawing.strokes.isEmpty)
            }
        }
        .roundedCard()
    }

    // MARK: Reveal

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
            PastelTile(kanji.literal, soft: Palette.lavenderSoft, accent: Palette.lavender,
                       size: 120, fontSize: 76)
            if !kanji.onReadings.isEmpty {
                readingRow(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
            }
            if !kanji.kunReadings.isEmpty {
                readingRow(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
            }
        }
        .frame(maxWidth: .infinity)
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

    // MARK: Done / empty

    private var doneCard: some View {
        VStack(spacing: 12) {
            Text("🎉").font(.system(size: 52))
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

/// Renders the KanjiVG stroke guide (109x109 viewBox) scaled to fit its square.
/// Shown faintly behind the canvas only after the learner reveals the answer.
private struct GuideStrokes: View {
    private static let viewBoxSize: CGFloat = 109.0
    let paths: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.viewBoxSize
            ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                SVGPath.path(from: SVGPath.parse(d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                    .stroke(Palette.lavender.opacity(0.35), lineWidth: 3)
            }
        }
    }
}
