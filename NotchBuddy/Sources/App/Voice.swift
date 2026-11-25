import AVFoundation
import AppKit

/// Spoken announcements ("Claude is done", "Claude needs your permission") with
/// the voice that already ships with macOS. Nothing is recorded and nothing is
/// sent anywhere. Off by default (Settings → Voice).
/// The Windows twin is windows/src/core/voice.ts — keep the two in step.
@MainActor
final class Voice {
    static let shared = Voice()

    private let synth = AVSpeechSynthesizer()
    private var lastText = ""
    private var lastAt = Date.distantPast

    private init() {}

    /// Speaks `text` if the user turned voice on; the same phrase is not repeated within 4 s.
    func say(_ text: String) {
        let state = AppState.shared
        guard state.voiceEnabled, !text.isEmpty else { return }
        let now = Date.now
        if text == lastText, now.timeIntervalSince(lastAt) < 4 { return }
        lastText = text
        lastAt = now

        let u = AVSpeechUtterance(string: text)
        let lang = Locale.preferredLanguages.first ?? "en-US"
        u.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.volume = Float(min(1, max(0.3, state.soundVolume * 5)))
        // A new phrase replaces whatever is still being said.
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synth.speak(u)
    }
}
