import ComposableArchitecture
import Foundation
import Vision

/// The outcome of recognizing a drawn kanji: whether any recognized candidate
/// reads as the target, plus the raw candidate strings (for display / debugging).
public struct RecognitionResult: Equatable, Sendable {
    public var matched: Bool
    public var candidates: [String]
    public init(matched: Bool, candidates: [String]) {
        self.matched = matched
        self.candidates = candidates
    }
}

/// True when any recognized candidate contains the target literal (substring match,
/// so e.g. "登山道" counts as containing "山").
public func kanjiMatches(target: String, candidates: [String]) -> Bool {
    candidates.contains { $0.contains(target) }
}

/// On-device Japanese handwriting recognition over a rasterized `PKDrawing`.
@DependencyClient
public struct KanjiRecognizer: Sendable {
    public var recognize: @Sendable (_ imageData: Data, _ target: String) async -> RecognitionResult = { _, _ in
        RecognitionResult(matched: false, candidates: [])
    }
}

extension KanjiRecognizer: DependencyKey {
    public static let liveValue = KanjiRecognizer(
        recognize: { imageData, target in
            await Self.recognizeWithVision(imageData: imageData, target: target)
        }
    )

    /// Runs Vision's on-device text recognition (Japanese, accurate) over the
    /// PNG `imageData`. Any decode/Vision failure yields an empty, non-matching
    /// result rather than throwing.
    private static func recognizeWithVision(imageData: Data, target: String) async -> RecognitionResult {
        guard
            let provider = CGDataProvider(data: imageData as CFData),
            let cgImage = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            return RecognitionResult(matched: false, candidates: [])
        }
        do {
            var request = RecognizeTextRequest()
            request.recognitionLanguages = [Locale.Language(identifier: "ja")]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let observations = try await request.perform(on: cgImage)
            let candidates = observations.flatMap { observation in
                observation.topCandidates(3).map(\.string)
            }
            return RecognitionResult(
                matched: kanjiMatches(target: target, candidates: candidates),
                candidates: candidates
            )
        } catch {
            return RecognitionResult(matched: false, candidates: [])
        }
    }
}

extension KanjiRecognizer: TestDependencyKey {
    public static let testValue = KanjiRecognizer()
}

extension DependencyValues {
    public var kanjiRecognizer: KanjiRecognizer {
        get { self[KanjiRecognizer.self] }
        set { self[KanjiRecognizer.self] = newValue }
    }
}
