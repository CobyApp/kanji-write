import AVFoundation
import SharedModels
import SwiftUI

/// A small speaker icon that reads the given text aloud when tapped.
public struct SpeakButton: View {
    let text: String
    let language: String
    @AppStorage("appLanguage") private var uiLanguage: AppLanguage = .ko

    public init(_ text: String, language: String = "ja-JP") {
        self.text = text
        self.language = language
    }

    public var body: some View {
        Button { Speaker.speak(text, language: language) } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(6)
                .background(Palette.accent.opacity(0.12), in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.speak[uiLanguage])
        .accessibilityHint(text)
    }
}

/// Simple text-to-speech for reading Japanese words and example sentences aloud.
/// A single shared synthesizer so a new tap cancels the previous utterance.
public enum Speaker {
    private static let synth = AVSpeechSynthesizer()

    /// Speaks `text` in the given BCP-47 language (Japanese by default — the
    /// system voice reads kanji with correct readings).
    public static func speak(_ text: String, language: String = "ja-JP") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        synth.speak(utterance)
    }
}
