import Foundation

/// A review grade (FSRS rating). Raw values match FSRS G = 1…4.
public enum Grade: Int, Sendable, CaseIterable, Codable {
    case again = 1, hard = 2, good = 3, easy = 4
}

/// The two latent FSRS memory variables for a card.
/// Retrievability is derived from `stability` + elapsed time, so it is not stored.
public struct MemoryState: Equatable, Sendable, Codable {
    public var stability: Double   // days for retrievability to fall to 90%
    public var difficulty: Double  // 1…10

    public init(stability: Double, difficulty: Double) {
        self.stability = stability
        self.difficulty = difficulty
    }
}

/// FSRS-4.5 scheduler implemented as pure functions with the published default
/// parameters (no per-user optimization in v1). Days are integer epoch-day
/// numbers. Forgetting curve: R(t,S) = (1 + t/(9S))^(-1).
public enum FSRS {
    /// FSRS-4.5 default weights w[0]…w[18].
    public static let w: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046,
        1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315,
        2.9898, 0.51655, 0.6621,
    ]

    private static func clampD(_ d: Double) -> Double { min(10, max(1, d)) }
    private static func clampS(_ s: Double) -> Double { max(0.01, s) }

    /// Initial difficulty for the first rating: D0(G) = w4 - e^(w5·(G-1)) + 1.
    static func initialDifficulty(_ grade: Grade) -> Double {
        clampD(w[4] - exp(w[5] * Double(grade.rawValue - 1)) + 1)
    }

    /// Memory state right after the very first review of a new card.
    public static func initialState(_ grade: Grade) -> MemoryState {
        MemoryState(stability: clampS(w[grade.rawValue - 1]),
                    difficulty: initialDifficulty(grade))
    }

    /// Probability of recall after `elapsedDays` given `stability`.
    public static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + elapsedDays / (9 * stability), -1)
    }

    /// Difficulty update with linear damping + mean reversion toward D0(Easy).
    static func nextDifficulty(_ d: Double, _ grade: Grade) -> Double {
        let delta = -w[6] * Double(grade.rawValue - 3)
        let damped = d + delta * (10 - d) / 9
        let reverted = w[7] * initialDifficulty(.easy) + (1 - w[7]) * damped
        return clampD(reverted)
    }

    /// Stability after a successful recall (grade ≥ Hard).
    static func stabilityOnRecall(_ s: Double, _ d: Double, _ r: Double, _ grade: Grade) -> Double {
        let hard = grade == .hard ? w[15] : 1
        let easy = grade == .easy ? w[16] : 1
        let inc = exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy
        return clampS(s * (1 + inc))
    }

    /// Stability after a lapse (grade = Again).
    static func stabilityOnLapse(_ s: Double, _ d: Double, _ r: Double) -> Double {
        clampS(w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r)))
    }

    /// Interval (days, ≥1) until the card next reaches `retention`. At r=0.9 this
    /// is ≈ the stability.
    public static func interval(stability: Double, retention: Double) -> Int {
        max(1, Int((9 * stability * (1 / retention - 1)).rounded()))
    }

    /// Schedule a review. `state == nil` means a brand-new card (first rating).
    /// Returns the updated memory state and the next interval in days.
    public static func schedule(
        state: MemoryState?, grade: Grade, elapsedDays: Int, retention: Double = 0.9
    ) -> (state: MemoryState, intervalDays: Int) {
        let next: MemoryState
        if let state {
            let r = retrievability(elapsedDays: Double(max(0, elapsedDays)), stability: state.stability)
            let d = nextDifficulty(state.difficulty, grade)
            let s = grade == .again
                ? stabilityOnLapse(state.stability, d, r)
                : stabilityOnRecall(state.stability, d, r, grade)
            next = MemoryState(stability: s, difficulty: d)
        } else {
            next = initialState(grade)
        }
        return (next, interval(stability: next.stability, retention: retention))
    }
}
