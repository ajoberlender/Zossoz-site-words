import AVFoundation

/// Text-to-speech using the system's on-device voices (works offline, nothing leaves the phone).
/// This is the "help when a grown-up can't be there" feature: every card has a speaker button.
@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    @Published private(set) var isSpeaking = false
    /// Range of the word currently being spoken (UTF-16 NSRange into the spoken text).
    @Published private(set) var currentRange: NSRange?

    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        synth.delegate = self
        configureSession(record: false)
    }

    func configureSession(record: Bool) {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(record ? .playAndRecord : .playback, mode: record ? .measurement : .spokenAudio,
                           options: record ? [.defaultToSpeaker, .duckOthers] : [.duckOthers])
        try? s.setActive(true)
    }

    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// Prefer an enhanced/premium en-US voice when the child hasn't picked one.
    static func defaultVoice() -> AVSpeechSynthesisVoice? {
        let us = availableVoices().filter { $0.language == "en-US" }
        return us.first { $0.quality == .premium } ?? us.first { $0.quality == .enhanced } ?? us.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Speak ordinary text. Returns when finished (or interrupted).
    @discardableResult
    func speak(_ text: String, child: Child?, rate: Double? = nil) async -> Void {
        await speak(utteranceFor: AVSpeechUtterance(string: text), child: child, rate: rate)
    }

    /// Speak a letter/digraph sound. Uses IPA when the voice supports it, else the respelling ("sss").
    func speakSound(_ item: Item, child: Child?) async {
        let attr = NSMutableAttributedString(string: item.say)
        if let ipa = Self.ipa[item.text] {
            attr.addAttribute(NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute), value: ipa,
                              range: NSRange(location: 0, length: attr.length))
        }
        await speak(utteranceFor: AVSpeechUtterance(attributedString: attr), child: child, rate: 0.38)
    }

    /// "s … a … t … sat": slow sound-by-sound, then the whole word.
    func speakSoundedOut(_ word: String, child: Child?) async {
        for ch in word.lowercased() {
            let key = String(ch)
            guard let sound = Curriculum.byKey["letter:\(key)"] else { continue }
            await speakSound(sound, child: child)
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        await speak(word, child: child, rate: 0.35)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        finish()
    }

    private func speak(utteranceFor u: AVSpeechUtterance, child: Child?, rate: Double?) async {
        stop()
        u.voice = child?.voiceID.flatMap { AVSpeechSynthesisVoice(identifier: $0) } ?? Self.defaultVoice()
        u.rate = Float(rate ?? child?.speechRate ?? 0.42)
        u.pitchMultiplier = 1.08
        u.preUtteranceDelay = 0.05
        isSpeaking = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuation = c
            synth.speak(u)
        }
    }

    private func finish() {
        isSpeaking = false
        currentRange = nil
        continuation?.resume()
        continuation = nil
    }

    // MARK: AVSpeechSynthesizerDelegate (called on arbitrary queues)

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.currentRange = range }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    private static let ipa: [String: String] = [
        "s": "s", "a": "æ", "t": "t", "p": "p", "i": "ɪ", "n": "n", "m": "m", "d": "d", "o": "ɑ", "g": "g",
        "c": "k", "k": "k", "e": "ɛ", "u": "ʌ", "r": "ɹ", "h": "h", "b": "b", "f": "f", "l": "l", "j": "dʒ",
        "v": "v", "w": "w", "x": "ks", "y": "j", "z": "z", "q": "kw",
        "sh": "ʃ", "ch": "tʃ", "th": "θ", "wh": "w", "ck": "k", "ng": "ŋ", "qu": "kw",
        "ee": "i", "ai": "eɪ", "oa": "oʊ", "oo": "u", "ar": "ɑɹ",
    ]
}
