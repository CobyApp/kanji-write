import ComposableArchitecture
import DesignSystem
import Review
import SharedModels
import SwiftUI
import WritingCanvas

/// The word meaning for the selected language, falling back to English.
/// (Reimplemented inline so Worksheet does not depend on KanjiDetail.)
private func wordMeaning(_ word: WordEntry, _ language: AppLanguage) -> String? {
    switch language {
    case .ko: return word.meaningKo ?? word.meaningEn
    case .ja: return word.meaningJa ?? word.meaningEn
    case .zh: return word.meaningZh ?? word.meaningEn
    case .en: return word.meaningEn
    }
}

/// A sentence translation for the selected language, falling back deterministically.
private func localizedTranslation(_ translations: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ko", "ja", "zh"] {
        if let value = translations[key], !value.isEmpty { return value }
    }
    return translations.values.first(where: { !$0.isEmpty })
}

/// A guided study-sheet (학습) for today's NEW kanji. For each kanji: write it
/// once over the stroke-order guide, read one word that uses it, and one example
/// sentence. Finishing schedules them all for review (initial FSRS record).
public struct WorksheetView: View {
    @Bindable public var store: StoreOf<WorksheetFeature>
    @AppStorage("newPerDay") private var newPerDay = 7
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(store: StoreOf<WorksheetFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle(L.study[appLanguage])
        .task { store.send(.onAppear(newPerDay: newPerDay, level: targetLevel)) }
    }

    @ViewBuilder
    private var content: some View {
        if store.isFinished {
            finishedCard
        } else if store.queue.isEmpty {
            emptyCard
        } else if let kanji = store.current {
            ScrollView {
                VStack(spacing: 16) {
                    progressCard
                    writeCard(kanji)
                    wordCard
                    exampleCard
                    advanceButton
                }
                .padding(16)
            }
        }
    }

    // MARK: Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionHeader(L.toLearn[appLanguage], accent: Palette.butter)
                Spacer()
                Text("\(min(store.index + 1, store.queue.count)) / \(store.queue.count)")
                    .font(.kawaii(15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Palette.inkSoft)
            }
            // Plan summary: level · N/day · remaining · ~days to finish.
            Text("\(targetLevel) · \(newPerDay)/\(L.daysUnit[appLanguage]) · "
                + "\(store.remaining) \(L.left[appLanguage]) · "
                + "~\(daysToFinish(remaining: store.remaining, perDay: newPerDay))\(L.daysUnit[appLanguage])")
                .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
        }
        .roundedCard()
    }

    // MARK: 1) Write the kanji (big glyph + stroke guide behind the canvas)

    private func writeCard(_ kanji: Kanji) -> some View {
        VStack(spacing: 12) {
            SectionHeader(L.worksheetWrite[appLanguage], accent: Palette.mint)
            // Show the stroke order animated (how to write).
            if store.strokePaths.isEmpty {
                PastelTile(kanji.literal, soft: Palette.butterSoft, accent: Palette.butter,
                           size: 96, fontSize: 60)
            } else {
                StrokeOrderPlayer(paths: store.strokePaths, size: 150)
            }
            // Tracing is an iPad / Apple-Pencil activity; iPhone just watches.
            if sizeClass != .compact {
                TracingGrid(paths: store.strokePaths, showGuide: true,
                            clearToken: store.clearToken, cellCount: 6)
            }
        }
        .roundedCard()
    }

    // MARK: 2) One word using the kanji

    @ViewBuilder
    private var wordCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.worksheetWord[appLanguage], accent: Palette.lavender)
            if let word = store.word {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(word.surface)
                        .font(.kawaii(24, weight: .bold)).foregroundStyle(Palette.ink)
                    Text("（\(word.reading)）")
                        .font(.kawaii(15)).foregroundStyle(Palette.inkSoft)
                }
                if let meaning = wordMeaning(word, appLanguage), !meaning.isEmpty {
                    Text(meaning)
                        .font(.kawaii(16, language: appLanguage))
                        .foregroundStyle(Palette.ink)
                }
            } else {
                Text("…").font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
            }
        }
        .roundedCard()
    }

    // MARK: 3) One example sentence

    @ViewBuilder
    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L.worksheetExample[appLanguage], accent: Palette.sky)
            if let sentence = store.sentence {
                Text(sentence.textJa)
                    .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
                if let translation = localizedTranslation(sentence.translations, appLanguage),
                   !translation.isEmpty {
                    Text(translation)
                        .font(.kawaii(15, language: appLanguage))
                        .foregroundStyle(Palette.inkSoft)
                }
            } else {
                Text("…").font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
            }
        }
        .roundedCard()
    }

    // MARK: Advance (Next / Done)

    private var advanceButton: some View {
        Button {
            store.send(store.isLast ? .doneTapped : .nextTapped)
        } label: {
            Text(store.isLast ? L.done[appLanguage] : L.next[appLanguage])
                .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(store.isLast ? Palette.mint : Palette.butter)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Finished / empty

    private var finishedCard: some View {
        VStack(spacing: 12) {
            Text("🎉").font(.system(size: 52))
            Text(L.doneToday[appLanguage])
                .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text(L.seeTomorrow[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard()
        .padding(16)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Text("🌸").font(.system(size: 52))
            Text(L.noLessons[appLanguage])
                .font(.kawaii(18, weight: .bold)).foregroundStyle(Palette.ink)
            Text(L.seeTomorrow[appLanguage])
                .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .roundedCard()
        .padding(16)
    }
}

/// Renders the KanjiVG stroke guide (109x109 viewBox) scaled to fit its square,
/// shown faintly behind the write canvas.
private struct GuideStrokes: View {
    private static let viewBoxSize: CGFloat = 109.0
    let paths: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.viewBoxSize
            ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                SVGPath.path(from: SVGPath.parse(d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                    .stroke(Palette.mint.opacity(0.35), lineWidth: 3)
            }
        }
    }
}
