import AVFoundation
import Speech

/// macOS speech recognizer — no AVAudioSession (macOS doesn't use it).
nonisolated final class MacSpeechRecognizer: @unchecked Sendable {

    var onTranscript: (@Sendable (String) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private(set) var lastTranscript: String = ""
    private(set) var isRecording: Bool = false
    var error: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private var isAuthorized = false
    private var audioFile: AVAudioFile?
    private(set) var recordedAudioURL: URL?

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        if isAuthorized { return true }

        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus == .denied || currentStatus == .restricted {
            error = "Speech recognition not authorized"
            return false
        }

        if currentStatus == .notDetermined {
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

        // macOS mic permission via AVCaptureDevice
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            error = "Microphone access not authorized"
            return false
        }
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
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

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0 else {
            error = "Microphone not ready — please try again"
            return
        }

        // Audio file for Whisper upload
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("osmo_recording.wav")
        try? FileManager.default.removeItem(at: tempURL)
        let wavFile = try? AVAudioFile(forWriting: tempURL, settings: recordingFormat.settings)
        self.audioFile = wavFile
        self.recordedAudioURL = tempURL

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            request.append(buffer)
            try? wavFile?.write(from: buffer)
        }

        engine.prepare()
        try engine.start()

        let transcriptCallback = self.onTranscript
        let errorCallback = self.onError

        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, taskError in
            if let result {
                let text = result.bestTranscription.formattedString
                transcriptCallback?(text)
            }
            if let taskError {
                let nsError = taskError as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 { return }
                if nsError.code == 1 || nsError.code == 301 { return }
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
        audioFile = nil
        isRecording = false
    }

    func consumeRecordedAudio() -> Data? {
        guard let url = recordedAudioURL else { return nil }
        defer {
            try? FileManager.default.removeItem(at: url)
            recordedAudioURL = nil
        }
        return try? Data(contentsOf: url)
    }
}
