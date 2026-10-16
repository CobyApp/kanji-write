import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

/// The 부수 reference screen: a searchable list of the 214 Kangxi radicals,
/// each tappable to see the kanji that use it.
struct RadicalReferenceView: View {
    @Bindable var store: StoreOf<RadicalReferenceFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            list
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                NavHeader(title: L.radicalDictionary[appLanguage], onBack: { dismiss() })
                SearchField(text: searchBinding, placeholder: L.radicalSearchPrompt[appLanguage])
                    .padding(.horizontal, 16)
                    .readableWidth(sizeClass)
            }
            .padding(.bottom, 6)
            .background(Palette.background)
        }
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var list: some View {
        ScrollView {
            if store.visible.isEmpty {
                Text(L.noRadicalFound[appLanguage])
                    .font(.kawaii(14, language: appLanguage))
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.top, 48)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(store.visible.enumerated()), id: \.element.id) { i, radical in
                        row(radical, tint: Palette.tint(i))
                    }
                }
                .padding(16)
                .readableWidth(sizeClass)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ radical: RadicalEntry, tint: (soft: Color, accent: Color)) -> some View {
        Button { store.send(.radicalTapped(radical)) } label: {
            HStack(spacing: 14) {
                Text(radical.glyph)
                    .font(.kawaiiJP(28, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(tint.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(radical.nameJa)
                        .font(.kawaiiJP(17, weight: .bold)).japaneseGlyphs()
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(radical.meaning(appLanguage))
                        .font(.kawaii(13, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("#\(radical.number) · \(L.strokeCount(radical.strokes, appLanguage))")
                        .font(.kawaii(11)).monospacedDigit().foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L.radicalKanjiCount(radical.kanjiCount, appLanguage))
                        .font(.kawaii(12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(tint.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                }
            }
            .roundedCard()
        }
        .buttonStyle(.bouncy)
    }
}
