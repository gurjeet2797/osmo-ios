import SwiftUI

@Observable
final class MacAppViewModel {
    var conversations: [Conversation] = []
    var currentConversation: Conversation?
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    // Recording
    let speechRecognizer = MacSpeechRecognizer()
    var isRecording: Bool = false
    var liveTranscript: String = ""

    // Audio data for Whisper transcription
    private var pendingAudioData: Data?

    // Auth
    weak var authManager: AuthManager?

    let apiClient = APIClient()
    let conversationStore = ConversationStore()

    init() {}

    // MARK: - Conversations

    func loadPersistedConversations() {
        let loaded = conversationStore.load()
        if !loaded.isEmpty {
            conversations = loaded
        }
    }

    func persistConversations() {
        var all = conversations
        if let current = currentConversation, !current.messages.isEmpty {
            if !all.contains(where: { $0.id == current.id }) {
                all.append(current)
            }
        }
        conversationStore.save(all)
    }

    func addGreetingIfNeeded() {
        guard currentConversation == nil else { return }
        var conversation = Conversation()
        let greeting = Message(content: "Hey! Type or use the mic.", isUser: false)
        conversation.messages.append(greeting)
        currentConversation = conversation
    }

    func clearChat() {
        if let conversation = currentConversation, !conversation.messages.isEmpty {
            conversations.append(conversation)
        }
        persistConversations()
        currentConversation = nil
        inputText = ""
        isLoading = false
        isRecording = false
        errorMessage = nil
        liveTranscript = ""
        speechRecognizer.stopRecording()
        addGreetingIfNeeded()
    }

    // MARK: - Recording

    func startRecording() {
        if let auth = authManager, !auth.isAuthenticated {
            Task { await auth.signInWithGoogle() }
            return
        }

        if currentConversation == nil {
            currentConversation = Conversation()
        }

        liveTranscript = ""

        speechRecognizer.onTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.liveTranscript = text
            }
        }
        speechRecognizer.onError = { [weak self] errorText in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.errorMessage = errorText
                self.speechRecognizer.stopRecording()
                self.isRecording = false
            }
        }

        Task {
            let authorized = await speechRecognizer.requestAuthorization()
            guard authorized else {
                errorMessage = speechRecognizer.error ?? "Speech recognition not available"
                return
            }
            do {
                try speechRecognizer.startRecording()
                isRecording = true
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }

    func stopRecordingAndSend() {
        guard isRecording else { return }

        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        speechRecognizer.stopRecording()
        isRecording = false

        let audioData = speechRecognizer.consumeRecordedAudio()

        guard !text.isEmpty || audioData != nil else {
            liveTranscript = ""
            return
        }

        inputText = text.isEmpty ? "..." : text
        liveTranscript = ""
        pendingAudioData = audioData
        sendMessage()
    }

    // MARK: - Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = Message(content: text, isUser: true)
        currentConversation?.messages.append(userMessage)
        inputText = ""
        isLoading = true
        errorMessage = nil

        let audioForRequest = pendingAudioData
        pendingAudioData = nil

        Task {
            do {
                let response: CommandResponse
                if let audioData = audioForRequest {
                    response = try await apiClient.sendAudioCommand(audioData: audioData)
                } else {
                    response = try await apiClient.sendCommand(transcript: text)
                }
                handleResponse(response)
            } catch let error as APIError {
                handleError(error)
            } catch {
                handleError(.networkError(error))
            }
        }
    }

    private func handleResponse(_ response: CommandResponse) {
        isLoading = false

        if let newName = response.updatedUserName {
            authManager?.updateName(newName)
        }

        var tags: [String] = []
        if let plan = response.actionPlan {
            tags = plan.steps.map { step in
                let parts = step.toolName.split(separator: ".")
                return String(parts.last ?? Substring(step.toolName))
            }
        }

        let message = Message(
            content: response.spokenResponse,
            isUser: false,
            tags: tags.isEmpty ? nil : tags,
            deviceActions: response.deviceActions
        )
        currentConversation?.messages.append(message)

        // Handle macOS device actions
        if !response.deviceActions.isEmpty {
            executeDeviceActions(response.deviceActions, planId: response.planId)
        }

        persistConversations()
    }

    private func handleError(_ error: APIError) {
        isLoading = false
        errorMessage = error.localizedDescription
        let errMsg = Message(content: error.localizedDescription, isUser: false, tags: ["error"])
        currentConversation?.messages.append(errMsg)
    }

    private func executeDeviceActions(_ actions: [DeviceAction], planId: String?) {
        Task {
            var results: [DeviceActionResult] = []

            for action in actions {
                let result: DeviceActionResult
                if action.toolName.hasPrefix("macos_messages.") {
                    result = iMessageReader.shared.executeAction(action)
                } else {
                    result = DeviceActionResult(
                        actionId: action.actionId,
                        idempotencyKey: action.idempotencyKey,
                        success: false,
                        result: [:],
                        error: "Unsupported on macOS: \(action.toolName)"
                    )
                }
                results.append(result)
            }

            if let planId {
                do {
                    _ = try await apiClient.reportDeviceResults(planId: planId, results: results)
                } catch {
                    // Best-effort
                }
            }
        }
    }
}
