import Foundation
import Speech
import AVFoundation

/// Continuous, on-device listening for read-along. Unlike `ListeningService` (one short answer),
/// this keeps the microphone open while a child reads a whole passage and streams the words it
/// hears. `requiresOnDeviceRecognition` guarantees audio never leaves the phone.
///
/// The system recognizer ends an utterance after about a minute or a long pause, so the service
/// quietly starts a new one; each gets a new `segment` number so callers know the token list restarted.
@MainActor
final class LiveReadingService {
    static let shared = LiveReadingService()

    /// (tokens heard so far in this segment, segment number, isFinal)
    var onUpdate: (([String], Int, Bool) -> Void)?
    /// Called if listening stops on its own (e.g. the recognizer keeps failing).
    var onFailure: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var wanted = false
    private var generation = 0
    private var segment = 0
    private var contextual: [String] = []
    private var recentFailures: [Date] = []

    private(set) var isListening = false

    var isAvailable: Bool { recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true }

    /// Starts listening. `contextualStrings` (the words of the text) bias the recognizer toward them.
    func start(contextualStrings: [String]) async -> Bool {
        guard isAvailable else { return false }
        if wanted { return true }
        SpeechService.shared.stop()
        await SpeechService.shared.configureSessionAndWait(record: true)
        contextual = Array(Set(contextualStrings)).prefix(100).map { $0 }
        wanted = true
        generation += 1

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [box] buf, _ in box.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { teardown(); return false }
        isListening = true
        beginSegment()
        return true
    }

    func stop() {
        guard wanted || isListening else { return }
        teardown()
    }

    private func teardown() {
        wanted = false
        generation += 1
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        box.set(nil)
        task?.cancel()
        task = nil
        isListening = false
        SpeechService.shared.configureSession(record: false)
    }

    private func beginSegment() {
        guard wanted, let recognizer else { return }
        segment += 1
        let seg = segment
        let gen = generation
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.contextualStrings = contextual
        box.set(req)
        task?.cancel()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.wanted, self.generation == gen, self.segment == seg else { return }
                if let text {
                    self.recentFailures.removeAll()
                    self.onUpdate?(ReadAlongTracker.tokens(from: text), seg, isFinal || failed)
                }
                if isFinal || failed { self.restartSegment(afterFailure: failed && text == nil) }
            }
        }
    }

    private func restartSegment(afterFailure: Bool) {
        if afterFailure {
            let now = Date()
            recentFailures = recentFailures.filter { now.timeIntervalSince($0) < 5 } + [now]
            if recentFailures.count >= 4 {
                teardown()
                onFailure?()
                return
            }
        }
        let gen = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: afterFailure ? 300_000_000 : 50_000_000)
            guard self.wanted, self.generation == gen else { return }
            self.beginSegment()
        }
    }
}

/// The microphone tap runs on the audio thread; this lets the current request be swapped safely.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = r
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
}
