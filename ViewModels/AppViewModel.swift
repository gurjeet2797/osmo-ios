import SwiftUI
import Translation

@Observable
final class AppViewModel {
    var conversations: [Conversation] = []
    var currentConversation: Conversation?
    var inputText: String = ""
    var isLoading: Bool = false
    var showChat: Bool = false
    var showHistory: Bool = false
    var showControlCenter: Bool = false
    var activeCategory: CategoryType? = nil
    var errorMessage: String?
    var pendingConfirmation: PendingConfirmation?

    // UI-presenting device actions
    var pendingCameraAction: DeviceAction?
    var pendingMessageAction: DeviceAction?
    var pendingTranslationConfig: TranslationSession.Configuration?

    // Calendar
    var upcomingEvents: [CalendarEvent] = []
    var isLoadingEvents: Bool = false

    // Auth — set by ContentView on appear
    weak var authManager: AuthManager?

    // Recording
    let speechRecognizer = SpeechRecognizer()
    var isRecording: Bool = false
    var liveTranscript: String = ""
    var statusMessage: String?
    private var statusDismissTask: Task<Void, Never>?

    // LLM response shown on HomeView
    var lastSpokenResponse: String?
    var displayedResponse: String = ""
    private var responseDismissTask: Task<Void, Never>?
    private var typewriterTask: Task<Void, Never>?

    // Tracks whether the user has tapped record this session (for title fade)
    var hasUsedRecording: Bool = false

    // Silence detection — auto-send after 2s of no new speech
    private var silenceTimer: Task<Void, Never>?

    // Orb state
    var orbPhase: OrbPhase = .idle

    let apiClient = APIClient()

    // MARK: - Orb Phase

    enum OrbPhase: Equatable {
        case idle
        case listening
        case transcribing
        case sending
        case success
        case error
    }

    // MARK: - Placeholder suggestions (customize these)

    let suggestions: [String] = [
        "What's on my calendar today?",
        "Schedule a meeting tomorrow at 2pm",
        "Find free time this week",
        "Show my upcoming events",
        "Cancel my next meeting"
    ]

    // MARK: - Category types (customize these)

    enum CategoryType: String, CaseIterable {
        case category1 = "Category 1"
        case category2 = "Category 2"
        case category3 = "Category 3"
        case category4 = "Category 4"
    }

    var needsConfirmation: Bool { pendingConfirmation != nil }

    struct PendingConfirmation {
        let planId: String
        let prompt: String
        let messageId: UUID
    }

    func fetchUpcomingEvents() {
        isLoadingEvents = true
        Task {
            do {
                let events = try await apiClient.fetchUpcomingEvents()
                upcomingEvents = events
            } catch {
                // Silently fail — the view shows placeholder text
            }
            isLoadingEvents = false
        }
    }

    func addGreetingIfNeeded() {
        guard currentConversation == nil else { return }
        var conversation = Conversation()
        let greeting = Message(
            content: "Hey! I'm Osmo, your personal calendar assistant. Try saying \"Schedule a meeting tomorrow at 2pm\" or tap the mic to get started.",
            isUser: false
        )
        conversation.messages.append(greeting)
        currentConversation = conversation
    }

    func startNewConversation() {
        let conversation = Conversation()
        currentConversation = conversation
        showChat = true
    }

    func selectSuggestion(_ suggestion: String) {
        if currentConversation == nil {
            currentConversation = Conversation()
        }
        showChat = true
        inputText = suggestion
        sendMessage()
    }

    // MARK: - Recording

