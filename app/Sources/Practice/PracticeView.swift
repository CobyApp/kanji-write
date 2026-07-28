import ComposableArchitecture
import DesignSystem
import PencilKit
import SharedModels
import SwiftUI
import WritingCanvas

/// The kanji's meaning for the selected language, falling back deterministically.
private func localizedGloss(_ glosses: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = glosses[key], !value.isEmpty { return value }
    }
    return glosses.values.first(where: { !$0.isEmpty })
}

/// The kanji writing test: pick a level + range (setup), write each kanji from
/// its meaning/readings (testing), then compare every answer with the real kanji
/// side-by-side (review) — self-checked, not auto-graded.
public struct PracticeView: View {
    @Bindable public var store: StoreOf<PracticeFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The current question's canvas.
    @State private var drawing = PKDrawing()

    /// The canvas's actual side, measured at layout time and reused as the
    /// review's capture rect so the saved drawing never clips or rescales.
    @State private var canvasSide: CGFloat = 320

    private var levels: [String] { examType.levels }
    private let countOptions = [10, 20, 30, 50]

    public init(store: StoreOf<PracticeFeature>) { self.store = store }

    public var body: some View {
        ZStack {
            AuroraBackground()
            content.readableWidth(sizeClass)
        }
        .task { store.send(.onAppear) }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .setup: setupView
        case .testing: testingView
        case .review: reviewView
        }
    }

    // MARK: Setup — level + range

    private var levelBinding: Binding<String> {
        Binding(get: { store.level }, set: { store.send(.levelSelected($0)) })
    }
    private var modeBinding: Binding<PracticeFeature.State.Mode> {
        Binding(get: { store.mode }, set: { store.send(.modeSelected($0)) })
    }

    private var modeSubtitle: String {
        switch store.mode {
        case .kanji: L.practiceSub[appLanguage]
        case .word: L.wordWriteSub[appLanguage]
        case .yoji: L.yojiWriteSub[appLanguage]
        }
    }

    private var modeTitle: String {
        switch store.mode {
        case .kanji: L.writeTestTitle[appLanguage]
        case .word: L.wordWriteTestTitle[appLanguage]
        case .yoji: L.yojiWriteTestTitle[appLanguage]
        }
    }

    private var rangeSummary: String {
        "\(store.start + 1) ~ \(store.rangeEnd) · \(store.count)\(L.unitCount[appLanguage])"
    }

    /// How many items this 級 holds, which is what tells you whether a range is
    /// a dent or the whole thing.
    private var levelTotalCard: some View {
        HStack(spacing: 14) {
            Image(systemName: store.mode == .kanji ? "character.book.closed.fill" : "text.book.closed.fill")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.sky)
                .frame(width: 44, height: 44)
                .background(Palette.skySoft).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(totalLabel)
                .font(.kawaii(15, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text("\(store.levelCount)")
                .font(.kawaii(26, weight: .bold)).monospacedDigit().foregroundStyle(Palette.sky)
            Text(L.unitCount[appLanguage])
                .font(.kawaii(13, weight: .bold)).foregroundStyle(Palette.sky)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Palette.skySoft.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var promptLabel: String {
        switch store.mode {
        case .kanji: L.writeTestPrompt[appLanguage]
        case .word: L.wordWriteTestPrompt[appLanguage]
        case .yoji: L.yojiWriteTestPrompt[appLanguage]
        }
    }

    private var totalLabel: String {
        switch store.mode {
        case .kanji: L.writeLevelKanjiTotal[appLanguage]
        case .word: L.writeLevelWordTotal[appLanguage]
        case .yoji: L.writeLevelYojiTotal[appLanguage]
        }
    }

    private var rangeLow: Binding<Int> {
        Binding(get: { store.start }, set: { store.send(.setStart(Double($0))) })
    }
    private var rangeHigh: Binding<Int> {
        Binding(get: { store.end }, set: { store.send(.setEnd(Double($0))) })
    }

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(modeTitle)
                        .font(.kawaii(24, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                    Text(modeSubtitle)
                        .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                }
                .padding(.top, 8)

                settingCard(L.writeWhat[appLanguage]) {
                    Picker("", selection: modeBinding) {
                        Text(L.writeModeKanji[appLanguage]).tag(PracticeFeature.State.Mode.kanji)
                        Text(L.writeModeWord[appLanguage]).tag(PracticeFeature.State.Mode.word)
                        Text(L.writeModeYoji[appLanguage]).tag(PracticeFeature.State.Mode.yoji)
                    }
                    .pickerStyle(.segmented)
                }
                settingCard(L.targetLevel[appLanguage]) {
                    // A segmented control crams 漢検's ten 級 into one row; chips
                    // wrap onto as many rows as needed (same as the study plan).
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
                        ForEach(levels, id: \.self) { level in
                            levelChip(level)
                        }
                    }
                }
                levelTotalCard
                settingCard(L.writeRange[appLanguage]) {
                    VStack(spacing: 4) {
                        // One interval, one control. Picking "the 51st to the
                        // 80th" is how you resume a long 級; start-plus-count
                        // makes the learner do that arithmetic, and two separate
                        // sliders draw a single range as two unrelated dots.
                        RangeSlider(low: rangeLow, high: rangeHigh,
                                    in: 0...max(1, store.maxStart),
                                    accent: Palette.lavender)
                        Text(rangeSummary)
                            .font(.kawaii(15, weight: .bold)).foregroundStyle(Palette.lavender)
                    }
                }

                Button { store.send(.startTest) } label: {
                    Text(L.writeTestStart[appLanguage])
                        .font(.kawaii(17, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Palette.accent).clipShape(Capsule())
                        .shadow(color: Palette.accent.opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(.bouncy)
                .disabled(store.levelCount == 0)
            }
            .padding(20)
        }
    }

    /// A square tile that fills the width it's given. Driving the shape from a
    /// clear spacer keeps both comparison boxes the same size — `aspectRatio` on a
    /// Text collapses to the glyph's intrinsic height instead of going square.
    private func squareBox<C: View>(_ fill: Color, @ViewBuilder _ content: () -> C) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content() }
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func levelChip(_ level: String) -> some View {
        let selected = store.level == level
        return Button { store.send(.levelSelected(level)) } label: {
            Text(level)
                .font(.kawaii(14, weight: .bold))
                .foregroundStyle(selected ? .white : Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(selected ? Palette.accent : Palette.background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    selected ? .clear : Palette.ink.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.bouncy)
    }

    private func settingCard<C: View>(_ title: String, @ViewBuilder _ inner: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.kawaii(14, weight: .bold, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            inner()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roundedCard()
    }

    // MARK: Testing — write from the hint

    /// Everything on one screen, no scrolling: the canvas is sized from the
    /// space the fixed parts leave over rather than being a constant that
    /// pushes the buttons off a phone. Writing is the task — having to scroll
    /// to find the canvas, or to reach 다음, interrupts it.
    private var testingView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(store.index + 1) / \(store.questions.count)")
                    .font(.kawaii(14, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                Spacer()
                Text(store.level).font(.kawaii(13, weight: .bold)).foregroundStyle(Palette.inkSoft)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if let item = store.current {
                hintCard(item).padding(.horizontal, 16)

                GeometryReader { geo in
                    let side = max(160, min(geo.size.width - 32, geo.size.height - 12))
                    ZStack {
                        if store.hintShown {
                            hintBoard(item, side: side)
                        } else {
                            canvasCard(side: side)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The review renders the drawing against this same rect, so
                    // the capture has to track whatever size we ended up with.
                    .onAppear { canvasSide = side }
                    .onChange(of: side) { _, new in canvasSide = new }
                }
                .padding(.vertical, 6)

                hintToggle.padding(.bottom, 6)
            }

            navButtons.padding(.horizontal, 16).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadDrawing() }
        .onChange(of: store.index) { _, _ in loadDrawing() }
    }

    private func hintCard(_ item: PracticeItem) -> some View {
        VStack(spacing: 10) {
            Text(promptLabel)
                .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
            if let meaning = localizedGloss(item.glosses, appLanguage), !meaning.isEmpty {
                Text(meaning)
                    .font(.kawaii(26, weight: .bold, language: appLanguage))
                    .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            }
            VStack(spacing: 6) {
                // A word is pinned by its kana reading; a single kanji by its
                // 음/훈 lines, since it has no one reading in isolation.
                if let reading = item.reading, !reading.isEmpty {
                    readingLine(L.reading[appLanguage], [reading], Palette.lavender)
                }
                if !item.onReadings.isEmpty {
                    readingLine(L.onReading[appLanguage], item.onReadings, Palette.sky)
                }
                if !item.kunReadings.isEmpty {
                    readingLine(L.kunReading[appLanguage], item.kunReadings, Palette.mint)
                }
            }
        }
        .frame(maxWidth: .infinity).roundedCard()
    }

    private func canvasCard(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.card)
            PencilCanvasView(drawing: $drawing).padding(10)
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Palette.ink.opacity(0.08), lineWidth: 1.5))
        .overlay(alignment: .bottomTrailing) {
            Button { drawing = PKDrawing() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.pink)
                    .padding(10).background(Palette.pinkSoft, in: Circle())
            }
            .buttonStyle(.bouncy).padding(12)
        }
    }

    private var navButtons: some View {
        HStack(spacing: 12) {
            Button {
                store.send(.saveDrawing(drawing.dataRepresentation()))
                store.send(.prev)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(store.index == 0 ? Palette.inkSoft : Palette.pink)
                    .frame(width: 64).padding(.vertical, 14)
                    .background(Palette.pinkSoft.opacity(store.index == 0 ? 0.4 : 1)).clipShape(Capsule())
            }
            .buttonStyle(.bouncy).disabled(store.index == 0)

            Button {
                store.send(.saveDrawing(drawing.dataRepresentation()))
                if store.isLast { store.send(.finish) } else { store.send(.next) }
            } label: {
                Text(store.isLast ? L.writeSeeResult[appLanguage] : L.next[appLanguage])
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient(
                        colors: store.isLast ? [Palette.mint, Palette.sky] : [Palette.butter, Palette.pink],
                        startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.bouncy)
        }
    }

    /// 힌트 보기 / 숨기기. The attempt is kept: the hint covers the canvas
    /// rather than sitting beside it, so there is nothing to trace from, and
    /// wiping the work would cost the learner their answer for a peek.
    private var hintToggle: some View {
        Button { store.send(.toggleHint) } label: {
            HStack(spacing: 8) {
                Image(systemName: store.hintShown ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(store.hintShown ? L.hintHide[appLanguage] : L.hintShow[appLanguage])
                    .font(.kawaii(14, weight: .bold, language: appLanguage))
            }
            .foregroundStyle(Palette.grape)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Palette.grapeSoft).clipShape(Capsule())
        }
        .buttonStyle(.bouncy)
    }

    /// The answer in the canvas's own footprint: a stroke-order animation for a
    /// single kanji, the glyphs themselves for a word.
    private func hintBoard(_ item: PracticeItem, side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.card)
            switch store.hintStrokes {
            case .none:
                // Still fetching. Showing the glyph here and swapping it for
                // the animation a frame later is the flicker.
                ProgressView().tint(Palette.grape)
            case .some(let paths) where paths.isEmpty:
                Text(item.answer)
                    .font(.kawaiiJP(item.answer.count > 2 ? 78 : 150, weight: .bold))
                    .japaneseGlyphs().foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.4).padding(16)
            case .some(let paths):
                StrokeOrderPlayer(paths: paths).padding(10)
            }
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(Palette.grape.opacity(0.35), lineWidth: 1.5))
        .transition(.opacity)
    }

    private func loadDrawing() {
        if let data = store.drawings[store.index], let restored = try? PKDrawing(data: data) {
            drawing = restored
        } else {
            drawing = PKDrawing()
        }
    }

    // MARK: Review — my answer vs the real kanji

    /// One comparison per row on a phone. Each cell holds two side-by-side boxes
    /// (my writing vs the answer), so squeezing two cells into a narrow width made
    /// them overlap — a phone gets the full width for one comparison instead.
    private var reviewColumns: [GridItem] {
        sizeClass == .compact
            ? [GridItem(.flexible(), spacing: 14)]
            : [GridItem(.adaptive(minimum: 240), spacing: 14)]
    }

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(L.writeCompareHint[appLanguage])
                    .font(.kawaii(16, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                    .padding(.top, 8)
                LazyVGrid(columns: reviewColumns, spacing: 14) {
                    ForEach(Array(store.questions.enumerated()), id: \.element.id) { index, item in
                        reviewCell(index, item)
                    }
                }
                HStack(spacing: 12) {
                    Button { store.send(.restart) } label: {
                        Text(L.writeNewRange[appLanguage])
                            .font(.kawaii(15, weight: .bold)).foregroundStyle(Palette.lavender)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Palette.lavenderSoft).clipShape(Capsule())
                    }
                    .buttonStyle(.bouncy)
                    Button { store.send(.startTest) } label: {
                        Text(L.writeRetest[appLanguage])
                            .font(.kawaii(15, weight: .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Palette.accent).clipShape(Capsule())
                    }
                    .buttonStyle(.bouncy)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private func reviewCell(_ index: Int, _ item: PracticeItem) -> some View {
        VStack(spacing: 8) {
            if let meaning = localizedGloss(item.glosses, appLanguage), !meaning.isEmpty {
                Text(meaning)
                    .font(.kawaii(13, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            // Both boxes share the row evenly and stay square, so the pair fits
            // whatever width the cell gets instead of forcing a fixed 176pt.
            HStack(spacing: 10) {
                VStack(spacing: 3) {
                    squareBox(Palette.background) { myWriting(index) }
                    Text(L.writeMine[appLanguage]).font(.kawaii(10)).foregroundStyle(Palette.inkSoft)
                }
                VStack(spacing: 3) {
                    squareBox(Palette.mintSoft.opacity(0.5)) {
                        // A word needs a smaller face than a lone kanji to fit
                        // the same square.
                        Text(item.answer)
                            .font(.kawaiiJP(item.answer.count > 1 ? 34 : 58, weight: .bold))
                            .japaneseGlyphs()
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.4)
                            .padding(.horizontal, 4)
                    }
                    Text(L.writeAnswer[appLanguage]).font(.kawaii(10)).foregroundStyle(Palette.mint)
                }
            }
            .frame(maxWidth: 320)  // keep the pair from ballooning on a wide cell
        }
        .padding(12).roundedCard()
    }

    @ViewBuilder private func myWriting(_ index: Int) -> some View {
        if let data = store.drawings[index], let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty {
            Image(uiImage: drawing.image(from: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide), scale: 1))
                .resizable().scaledToFit()
        } else {
            Image(systemName: "pencil.slash")
                .font(.system(size: 22)).foregroundStyle(Palette.inkSoft.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func readingLine(_ label: String, _ readings: [String], _ accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.kawaii(11, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2).background(accent).clipShape(Capsule())
            Text(readings.prefix(6).joined(separator: "、"))
                .font(.kawaiiJP(15, weight: .semibold)).foregroundStyle(Palette.ink)
        }
    }
}
