import Foundation

/// Formats the drawn-vs-expected stroke count, prefixing a check mark when they match.
public func strokeCountStatus(expected: Int, drawn: Int) -> String {
    drawn == expected ? "✓ \(drawn)/\(expected)" : "\(drawn)/\(expected)"
}
