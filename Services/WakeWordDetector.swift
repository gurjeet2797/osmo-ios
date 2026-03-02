import AVFoundation
import Speech

/// Continuously listens for the wake word "Osmo" using on-device speech recognition.
/// Runs nonisolated to avoid blocking the main actor — same pattern as `SpeechRecognizer`.
nonisolated final class WakeWordDetector: @unchecked Sendable {

    // MARK: - Public Interface

    /// Called on the main actor when the wake word is detected.
    var onWakeWord: (@Sendable () -> Void)?

    /// Whether the detector is currently listening.
    private(set) var isListening: Bool = false

    /// User preference — when disabled, start/resume are no-ops.
    private(set) var isEnabled: Bool = true

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?

    /// Prevent double-triggers within a short window.
    private var lastDetectionTime: Date = .distantPast
    private let cooldownInterval: TimeInterval = 3.0

    /// Track whether we've been explicitly paused (for command recording coordination).
    private var isPaused: Bool = false

    /// Variants of "Osmo" that the recognizer might produce.
    private let wakeVariants: [String] = ["osmo", "ozmo", "oz mo", "osmol", "ossmo"]

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Enable / Disable (User Preference)

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled && !isPaused {
            startListening()
        } else if !enabled {
            stopListening()
        }
    }

    // MARK: - Pause / Resume (Audio Session Coordination)

    /// Stop listening to yield the audio session to the command recorder.
    func pause() {
        isPaused = true
        stopListening()
    }

    /// Resume listening after the command recorder is done.
    /// Delays briefly to let the audio session fully release.
    func resume() {
        isPaused = false
        guard isEnabled else { return }

        // Delay to let the audio session settle after command recording stops.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.isEnabled, !self.isPaused else { return }
            self.startListening()
        }
    }

    // MARK: - Core Listening

    func startListening() {
        guard isEnabled, !isPaused, !isListening else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        // Authorization must already be granted (checked at app startup via SpeechRecognizer).
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission
        guard speechStatus == .authorized, micStatus == .granted else { return }

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
            guard recordingFormat.channelCount > 0 else { return }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            let callback = self.onWakeWord

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString.lowercased()
                    if self.containsWakeWord(text) {
                        let now = Date()
                        if now.timeIntervalSince(self.lastDetectionTime) >= self.cooldownInterval {
                            self.lastDetectionTime = now
                            callback?()
                        }
                    }
                }

                // Recognition timed out or errored — auto-restart.
                if error != nil || (result?.isFinal == true) {
                    self.stopListening()
                    // Restart after a brief delay, unless paused or disabled.
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self, self.isEnabled, !self.isPaused else { return }
                        self.startListening()
                    }
                }
            }

            self.audioEngine = engine
            self.recognitionRequest = request
            self.isListening = true

        } catch {
            stopListening()
        }
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Wake Word Matching

    /// Checks whether the transcription text contains a wake word variant at a word boundary.
    private func containsWakeWord(_ text: String) -> Bool {
        for variant in wakeVariants {
            // Word-boundary check: ensure the variant isn't embedded in a longer word.
            // Split the text into words and check for the variant (which may be multi-word).
            if variant.contains(" ") {
                // Multi-word variant — check substring presence
                if text.contains(variant) { return true }
            } else {
                // Single-word variant — match against individual words
                let words = text.split(separator: " ").map { String($0) }
                if words.contains(variant) { return true }
            }
        }
        return false
    }
}
