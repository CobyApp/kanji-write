import ComposableArchitecture
import PencilKit
import SwiftUI
import UIKit

/// Renders the KanjiVG stroke guide (109x109 viewBox) scaled to the square.
private struct GuideStrokesView: View {
    /// KanjiVG strokes are authored in a fixed 109x109 coordinate space.
    private static let viewBoxSize: CGFloat = 109.0
    let paths: [String]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / Self.viewBoxSize
            ForEach(Array(paths.enumerated()), id: \.offset) { _, d in
                SVGPath.path(from: SVGPath.parse(d))
                    .applying(CGAffineTransform(scaleX: scale, y: scale))
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
            }
        }
    }
}

public struct KanjiWritingView: View {
    @Bindable public var store: StoreOf<KanjiWritingFeature>
    @State private var drawing = PKDrawing()

    public init(store: StoreOf<KanjiWritingFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 8) {
            Text("画数 \(strokeCountStatus(expected: store.strokePaths.count, drawn: drawing.strokes.count))")
                .font(.headline)
                .monospacedDigit()
            ZStack {
                if store.showGuide {
                    GuideStrokesView(paths: store.strokePaths)
                }
                PencilCanvasView(drawing: $drawing)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Color(.secondarySystemBackground))
            if let recognition = store.recognition {
                VStack(spacing: 4) {
                    Text(recognition.matched ? "正解！" : "もう一度")
                        .font(.title2.bold())
                        .foregroundStyle(recognition.matched ? Color.green : Color.red)
                    if let candidate = recognition.candidates.first {
                        Text("認識: \(candidate)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .navigationTitle(store.kanji.literal)
        .toolbar {
            Button(store.showGuide ? "ガイド非表示" : "ガイド表示") {
                store.send(.toggleGuide)
            }
            Button("消す") { drawing = PKDrawing() }
            Button("採点") {
                if let data = rasterizedDrawingData() {
                    store.send(.recognize(data))
                }
            }
            .disabled(drawing.strokes.isEmpty)
            Button("保存") { store.send(.saveDrawing(drawing.dataRepresentation())) }
        }
        .task { store.send(.onAppear) }
        .onChange(of: store.savedDrawingData) { _, data in
            if let data, let restored = try? PKDrawing(data: data) {
                drawing = restored
            }
        }
    }

    /// Rasterizes the current drawing to PNG data for Vision recognition.
    /// Uses a fixed square bounds so sparse ink still renders at a stable scale.
    private func rasterizedDrawingData() -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
        return drawing.image(from: bounds, scale: 1).pngData()
    }
}
