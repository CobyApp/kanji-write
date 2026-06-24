/// Splits an ordered list of kanji ids into `days` buckets as evenly as
/// possible, with earlier buckets taking the remainder. Pure.
public enum PlanScheduler {
    public static func distribute(kanjiIDs: [Int], days: Int) -> [[Int]] {
        guard !kanjiIDs.isEmpty else { return [] }
        let bucketCount = min(max(days, 1), kanjiIDs.count)
        let base = kanjiIDs.count / bucketCount
        let remainder = kanjiIDs.count % bucketCount
        var buckets: [[Int]] = []
        var index = 0
        for day in 0..<bucketCount {
            let size = base + (day < remainder ? 1 : 0)
            buckets.append(Array(kanjiIDs[index..<index + size]))
            index += size
        }
        return buckets
    }
}
