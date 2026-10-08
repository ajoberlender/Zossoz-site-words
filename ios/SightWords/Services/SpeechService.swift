import AVFoundation

/// Text-to-speech using the system's on-device voices (works offline, nothing leaves the phone).
/// This is the "help when a grown-up can't be there" feature: every card has a speaker button.
@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = SpeechService()

    @Published private(set) var isSpeaking = false
    /// Range of the word currently being spoken (UTF-16 NSRange into the spoken text).
    @Published private(set) var currentRange: NSRange?

    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var player: AVAudioPlayer?

    private override init() {
        super.init()
        synth.delegate = self
        configureSession(record: false)
    }

    /// AVAudioSession calls can block, so they run on a serial background queue (in call order).
    private static let sessionQueue = DispatchQueue(label: "SpeechService.audioSession")

    private nonisolated static func applySession(record: Bool) {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(record ? .playAndRecord : .playback, mode: record ? .measurement : .spokenAudio,
                           options: record ? [.defaultToSpeaker, .duckOthers] : [.duckOthers])
        try? s.setActive(true)
    }

    /// Fire-and-forget; returns immediately.
    func configureSession(record: Bool) {
        Self.sessionQueue.async { Self.applySession(record: record) }
    }

    /// Returns once the session is configured (use before starting the audio engine).
    func configureSessionAndWait(record: Bool) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            Self.sessionQueue.async { Self.applySession(record: record); c.resume() }
        }
    }

    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// Samantha (the classic en-US system voice) unless the child picked another; falls back to the best en-US voice.
    static func defaultVoice() -> AVSpeechSynthesisVoice? {
        let us = availableVoices().filter { $0.language == "en-US" }
        return us.first { $0.name == "Samantha" && $0.quality != .default }
            ?? us.first { $0.name == "Samantha" }
            ?? us.first { $0.quality == .premium } ?? us.first { $0.quality == .enhanced } ?? us.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Speak ordinary text. Returns when finished (or interrupted).
    func speak(_ text: String, child: Child?, rate: Double? = nil) async {
        await speak(utteranceFor: AVSpeechUtterance(string: text), child: child, rate: rate)
    }

    /// Speak a letter/digraph sound. IPA is deliberately not used: most voices (especially the
    /// enhanced/premium ones a parent picks) ignore or mangle it, which both clipped the sound and
    /// ignored the chosen voice. Instead we speak a drawn-out plain-text respelling, then an anchor word.
    func speakSound(_ item: Item, child: Child?, withExample: Bool = true) async {
        let rate = min(child?.speechRate ?? 0.42, 0.40)
        // A recorded clip says the sound and then "as in ___" itself, so nothing is spoken after it.
        // A speech engine asked for "sss" or "kuh" tends to read out letter names ("ess ess").
        if await playClip(named: Self.clipName(for: item)) { return }
        let spoken = Self.stretched[item.text] ?? item.say
        await speak(utteranceFor: AVSpeechUtterance(string: spoken + "…"), child: child, rate: rate)
        guard withExample, !Task.isCancelled, let word = Self.exampleWord(for: item) else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        await speak(word, child: child, rate: rate)
    }

    private static func clipName(for item: Item) -> String {
        item.key.replacingOccurrences(of: ":", with: "-")
    }

    /// After a wrong tap: the chosen voice says "Try again, that's", then the clip of the tapped
    /// sound plays (it says the sound and "as in ___"). Words are just read out.
    func speakWrongAnswer(tapped: Item, child: Child?) async {
        guard tapped.isSound else {
            await speak("Try again. That's \(tapped.say).", child: child)
            return
        }
        await speak("Try again, that's", child: child)
        if Task.isCancelled { return }
        await speakSound(tapped, child: child)
    }

    private static func exampleWord(for item: Item) -> String? {
        if item.kind == .digraph { return item.hint?.replacingOccurrences(of: "as in ", with: "") }
        return exampleWords[item.text]
    }

    /// "s … a … t … sat": slow sound-by-sound, then the whole word.
    func speakSoundedOut(_ word: String, child: Child?) async {
        for ch in word.lowercased() {
            let key = String(ch)
            guard let sound = Curriculum.byKey["letter:\(key)"] else { continue }
            await speakSound(sound, child: child, withExample: false)
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        await speak(word, child: child, rate: 0.35)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        finish()
    }

    /// Plays Resources/Sounds/<name>.wav. Returns false (without playing) if there's no such clip.
    @discardableResult
    private func playClip(named name: String) async -> Bool {
        // The recorded clips are .wav files in Resources/Sounds.
        var found: AVAudioPlayer?
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "wav") {
            do { found = try AVAudioPlayer(contentsOf: url) }
            catch { NSLog("SpeechService: can't decode \(url.lastPathComponent): \(error)") }
        }
        guard let p = found else {
            NSLog("SpeechService: no playable clip named \(name) in the app bundle")
            return false
        }
        stop()
        p.delegate = self
        p.prepareToPlay()
        player = p
        isSpeaking = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuation = c
            if !p.play() { finish() }
        }
        return true
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
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

    /// Continuous sounds are held longer so they're audible; stop sounds keep the short "uh" form.
    private static let stretched: [String: String] = [
        "s": "sssss", "n": "nnnnn", "m": "mmmmm", "r": "rrrrr", "f": "fffff", "l": "lllll", "v": "vvvvv",
        "z": "zzzzz", "sh": "shhhhh", "th": "thhhhh", "ng": "nnggg", "ee": "eeeee", "oo": "oooo",
    ]

    private static let exampleWords: [String: String] = [
        "s": "snake", "a": "apple", "t": "tiger", "p": "penguin", "i": "iguana", "n": "nose", "m": "moon",
        "d": "dog", "o": "octopus", "g": "goat", "c": "cat", "k": "key", "e": "egg", "u": "umbrella",
        "r": "rainbow", "h": "hat", "b": "bear", "f": "fish", "l": "lion", "j": "juice", "v": "violin",
        "w": "whale", "x": "fox", "y": "yo-yo", "z": "zebra", "q": "queen",
    ]
}
