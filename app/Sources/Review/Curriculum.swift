import SharedModels

/// The order in which new kanji are introduced: by the classification's level
/// sequence (JLPT N5→N1, or grade 小1→中学; un-leveled last), then by ascending
/// stroke count (simpler first), then id for stability.
public func studyOrder(_ kanji: [Kanji], classification: Classification) -> [Kanji] {
    kanji.sorted { a, b in
        let ra = orderRank(a, classification)
        let rb = orderRank(b, classification)
        if ra.level != rb.level { return ra.level < rb.level }
        if ra.strokes != rb.strokes { return ra.strokes < rb.strokes }
        return ra.id < rb.id
    }
}

private func orderRank(_ k: Kanji, _ classification: Classification) -> (level: Int, strokes: Int, id: Int) {
    let level: Int
    switch classification {
    case .jlpt:
        // N5 first … N1 last; unmapped sorts after.
        level = ["N5": 0, "N4": 1, "N3": 2, "N2": 3, "N1": 4][k.jlptLevel ?? ""] ?? 99
    case .grade:
        level = k.grade ?? 99
    }
    return (level, k.strokeCount, k.id)
}
