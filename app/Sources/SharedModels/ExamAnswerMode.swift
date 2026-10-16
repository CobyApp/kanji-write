import Foundation

/// How the learner answers exam questions. Chosen in the hub's "답하는 방법" card
/// and stored per exam. Replaces the old write-mode boolean so readings can be
/// answered by handwriting, not only typed.
public enum ExamAnswerMode: String, CaseIterable, Sendable {
    /// Pick from multiple choice.
    case choose
    /// Type kana readings; write kanji answers by hand.
    case type
    /// Write every answer by hand (readings included) and self-mark it.
    case write
}
