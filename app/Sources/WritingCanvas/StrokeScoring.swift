import CoreGraphics

/// The (start, end) endpoints of a single stroke, used for coarse geometric scoring.
public struct StrokeEndpoints: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

/// The result of comparing drawn strokes to the reference strokes.
public struct StrokeScore: Equatable {
    public var countMatch: Bool
    public var matched: Int
    public var total: Int
    public var percent: Int
    public init(countMatch: Bool, matched: Int, total: Int, percent: Int) {
        self.countMatch = countMatch
        self.matched = matched
        self.total = total
        self.percent = percent
    }
}

/// Maps every endpoint into the unit square `[0,1]²` by the combined bounding box,
/// so absolute canvas size is irrelevant. A degenerate (single-point) box returns zeros.
public func normalize(_ strokes: [StrokeEndpoints]) -> [StrokeEndpoints] {
    let points = strokes.flatMap { [$0.start, $0.end] }
    guard let first = points.first else { return strokes }
    var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
    for p in points {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
    }
    let width = maxX - minX, height = maxY - minY
    guard width > 0 || height > 0 else {
        return strokes.map { _ in StrokeEndpoints(start: .zero, end: .zero) }
    }
    func map(_ p: CGPoint) -> CGPoint {
        CGPoint(x: width > 0 ? (p.x - minX) / width : 0,
                y: height > 0 ? (p.y - minY) / height : 0)
    }
    return strokes.map { StrokeEndpoints(start: map($0.start), end: map($0.end)) }
}

/// Reduces an SVG path to its endpoints: start = first `move` point,
/// end = the terminal point of the last drawable command. Returns nil if none.
public func endpoints(ofSVGPath d: String) -> StrokeEndpoints? {
    let commands = SVGPath.parse(d)
    var start: CGPoint?
    var end: CGPoint?
    for command in commands {
        switch command {
        case let .move(p):
            if start == nil { start = p }
            end = p
        case let .line(p):
            end = p
        case let .cubic(_, _, p):
            end = p
        case .close:
            break
        }
    }
    guard let start, let end else { return nil }
    return StrokeEndpoints(start: start, end: end)
}

/// Scores drawn strokes against the reference: stroke `i` matches when both its
/// start and end are within `threshold` (in unit space). `total = max(counts)`.
public func scoreStrokes(
    reference: [StrokeEndpoints],
    drawn: [StrokeEndpoints],
    threshold: CGFloat = 0.18
) -> StrokeScore {
    let total = max(reference.count, drawn.count)
    var matched = 0
    for i in 0 ..< min(reference.count, drawn.count) {
        let r = reference[i], d = drawn[i]
        if distance(r.start, d.start) <= threshold, distance(r.end, d.end) <= threshold {
            matched += 1
        }
    }
    let percent = total == 0 ? 0 : matched * 100 / total
    return StrokeScore(countMatch: reference.count == drawn.count,
                       matched: matched, total: total, percent: percent)
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}
