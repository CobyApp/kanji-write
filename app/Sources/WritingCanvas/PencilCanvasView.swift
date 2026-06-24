import PencilKit
import SwiftUI

/// Wraps PKCanvasView so SwiftUI/TCA can read and reset the drawing.
/// `.anyInput` lets it work with a finger in the simulator and the Pencil
/// (with pressure/tilt) on device.
public struct PencilCanvasView: UIViewRepresentable {
    @Binding public var drawing: PKDrawing

    public init(drawing: Binding<PKDrawing>) {
        self._drawing = drawing
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 8)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        return canvas
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing.dataRepresentation() != drawing.dataRepresentation() {
            canvas.drawing = drawing
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: PencilCanvasView
        init(_ parent: PencilCanvasView) { self.parent = parent }
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
