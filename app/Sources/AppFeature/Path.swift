import ComposableArchitecture
import KanjiDetail
import WritingCanvas

/// Destinations reachable from a kanji tap: the study card, then the canvas.
@Reducer
public enum Path {
    case detail(KanjiDetailFeature)
    case writing(KanjiWritingFeature)
}

extension Path.State: Equatable {}