    func startRecording() {
        // Gate: require authentication before recording
        if let auth = authManager, !auth.isAuthenticated {
            Task { await auth.signInWithGoogle() }
            return
        }

        if currentConversation == nil {
            currentConversation = Conversation()
        }

        if !hasUsedRecording {
            hasUsedRecording = true
        }

        orbPhase = .listening
        liveTranscript = ""

        // Wire up callbacks (these fire from background thread via @Sendable)
        speechRecognizer.onTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liveTranscript = text
                if self.orbPhase == .listening && !text.isEmpty {
                    self.orbPhase = .transcribing
                }
                // Reset silence timer — auto-send after 2s of no new speech
                self.resetSilenceTimer()
            }
        }
        speechRecognizer.onError = { [weak self] errorText in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.errorMessage = errorText
                self.speechRecognizer.stopRecording()
                self.isRecording = false
            }
        }

        Task {
            let authorized = await speechRecognizer.requestAuthorization()
            guard authorized else {
                errorMessage = speechRecognizer.error ?? "Speech recognition not available"
                orbPhase = .idle
                return
            }

            do {
                try speechRecognizer.startRecording()
                isRecording = true
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                orbPhase = .idle
            }
        }
    }

    func stopRecordingAndSend() {
        guard isRecording else { return }
        silenceTimer?.cancel()
        silenceTimer = nil

        // Use liveTranscript (already on MainActor) as the authoritative source
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        speechRecognizer.stopRecording()
        isRecording = false

        guard !text.isEmpty else {
            orbPhase = .idle
            liveTranscript = ""
            return
        }

        inputText = text
        liveTranscript = ""
        sendMessage()
    }

    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        // Only start timer if we have some transcript to send
        guard !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        silenceTimer = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled && isRecording {
                stopRecordingAndSend()
            }
        }
    }

    // MARK: - Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = Message(content: text, isUser: true)
        currentConversation?.messages.append(userMessage)
        inputText = ""
        isLoading = true
        activeCategory = nil
        errorMessage = nil

        orbPhase = .sending
        showStatus("Command sent...")

        Task {
            do {
                showStatus("Processing...")
                let response = try await apiClient.sendCommand(
                    transcript: text,
                    latitude: LocationManager.shared.currentLatitude,
                    longitude: LocationManager.shared.currentLongitude
                )
                showStatus("Executed successfully")
                dismissStatusAfterDelay()
                handleCommandResponse(response)
                orbPhase = .success
                returnToIdleAfterDelay(seconds: 1.5)
            } catch let error as APIError {
                showStatus("Failed: \(error.localizedDescription ?? "Unknown error")")
                dismissStatusAfterDelay(seconds: 4)
                handleError(error)
                orbPhase = .error
                returnToIdleAfterDelay(seconds: 2.0)
            } catch {
                showStatus("Failed: \(error.localizedDescription)")
                dismissStatusAfterDelay(seconds: 4)
                handleError(.networkError(error))
                orbPhase = .error
                returnToIdleAfterDelay(seconds: 2.0)
            }
        }
    }

    func confirmPlan() {
        guard let confirmation = pendingConfirmation else { return }

        isLoading = true
        errorMessage = nil
        pendingConfirmation = nil

        Task {
            do {
                let response = try await apiClient.confirmPlan(planId: confirmation.planId)
                handleCommandResponse(response)
            } catch let error as APIError {
                handleError(error)
            } catch {
                handleError(.networkError(error))
            }
        }
    }

    func declineConfirmation() {
        if let confirmation = pendingConfirmation {
            // Update the confirmation message to show it was declined
            if let index = currentConversation?.messages.firstIndex(where: { $0.id == confirmation.messageId }) {
                currentConversation?.messages[index].requiresConfirmation = false
            }
        }
        pendingConfirmation = nil

        let declineMessage = Message(
            content: "Cancelled.",
            isUser: false,
            tags: ["cancelled"]
        )
        currentConversation?.messages.append(declineMessage)
    }

    func clearChat() {
        if let conversation = currentConversation, !conversation.messages.isEmpty {
            conversations.append(conversation)
        }
        currentConversation = nil
        showChat = false
        inputText = ""
        isLoading = false
        isRecording = false
        activeCategory = nil
        errorMessage = nil
        statusMessage = nil
        liveTranscript = ""
        pendingConfirmation = nil
        lastSpokenResponse = nil
        displayedResponse = ""
        responseDismissTask?.cancel()
        typewriterTask?.cancel()
        silenceTimer?.cancel()
        // Clear server-side session so LLM starts fresh
        Task { try? await apiClient.clearSession() }
        silenceTimer = nil
        orbPhase = .idle
        speechRecognizer.stopRecording()
    }

    func resumeConversation(_ conversation: Conversation) {
        if let current = currentConversation, current.id != conversation.id, !current.messages.isEmpty {
            conversations.append(current)
        }
        conversations.removeAll { $0.id == conversation.id }
        currentConversation = conversation
        showHistory = false
        showChat = true
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
    }

    func categoryText(for category: CategoryType, in message: Message) -> String? {
        guard let categories = message.categories else { return nil }
        switch category {
        case .category1: return categories.category1.isEmpty ? nil : categories.category1
        case .category2: return categories.category2.isEmpty ? nil : categories.category2
        case .category3: return categories.category3.isEmpty ? nil : categories.category3
        case .category4: return categories.category4.isEmpty ? nil : categories.category4
        }
    }

    // MARK: - Private

    private func showStatus(_ message: String) {
        statusMessage = message
    }

    private func dismissStatusAfterDelay(seconds: Double = 2.5) {
        statusDismissTask?.cancel()
        statusDismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled {
                statusMessage = nil
            }
        }
    }

    private func returnToIdleAfterDelay(seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled && (orbPhase == .success || orbPhase == .error) {
                orbPhase = .idle
            }
        }
    }

    private func handleCommandResponse(_ response: CommandResponse) {
        isLoading = false

        // Update user name if the backend changed it
        if let newName = response.updatedUserName {
            authManager?.updateName(newName)
        }

        // Show response on HomeView with typewriter animation
        let fullText = response.spokenResponse
        lastSpokenResponse = fullText
        displayedResponse = ""
        typewriterTask?.cancel()
        responseDismissTask?.cancel()

        typewriterTask = Task {
            for char in fullText {
                if Task.isCancelled { return }
                displayedResponse.append(char)
                try? await Task.sleep(for: .milliseconds(30))
            }
            // After typewriter finishes, auto-dismiss after 8 seconds
            if !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled {
                    lastSpokenResponse = nil
                    displayedResponse = ""
                }
            }
        }

        // Build tags from action plan steps
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
            planId: response.planId,
            requiresConfirmation: response.requiresConfirmation,
            deviceActions: response.deviceActions,
            attachments: response.attachments
        )
        currentConversation?.messages.append(message)

        // Handle confirmation flow
        if response.requiresConfirmation, let planId = response.planId {
            pendingConfirmation = PendingConfirmation(
                planId: planId,
                prompt: response.confirmationPrompt ?? response.spokenResponse,
                messageId: message.id
            )
        }

        // Handle device actions
        if !response.deviceActions.isEmpty {
            executeDeviceActions(response.deviceActions, planId: response.planId)
        }
    }

    private func handleError(_ error: APIError) {
        isLoading = false
        errorMessage = error.localizedDescription

        let errorMsg = Message(
            content: error.localizedDescription ?? "Something went wrong. Please try again.",
            isUser: false,
            tags: ["error"]
        )
        currentConversation?.messages.append(errorMsg)
    }

    private func executeDeviceActions(_ actions: [DeviceAction], planId: String?) {
        Task {
            var results: [DeviceActionResult] = []

            for action in actions {
                let result: DeviceActionResult
                switch action.toolName {
                case let name where name.hasPrefix("ios_eventkit."):
                    result = await EventKitManager.shared.executeAction(action)
                case let name where name.hasPrefix("ios_reminders."):
                    result = await ReminderManager.shared.executeAction(action)
                case let name where name.hasPrefix("ios_notifications."):
                    result = await NotificationManager.shared.executeAction(action)
                case let name where name.hasPrefix("ios_device."):
                    result = await DeviceControlManager.shared.executeAction(action)
                case let name where name.hasPrefix("ios_camera."):
                    pendingCameraAction = action
                    result = await CameraManager.shared.executeAction(action)
                    pendingCameraAction = nil
                case let name where name.hasPrefix("ios_messages."):
                    pendingMessageAction = action
                    result = await MessageManager.shared.executeAction(action)
                    pendingMessageAction = nil
                case let name where name.hasPrefix("ios_music."):
                    result = await MusicManager.shared.executeAction(action)
                case let name where name.hasPrefix("ios_app_launcher."):
                    result = await AppLauncherManager.shared.executeAction(action)
                case let name where name.hasPrefix("ios_translation."):
                    // Trigger SwiftUI .translationTask via config change
                    if let targetLang = action.args["target_language"]?.stringValue,
                       let langCode = TranslationManager.languageCodes[targetLang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] {
                        let target = Locale.Language(identifier: langCode)
                        pendingTranslationConfig = .init(target: target)
                    }
                    result = await TranslationManager.shared.executeAction(action)
                    pendingTranslationConfig = nil
                case let name where name.hasPrefix("ios_navigation."):
                    result = await NavigationManager.shared.executeAction(action)
                default:
                    result = DeviceActionResult(
                        actionId: action.actionId,
                        idempotencyKey: action.idempotencyKey,
                        success: false,
                        result: [:],
                        error: "Unknown tool: \(action.toolName)"
                    )
                }
                results.append(result)
            }

            // Surface any device action errors to the user
            let failures = results.filter { !$0.success }
            if !failures.isEmpty {
                let msgs = failures.compactMap(\.error)
                let joined = msgs.joined(separator: ". ")
                if !joined.isEmpty {
                    let errMsg = Message(content: joined, isUser: false, tags: ["device_error"])
                    currentConversation?.messages.append(errMsg)
                }
            }

            // Report results back to backend
            if let planId {
                do {
                    _ = try await apiClient.reportDeviceResults(planId: planId, results: results)
                } catch {
                    // Log but don't show to user — the local action already succeeded/failed
                }
            }
        }
    }
}
