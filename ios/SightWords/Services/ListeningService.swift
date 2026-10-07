import Foundation
import Speech
import AVFoundation

/// Listens to the child read aloud and checks the words — entirely on device.
/// `requiresOnDeviceRecognition` guarantees audio never leaves the phone. If on-device
/// recognition isn't available for the locale, `isAvailable` is false and the UI falls back
/// to a grown-up (or the child) tapping ✓ / ✗.
@MainActor
final class ListeningService: ObservableObject {
    static let shared = ListeningService()

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<String, Never>?

    var isAvailable: Bool { recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true }

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Listens until silence/timeout and returns the best transcript (lowercased).
    func listen(expecting words: [String], maxSeconds: Double = 6) async -> String {
        guard isAvailable, !isListening else { return "" }
        SpeechService.shared.stop()
        SpeechService.shared.configureSession(record: true)
        transcript = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.contextualStrings = words
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { cleanup(); return "" }
        isListening = true

        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            continuation = c
            task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString.lowercased() }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(maxSeconds * 1_000_000_000))
                await MainActor.run { self?.stop() }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        let result = transcript
        cleanup()
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func cleanup() {
        timeoutTask?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        SpeechService.shared.configureSession(record: false)
    }

    // MARK: Matching

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
    }

    /// Fraction of expected words the child said (order-insensitive; kids stumble and repeat).
    static func matchFraction(expected: String, heard: String) -> Double {
        let exp = tokens(expected)
        guard !exp.isEmpty else { return 0 }
        var pool = tokens(heard)
        var hit = 0
        for w in exp {
            if let i = pool.firstIndex(where: { $0 == w || homophone($0, w) }) { hit += 1; pool.remove(at: i) }
        }
        return Double(hit) / Double(exp.count)
    }

    private static func homophone(_ a: String, _ b: String) -> Bool {
        let groups = [["to", "too", "two"], ["for", "four"], ["no", "know"], ["see", "sea"], ["one", "won"],
                      ["red", "read"], ["be", "bee"], ["i", "eye"], ["there", "their"], ["our", "are"], ["by", "buy"],
                      ["new", "knew"], ["write", "right"], ["would", "wood"], ["so", "sew"], ["ate", "eight"]]
        return groups.contains { $0.contains(a) && $0.contains(b) }
    }
}
