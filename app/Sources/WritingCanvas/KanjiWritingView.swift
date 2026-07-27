import ComposableArchitecture
import DesignSystem
import PencilKit
import SharedModels
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
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.dismiss) private var dismiss

    public init(store: StoreOf<KanjiWritingFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 8) {
            if store.isWritingAvailable {
                Text("\(L.strokes[appLanguage]) \(strokeCountStatus(expected: store.strokePaths.count, drawn: drawing.strokes.count))")
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
                        Text(recognition.matched ? L.correct[appLanguage] : L.gradeAgain[appLanguage])
                            .font(.title2.bold())
                            .foregroundStyle(recognition.matched ? Color.green : Color.red)
                        if let candidate = recognition.candidates.first {
                            Text("\(L.recognized[appLanguage]): \(candidate)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Image(systemName: "pencil.slash")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text(L.strokeOrderUnavailable[appLanguage])
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            NavHeader(title: store.kanji.literal) { dismiss() }
                .background(Palette.background)
        }
        .safeAreaInset(edge: .bottom) {
            if store.isWritingAvailable { actionBar }
        }
        .task { store.send(.onAppear) }
        .onChange(of: store.savedDrawingData) { _, data in
            if let data, let restored = try? PKDrawing(data: data) {
                drawing = restored
            }
        }
    }

    /// The writing actions, moved off the (now-hidden) system toolbar into an
    /// in-content bottom bar so the back button can be the shared custom header.
    private var actionBar: some View {
        HStack(spacing: 10) {
            actionButton(store.showGuide ? L.hideGuide[appLanguage] : L.showGuide[appLanguage]) {
                store.send(.toggleGuide)
            }
            actionButton(L.clear[appLanguage]) { drawing = PKDrawing() }
            actionButton(L.grade[appLanguage]) {
                if let data = rasterizedDrawingData() { store.send(.recognize(data)) }
            }
            .disabled(drawing.strokes.isEmpty)
            actionButton(L.save[appLanguage], filled: true) {
                store.send(.saveDrawing(drawing.dataRepresentation()))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Palette.background)
    }

    private func actionButton(_ title: String, filled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kawaii(14, weight: .bold))
                .foregroundStyle(filled ? .white : Palette.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(filled ? Palette.accent : Palette.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.ink.opacity(filled ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Rasterizes the current drawing to PNG data for Vision recognition.
    /// Uses a fixed square bounds so sparse ink still renders at a stable scale.
    private func rasterizedDrawingData() -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
        return drawing.image(from: bounds, scale: 1).pngData()
    }
}
