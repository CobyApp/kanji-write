import ComposableArchitecture
import KanjiDetail
import WritingCanvas

/// Destinations reachable from a kanji tap: the study card, then the canvas.
@Reducer
public enum Path {
    case detail(KanjiDetailFeature)
    case writing(KanjiWritingFeature)
}

// Both member states (KanjiDetailFeature.State, KanjiWritingFeature.State) are
// Equatable; update/revisit this if a new Path case adds a non-Equatable state.
extension Path.State: Equatable {}
