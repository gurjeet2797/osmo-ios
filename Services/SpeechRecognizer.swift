import AVFoundation
import Speech

/// Nonisolated speech recognizer — all callbacks run safely off the main actor.
/// Transcript updates are delivered via `onTranscript` callback to the main actor owner.
nonisolated final class SpeechRecognizer: @unchecked Sendable {

    // Callback for transcript updates — set by AppViewModel on MainActor
    var onTranscript: (@Sendable (String) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    // Read-only state (set internally, read from MainActor via AppViewModel)
    private(set) var lastTranscript: String = ""
    private(set) var isRecording: Bool = false
    var error: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private var isAuthorized = false

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        if isAuthorized { return true }

        let currentSpeechStatus = SFSpeechRecognizer.authorizationStatus()
        if currentSpeechStatus == .denied || currentSpeechStatus == .restricted {
            error = "Speech recognition not authorized"
            return false
        }

        if currentSpeechStatus == .notDetermined {
            let granted = await withUnsafeContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else {
                error = "Speech recognition not authorized"
                return false
            }
        }

        let micStatus = AVAudioApplication.shared.recordPermission
        if micStatus == .denied {
            error = "Microphone access not authorized"
            return false
        }

        if micStatus == .undetermined {
            let micGranted = await AVAudioApplication.requestRecordPermission()
            guard micGranted else {
                error = "Microphone access not authorized"
                return false
            }
        }

        isAuthorized = true
        return true
    }

    // MARK: - Start Recording

    func startRecording() throws {
        stopRecording()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        guard audioSession.isInputAvailable else {
            error = "No audio input available"
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0 else {
            error = "Microphone not ready — please try again"
            return
        }

        // Install audio tap FIRST (before starting engine or recognition)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        // Capture callbacks as local lets to avoid capturing self in the handler
        let transcriptCallback = self.onTranscript
        let errorCallback = self.onError

        // Start recognition AFTER engine is running
        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, taskError in
            if let result {
                let text = result.bestTranscription.formattedString
                transcriptCallback?(text)
            }
            if let taskError {
                errorCallback?(taskError.localizedDescription)
            }
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.lastTranscript = ""
        self.error = nil
        self.isRecording = true
    }

    // MARK: - Stop Recording

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stops recording and returns the final transcript, or nil if nothing was captured.
    func finishAndReturnTranscript() -> String? {
        let finalText = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopRecording()
        return finalText.isEmpty ? nil : finalText
    }
}
