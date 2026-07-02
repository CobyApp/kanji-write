import Foundation

/// Pure layout logic for the 한자노트 practice grid. Kept framework-free so it
/// can be unit-tested without SwiftUI.
public enum PracticeGrid {
    /// Number of write cells shown in the notebook grid.
    public static let cellCount = 9

    /// Number of columns for the practice grid at a given available width.
    /// Aims for roughly square cells around 150pt: wider layouts get more
    /// columns. Always clamped to 2…4 so cells never get too tiny or too huge.
    public static func columnCount(forWidth width: CGFloat, target: CGFloat = 150) -> Int {
        guard width > 0 else { return 2 }
        let raw = Int((width / target).rounded(.down))
        return min(4, max(2, raw))
    }

    /// Number of rows needed to lay out `count` cells across `columns`.
    public static func rowCount(count: Int = cellCount, columns: Int) -> Int {
        let cols = max(1, columns)
        return (count + cols - 1) / cols
    }
}
