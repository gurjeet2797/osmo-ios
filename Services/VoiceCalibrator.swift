import AVFoundation
import Speech

/// Records short speech samples for wake word calibration.
/// Uses identical recognition config to `WakeWordDetector` so transcriptions match.
nonisolated final class VoiceCalibrator: @unchecked Sendable {

    private static let userVariantsKey = "wakeWordUserVariants"

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?

    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Records ~2.5s of speech and returns the lowercased transcription.
    func recordSample() async throws -> String {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw CalibrationError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers, .defaultToSpeaker])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                let engine = AVAudioEngine()
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.requiresOnDeviceRecognition = true
                request.taskHint = .search

                let inputNode = engine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                guard recordingFormat.channelCount > 0 else {
                    continuation.resume(throwing: CalibrationError.audioSetupFailed)
                    return
                }

                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    request.append(buffer)
                }

                engine.prepare()
                try engine.start()

                self.audioEngine = engine
                self.recognitionRequest = request

                var bestTranscription = ""
                var hasResumed = false

                self.recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
                    if let result {
                        bestTranscription = result.bestTranscription.formattedString.lowercased()
                    }

                    if error != nil || result?.isFinal == true {
                        guard !hasResumed else { return }
                        hasResumed = true
                        self.tearDown()
                        continuation.resume(returning: bestTranscription)
                    }
                }

                // Stop recording after ~2.5s
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard !hasResumed else { return }
                    self?.recognitionRequest?.endAudio()
                    self?.audioEngine?.stop()
                    self?.audioEngine?.inputNode.removeTap(onBus: 0)
                    // Give recognition a moment to finalize
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) {
                        guard !hasResumed else { return }
                        hasResumed = true
                        self?.tearDown()
                        continuation.resume(returning: bestTranscription)
                    }
                }

            } catch {
                tearDown()
                continuation.resume(throwing: CalibrationError.audioSetupFailed)
            }
        }
    }

    /// Tears down audio resources.
    func cancel() {
        tearDown()
    }

    private func tearDown() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Persistence

    static func saveUserVariants(_ variants: [String]) {
        UserDefaults.standard.set(variants, forKey: userVariantsKey)
    }

    static func loadUserVariants() -> [String] {
        UserDefaults.standard.stringArray(forKey: userVariantsKey) ?? []
    }

    static var hasCalibrated: Bool {
        !loadUserVariants().isEmpty
    }

    // MARK: - Errors

    enum CalibrationError: Error {
        case recognizerUnavailable
        case audioSetupFailed
    }
}
