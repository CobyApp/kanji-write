import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct KanjiListView: View {
    @Bindable public var store: StoreOf<KanjiListFeature>

    public init(store: StoreOf<KanjiListFeature>) {
        self.store = store
    }

    /// Filter chips: すべて + JLPT N5…N1 + grades 小1…小6 + 中.
    private static let filters: [(label: String, filter: KanjiFilter)] =
        [("すべて", .all)]
        + ["N5", "N4", "N3", "N2", "N1"].map { ($0, .jlpt($0)) }
        + (1...6).map { ("小\($0)", .grade($0)) }
        + [("中", .grade(8))]

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle("漢字")
        .task { store.send(.onAppear) }
    }

    @ViewBuilder private var content: some View {
        if store.isLoading {
            ProgressView().tint(Palette.accent)
        } else if let error = store.loadError {
            ContentUnavailableView(
                "読み込み失敗", systemImage: "exclamationmark.triangle",
                description: Text(error))
        } else {
            VStack(spacing: 0) {
                searchField
                filterChips
                kanjiList
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.inkSoft)
            TextField("漢字・読みで検索", text: searchBinding)
                .font(.kawaii(16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Palette.card)
        .clipShape(Capsule())
        .shadow(color: Palette.ink.opacity(0.06), radius: 6, y: 2)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(Self.filters.enumerated()), id: \.offset) { index, item in
                    let tint = Palette.tint(index)
                    Button {
                        store.send(.filterChanged(item.filter))
                    } label: {
                        CandyChip(
                            item.label, soft: tint.soft, accent: tint.accent,
                            selected: store.filter == item.filter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private var kanjiList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(store.visibleKanji.enumerated()), id: \.element.id) { index, kanji in
                    let tint = Palette.tint(index)
                    Button {
                        store.send(.kanjiTapped(kanji))
                    } label: {
                        row(kanji, tint: tint)
                    }
                    .buttonStyle(.plain)
                }
                if store.visibleKanji.isEmpty {
                    Text("該当する漢字がありません")
                        .font(.kawaii(15)).foregroundStyle(Palette.inkSoft)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private func row(_ kanji: Kanji, tint: (soft: Color, accent: Color)) -> some View {
        HStack(spacing: 14) {
            PastelTile(kanji.literal, soft: tint.soft, accent: tint.accent)
            VStack(alignment: .leading, spacing: 3) {
                if !kanji.onReadings.isEmpty {
                    Text(kanji.onReadings.joined(separator: "、"))
                        .font(.kawaii(15, weight: .semibold)).foregroundStyle(Palette.ink)
                }
                if !kanji.kunReadings.isEmpty {
                    Text(kanji.kunReadings.joined(separator: "、"))
                        .font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer()
            if let jlpt = kanji.jlptLevel {
                CandyChip(jlpt, soft: tint.soft, accent: tint.accent)
            }
        }
        .roundedCard()
    }
}
