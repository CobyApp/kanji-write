import ComposableArchitecture
import SharedModels
import SwiftUI
import WritingCanvas

public struct KanjiDetailView: View {
    @Bindable public var store: StoreOf<KanjiDetailFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko

    public init(store: StoreOf<KanjiDetailFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                readings
                if !store.strokePaths.isEmpty { strokeOrderSection }
                if !store.words.isEmpty { wordsSection }
                if !store.sentences.isEmpty { sentencesSection }
                if !store.relations.isEmpty { relationsSection }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(store.kanji.literal)
        .toolbar {
            Button(store.addedToReview ? "復習に追加済み" : "復習に追加") {
                store.send(.addToReview)
            }
            .disabled(store.addedToReview)
            Button("書いて練習") { store.send(.writeTapped) }
        }
        .task { store.send(.onAppear) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(store.kanji.literal)
                .font(.system(size: 84))
            VStack(alignment: .leading, spacing: 8) {
                Text(localizedGloss(store.glosses, appLanguage) ?? "")
                    .font(.title)
                HStack(spacing: 8) {
                    if let grade = store.kanji.grade { chip("学\(grade)") }
                    if let jlpt = store.kanji.jlptLevel { chip(jlpt) }
                }
            }
            Spacer()
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("読み").font(.headline)
            if !store.kanji.onReadings.isEmpty {
                Text("音 " + store.kanji.onReadings.joined(separator: "、"))
            }
            if !store.kanji.kunReadings.isEmpty {
                Text("訓 " + store.kanji.kunReadings.joined(separator: "、"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var strokeOrderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("画順").font(.headline)
            StrokeOrderPlayer(paths: store.strokePaths)
        }
    }

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("活用").font(.headline)
            ForEach(store.words) { word in
                VStack(alignment: .leading) {
                    Text("\(word.surface)（\(word.reading)）").font(.body)
                    if let meaning = wordMeaning(word, appLanguage) {
                        Text(meaning).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sentencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("例文").font(.headline)
            ForEach(store.sentences) { sentence in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sentence.textJa)
                    if let translation = localizedTranslation(sentence.translations, appLanguage) {
                        Text(translation).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var relationsSection: some View {
        let antonyms = store.relations.filter { $0.type == "antonym" }.map(\.surface)
        let related = store.relations.filter { $0.type == "related" }.map(\.surface)
        return VStack(alignment: .leading, spacing: 8) {
            Text("関連").font(.headline)
            if !antonyms.isEmpty {
                Text("反意").font(.subheadline).foregroundStyle(.secondary)
                Text(antonyms.joined(separator: "、"))
            }
            if !related.isEmpty {
                Text("関連語").font(.subheadline).foregroundStyle(.secondary)
                Text(related.joined(separator: "、"))
            }
        }
    }
}
