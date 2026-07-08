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

/// A sentence translation for the selected language. Japanese mode shows no
/// translation (the example is already Japanese); others fall back to English.
private func localizedTranslation(_ translations: [String: String], _ language: AppLanguage) -> String? {
    if language == .ja { return nil }
    for key in [language.glossKey, "ko", "zh", "en"] {
        if let value = translations[key], !value.isEmpty { return value }
    }
    return nil
}

/// The kanji's own meaning for the selected language, falling back deterministically.
private func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
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
            AuroraBackground()
            content
        }
        .navigationTitle(L.study[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.onAppear(newPerDay: max(1, newPerDay), level: targetLevel)) }
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasLoaded {
            loadingCard
        } else if store.isFinished {
            finishedCard
        } else if store.queue.isEmpty {
            emptyCard
        } else if let kanji = store.current {
            ScrollView {
                VStack(spacing: 16) {
                    progressCard.popIn(delay: 0.02)
                    writeCard(kanji).popIn(delay: 0.09)
                    wordCard.popIn(delay: 0.16)
                    exampleCard.popIn(delay: 0.23)
                    advanceButton.popIn(delay: 0.30)
                }
                .padding(16)
                // Re-run the entrance animation each time the card advances.
                .id(store.index)
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

    // MARK: 1) Learn the kanji — meaning + animated stroke order (no writing here;
    // writing practice lives in the 연습 screen).

    private func writeCard(_ kanji: Kanji) -> some View {
        // A big, centered glyph — iPhone has no tracing grid, so give it room.
        let glyphSize: CGFloat = sizeClass == .compact ? 260 : 220
        return VStack(spacing: 14) {
            if let meaning = localizedGloss(store.glosses, appLanguage), !meaning.isEmpty {
                HStack(spacing: 8) {
                    Text(meaning)
                        .font(.kawaii(22, weight: .bold, language: appLanguage))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    SpeakButton(kanji.literal)
                }
            }
            // 音読み / 訓読み — the readings, so learning isn't just meaning + shape.
            if !kanji.onReadings.isEmpty || !kanji.kunReadings.isEmpty {
                VStack(spacing: 5) {
                    if !kanji.onReadings.isEmpty {
                        readingRow(L.onReading[appLanguage], kanji.onReadings, Palette.sky)
                    }
                    if !kanji.kunReadings.isEmpty {
                        readingRow(L.kunReading[appLanguage], kanji.kunReadings, Palette.mint)
                    }
                }
            }
            // Animated stroke order (how it's written).
            if store.strokePaths.isEmpty {
                PastelTile(kanji.literal, soft: Palette.butterSoft, accent: Palette.butter,
                           size: glyphSize, fontSize: glyphSize * 0.62)
            } else {
                StrokeOrderPlayer(paths: store.strokePaths, size: glyphSize)
            }
        }
        .frame(maxWidth: .infinity)
        .roundedCard()
    }

    /// A centered 音/訓 reading row with a colored label chip.
    private func readingRow(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.kawaii(12, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(accent).clipShape(Capsule())
            Text(readings.joined(separator: "、"))
                .font(.kawaii(16, weight: .semibold)).foregroundStyle(Palette.ink)
        }
    }

    // MARK: 2) One word using the kanji

    @ViewBuilder
    private var wordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.worksheetWord[appLanguage], accent: Palette.lavender)
            if store.words.isEmpty {
                Text("…").font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
            } else {
                ForEach(store.words) { word in
                    HStack(spacing: 8) {
                        // Tap a word to drill into its detail (and from there, its
                        // kanji) without leaving the study session.
                        Button { store.send(.wordTapped(word)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                RubyWord(word.surface, reading: word.reading, size: 22)
                                if let meaning = wordMeaning(word, appLanguage), !meaning.isEmpty {
                                    Text(meaning)
                                        .font(.kawaii(14, language: appLanguage))
                                        .foregroundStyle(Palette.ink)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        SpeakButton(word.surface)
                    }
                }
            }
        }
        .roundedCard()
    }

    // MARK: 3) Example sentences

    @ViewBuilder
    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.worksheetExample[appLanguage], accent: Palette.sky)
            if store.sentences.isEmpty {
                Text("…").font(.kawaii(16)).foregroundStyle(Palette.inkSoft)
            } else {
                ForEach(store.sentences) { sentence in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            RubyText(sentence.textJa, size: 20)
                            if let translation = localizedTranslation(sentence.translations, appLanguage),
                               !translation.isEmpty {
                                Text(translation)
                                    .font(.kawaii(14, language: appLanguage))
                                    .foregroundStyle(Palette.inkSoft)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        SpeakButton(sentence.textJa)
                    }
                }
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
                .background(
                    LinearGradient(colors: store.isLast ? [Palette.mint, Palette.sky] : [Palette.butter, Palette.pink],
                                   startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
                .shadow(color: (store.isLast ? Palette.mint : Palette.butter).opacity(0.4), radius: 10, y: 5)
        }
        .buttonStyle(.bouncy)
    }

    // MARK: Finished / empty

    private var finishedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(Palette.mint)
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

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Palette.pink)
            Text(L.toLearn[appLanguage])
                .font(.kawaii(15)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
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
