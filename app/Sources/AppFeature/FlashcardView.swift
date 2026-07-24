import DesignSystem
import SharedModels
import SwiftUI

/// One flashcard's data: a front (kanji glyph or word) and a back (meaning +,
/// for kanji, its readings).
struct FlashcardItem: Identifiable, Equatable {
    let id: Int
    let front: String          // glyph, or word surface
    let frontReading: String?  // word reading (nil for a kanji card)
    let back: String           // meaning
    let backSub: String        // kanji: 음/훈 lines; word: empty
    let isKanji: Bool
}

/// A full-screen flashcard session over the wordbook's saved items. Tap the card
/// to flip (front ↔ back); prev/next move through the deck. Self-study, no
/// grading — matches the writing test's "check it yourself" spirit.
struct FlashcardView: View {
    let items: [FlashcardItem]
    let onClose: () -> Void
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var index = 0
    @State private var flipped = false

    private var current: FlashcardItem? { items.indices.contains(index) ? items[index] : nil }
    private var cardSide: CGFloat { sizeClass == .compact ? 300 : 360 }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 16) {
                if let item = current {
                    Text("\(index + 1) / \(items.count)")
                        .font(.kawaii(14, weight: .bold)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                    Spacer()
                    card(item)
                    Text(L.flashcardTapHint[appLanguage])
                        .font(.kawaii(12, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                    Spacer()
                    navButtons
                }
            }
            .padding(16)
            .readableWidth(sizeClass)
        }
        .safeAreaInset(edge: .top) {
            OverlayHeader(title: L.flashcards[appLanguage]) { onClose() }
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private func card(_ item: FlashcardItem) -> some View {
        ZStack {
            cardFace { frontContent(item) }.opacity(flipped ? 0 : 1)
            cardFace { backContent(item) }
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
        }
        .frame(width: cardSide, height: cardSide)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { flipped.toggle() } }
    }

    private func cardFace<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Palette.pink.opacity(0.25), lineWidth: 1.5))
            .shadow(color: Palette.ink.opacity(0.08), radius: 20, y: 8)
    }

    @ViewBuilder private func frontContent(_ item: FlashcardItem) -> some View {
        VStack(spacing: 10) {
            if let reading = item.frontReading, !reading.isEmpty {
                Text(reading).font(.kawaii(16, weight: .semibold)).foregroundStyle(Palette.pink)
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            Text(item.front)
                .font(.kawaiiJP(item.isKanji ? 150 : 52, weight: .bold)).japaneseGlyphs()
                .foregroundStyle(Palette.ink)
                .lineLimit(item.isKanji ? 1 : 2).minimumScaleFactor(0.4).multilineTextAlignment(.center)
        }
        .padding(24)
    }

    @ViewBuilder private func backContent(_ item: FlashcardItem) -> some View {
        VStack(spacing: 12) {
            Text(item.back)
                .font(.kawaii(28, weight: .bold, language: appLanguage)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).minimumScaleFactor(0.5)
            if !item.backSub.isEmpty {
                Text(item.backSub)
                    .font(.kawaiiJP(17, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    private var navButtons: some View {
        let atEnd = index >= items.count - 1
        return HStack(spacing: 12) {
            Button { move(-1) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    Text(L.prev[appLanguage]).font(.kawaii(16, weight: .bold))
                }
                .foregroundStyle(index == 0 ? Palette.inkSoft : Palette.pink)
                .frame(width: 110).padding(.vertical, 14)
                .background(Palette.pinkSoft.opacity(index == 0 ? 0.4 : 1)).clipShape(Capsule())
            }
            .buttonStyle(.bouncy).disabled(index == 0)

            // Last card → 완료 (closes); otherwise 다음.
            Button { atEnd ? onClose() : move(1) } label: {
                Text(atEnd ? L.done[appLanguage] : L.next[appLanguage])
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient(
                        colors: atEnd ? [Palette.mint, Palette.sky] : [Palette.butter, Palette.pink],
                        startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
            .buttonStyle(.bouncy)
        }
    }

    private func move(_ delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else { return }
        // Flip back to the front without animation, then slide to the next card.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { flipped = false }
        withAnimation(.easeInOut(duration: 0.2)) { index = next }
    }
}
