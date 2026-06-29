import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct KanjiListView: View {
    @Bindable public var store: StoreOf<KanjiListFeature>
    @AppStorage("classification") private var classification: Classification = .jlpt

    public init(store: StoreOf<KanjiListFeature>) {
        self.store = store
    }

    private var searchBinding: Binding<String> {
        Binding(get: { store.searchText }, set: { store.send(.searchChanged($0)) })
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.onAppear) }
    }

    private var navTitle: String {
        if store.isSearching { "検索" }
        else if let level = store.selectedLevel { level.label }
        else { "漢字" }
    }

    @ViewBuilder private var content: some View {
        if store.isLoading {
            ProgressView().tint(Palette.accent)
        } else if let error = store.loadError {
            ContentUnavailableView("読み込み失敗", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else {
            VStack(spacing: 0) {
                searchField
                if store.isSearching {
                    kanjiScroll(store.searchResults, accent: Palette.lavender, soft: Palette.lavenderSoft)
                } else if let level = store.selectedLevel {
                    let tint = tintFor(level)
                    backBar
                    kanjiScroll(store.levelKanji, accent: tint.accent, soft: tint.soft)
                } else {
                    levelGrid
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.inkSoft)
            TextField("漢字・読みで検索", text: searchBinding)
                .font(.kawaii(16)).foregroundStyle(Palette.ink).autocorrectionDisabled()
            if store.isSearching {
                Button { store.send(.searchChanged("")) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Palette.card).clipShape(Capsule())
        .shadow(color: Palette.ink.opacity(0.06), radius: 6, y: 2)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    // MARK: Level grid

    private var levelGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(Array(levels(for: classification).enumerated()), id: \.element.id) { index, level in
                    let tint = Palette.tint(index)
                    let count = kanjiIn(store.kanji.elements, in: level).count
                    Button { store.send(.levelSelected(level)) } label: {
                        levelCard(level, count: count, tint: tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private func levelCard(_ level: KanjiLevel, count: Int, tint: (soft: Color, accent: Color)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(level.label).font(.kawaii(26, weight: .bold)).foregroundStyle(Palette.ink)
            Text("\(count) 字").font(.kawaii(14)).foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(18)
        .background(tint.soft)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(tint.accent.opacity(0.35), lineWidth: 1.5))
    }

    // MARK: Level detail / search list

    private var backBar: some View {
        HStack {
            Button { store.send(.levelCleared) } label: {
                Label("一覧", systemImage: "chevron.left")
                    .font(.kawaii(15, weight: .semibold)).foregroundStyle(Palette.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.bottom, 6)
    }

    private func kanjiScroll(_ list: [Kanji], accent: Color, soft: Color) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(list) { kanji in
                    Button { store.send(.kanjiTapped(kanji)) } label: {
                        row(kanji, accent: accent, soft: soft)
                    }
                    .buttonStyle(.plain)
                }
                if list.isEmpty {
                    Text("該当する漢字がありません")
                        .font(.kawaii(15)).foregroundStyle(Palette.inkSoft).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private func row(_ kanji: Kanji, accent: Color, soft: Color) -> some View {
        HStack(spacing: 14) {
            PastelTile(kanji.literal, soft: soft, accent: accent)
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
        }
        .roundedCard()
    }

    private func tintFor(_ level: KanjiLevel) -> (soft: Color, accent: Color) {
        let all = levels(for: classification)
        let index = all.firstIndex(of: level) ?? 0
        return Palette.tint(index)
    }
}
