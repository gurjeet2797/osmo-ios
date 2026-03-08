import CoreLocation
import SwiftUI
import UIKit
import Translation
import WeatherKit

@Observable
final class AppViewModel {
    var conversations: [Conversation] = []
    var currentConversation: Conversation?
    var inputText: String = ""
    var isLoading: Bool = false
    var showChat: Bool = false
    var showHistory: Bool = false
    var showControlCenter: Bool = false
    var showPaywall: Bool = false
    var showVisionCamera: Bool = false
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

    // Morning briefing
    var briefingText: String?

    // LLM response shown on HomeView
    var lastSpokenResponse: String?
    var displayedResponse: String = ""
    private var responseDismissTask: Task<Void, Never>?
    private var typewriterTask: Task<Void, Never>?

    // Tracks whether the user has tapped record this session (for title fade)
    var hasUsedRecording: Bool = false

    // Orb state
    var orbPhase: OrbPhase = .idle

    // Home widgets
    var homeWidgets: [HomeWidgetType] = [.calendar, .briefing, .email, .commute]

    // Post-onboarding guide
    enum GuideStep: Int, Sendable {
        case nameCheck   // "Do I have your name right?"
        case tapToType   // "Tap the message to type instead"
        case complete
    }
    var guideStep: GuideStep = .complete

    // Global touch state — shared across orb, background, and comet
    var globalTouchPoint: CGPoint?
    var globalTouchActive: Bool = false

    // Subscription
    var subscriptionTier: String = "free"
    var remainingRequests: Int?

    // Weather
    var weatherText: String?  // e.g. "72° Sunny"
    var weatherIcon: String?  // SF Symbol name
    var weatherTemp: String?  // e.g. "72°"
    var weatherCondition: String?  // e.g. "Sunny"
    var weatherLocation: String?  // e.g. "San Francisco"

    // Widget data
    var emailWidgetData: EmailWidgetData?
    var commuteWidgetData: CommuteWidgetData?

    // Vision — captured photo for next command
    var capturedPhoto: UIImage?

    // Audio data for Whisper transcription (captured during voice recording)
    private var pendingAudioData: Data?
    var cameraBlurAmount: CGFloat = 0

    let apiClient = APIClient()
    let conversationStore = ConversationStore()

    private var lastWidgetFetch: Date?
    private var lastEventFetch: Date?

    init() {}

    // MARK: - Orb Phase

    enum OrbPhase: Equatable {
        case idle
        case listening
        case transcribing
        case sending
        case success
        case error
        case cameraTransition
    }

    // MARK: - Suggestions (dynamically updated from backend)

    var suggestions: [String] = [
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

    func fetchSuggestions() {
        Task {
            do {
                let fetched = try await apiClient.fetchSuggestions()
                if !fetched.isEmpty {
                    suggestions = fetched
                }
            } catch {
                // Silently fail — keep default suggestions
            }
        }
    }

    func fetchBriefing() {
        Task {
            do {
                let response = try await apiClient.fetchBriefing()
                briefingText = response.briefing
            } catch {
                // Silently fail — no briefing available
            }
        }
    }

    // MARK: - Preferences

    func fetchPreferences() {
        Task {
            do {
                let prefs = try await apiClient.fetchPreferences()
                if let widgetJSON = prefs["home_widgets"],
                   let data = widgetJSON.data(using: .utf8),
                   let types = try? JSONDecoder().decode([HomeWidgetType].self, from: data) {
                    homeWidgets = types
                }
            } catch {
                // Silently fail
            }
        }
    }

    func fetchWidgetData(forceRefresh: Bool = false) {
        if !forceRefresh, let last = lastWidgetFetch, Date().timeIntervalSince(last) < 300 { return }
        lastWidgetFetch = Date()
        Task {
            do {
                let data = try await apiClient.fetchWidgetData()
                emailWidgetData = data.email
                commuteWidgetData = data.commute
            } catch {
                // Silently fail — widgets show placeholder
            }
        }
    }

    // MARK: - Weather

    func fetchWeather() {
        Task {
            guard let lat = LocationManager.shared.currentLatitude,
                  let lng = LocationManager.shared.currentLongitude else {
                // Retry once after a short delay for location to populate
                try? await Task.sleep(for: .seconds(2))
                guard let lat = LocationManager.shared.currentLatitude,
                      let lng = LocationManager.shared.currentLongitude else { return }
                await _loadWeather(lat: lat, lng: lng)
                return
            }
            await _loadWeather(lat: lat, lng: lng)
        }
    }

    private func _loadWeather(lat: Double, lng: Double) async {
        do {
            let location = CLLocation(latitude: lat, longitude: lng)
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather

            let tempF = current.temperature.converted(to: .fahrenheit)
            let temp = "\(Int(tempF.value))°"
            let condition = current.condition.description

            weatherTemp = temp
            weatherCondition = condition
            weatherText = "\(temp) \(condition)"
            weatherIcon = current.symbolName

            // Reverse geocode for city name
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let city = placemarks.first?.locality {
                weatherLocation = city
            }
        } catch {
            // Silently fail — weather is best-effort
        }
    }

    // MARK: - Post-Onboarding Guide

    private var hasCompletedGuide: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedGuide") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedGuide") }
    }

    func startGuideIfNeeded() {
        guard !hasCompletedGuide else { return }
        guideStep = .nameCheck
    }

    func advanceGuide() {
        switch guideStep {
        case .nameCheck:
            guideStep = .tapToType
        case .tapToType:
            completeGuide()
        case .complete:
            break
        }
    }

    func completeGuide() {
        guideStep = .complete
        hasCompletedGuide = true
    }

    func saveWidgetPreferences() {
        Task {
            if let data = try? JSONEncoder().encode(homeWidgets),
               let json = String(data: data, encoding: .utf8) {
                _ = try? await apiClient.savePreferences(["home_widgets": json])
            }
        }
    }

    // MARK: - Subscription

    func fetchSubscriptionStatus() {
        Task {
            do {
                let status = try await apiClient.fetchSubscriptionStatus()
                subscriptionTier = status.tier
                remainingRequests = status.remainingRequests
            } catch {
                // Silently fail
            }
        }
    }

    var isDevMode: Bool { subscriptionTier == "dev" }
    var isProOrDev: Bool { subscriptionTier == "pro" || subscriptionTier == "dev" }

    // MARK: - Vision (Photo → AI)

    func startPhotoThenVoice() {
        orbPhase = .cameraTransition
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraBlurAmount = 20
        }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            showVisionCamera = true
        }
    }

    func onPhotoCaptured(_ image: UIImage) {
        capturedPhoto = image
        showVisionCamera = false
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraBlurAmount = 0
        }
        orbPhase = .idle
        // Automatically start recording after capture
        startRecording()
    }

    func cancelVisionCamera() {
        showVisionCamera = false
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraBlurAmount = 0
        }
        orbPhase = .idle
    }

    // MARK: - Proactive Notifications

    func checkForProactiveNotifications() {
        Task {
            do {
                let notifications = try await apiClient.fetchPendingNotifications()
                guard !notifications.isEmpty else { return }

                await NotificationManager.shared.scheduleProactiveNotifications(notifications)

                let ids = notifications.map(\.id)
                try await apiClient.markNotificationsDelivered(ids)
            } catch {
                // Silently fail — notifications are best-effort
            }
        }
    }

    func fetchUpcomingEvents(days: Int = 1, forceRefresh: Bool = false) {
        if !forceRefresh, let last = lastEventFetch, Date().timeIntervalSince(last) < 300 { return }
        lastEventFetch = Date()
        isLoadingEvents = true
        Task {
            do {
                let events = try await apiClient.fetchUpcomingEvents(days: days)
                upcomingEvents = events
            } catch {
                // Silently fail — the view shows placeholder text
            }
            isLoadingEvents = false
        }
    }

    func loadPersistedConversations() {
        let loaded = conversationStore.load()
        if !loaded.isEmpty {
            conversations = loaded
        }
    }

    func persistConversations() {
        var all = conversations
        if let current = currentConversation, !current.messages.isEmpty {
            // Include current conversation in the save (don't duplicate)
            if !all.contains(where: { $0.id == current.id }) {
                all.append(current)
            }
        }
        conversationStore.save(all)
    }

    func addGreetingIfNeeded() {
        guard currentConversation == nil else { return }
        var conversation = Conversation()
        let greeting = Message(
            content: "Hey! Tap the orb or say something.",
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

    func openChatWithCurrentConversation() {
        if currentConversation == nil {
            currentConversation = Conversation()
        }
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
            }
        }
        speechRecognizer.onError = { [weak self] errorText in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Don't show errors if we're not actively recording (already stopped)
                guard self.isRecording else { return }
                self.errorMessage = errorText
                self.speechRecognizer.stopRecording()
                self.isRecording = false
                self.orbPhase = .idle
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

        // Use liveTranscript (already on MainActor) as the authoritative source
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        speechRecognizer.stopRecording()
        isRecording = false

        // Capture recorded audio for Whisper transcription
        let audioData = speechRecognizer.consumeRecordedAudio()

        guard !text.isEmpty || audioData != nil else {
            orbPhase = .idle
            liveTranscript = ""
            return
        }

        inputText = text.isEmpty ? "..." : text  // placeholder if Apple STT got nothing
        liveTranscript = ""
        pendingAudioData = audioData
        sendMessage()
    }

    // MARK: - Messaging

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Clear previous response from HomeView when user sends a new message
        typewriterTask?.cancel()
        lastSpokenResponse = nil
        displayedResponse = ""

        let userMessage = Message(content: text, isUser: true)
        currentConversation?.messages.append(userMessage)
        inputText = ""
        isLoading = true
        activeCategory = nil
        errorMessage = nil

        // Capture and clear photo and audio for this request
        let photoForRequest = capturedPhoto
        capturedPhoto = nil
        let audioForRequest = pendingAudioData
        pendingAudioData = nil

        orbPhase = .sending
        showStatus("Command sent...")

        Task {
            do {
                showStatus("Processing...")

                let response: CommandResponse

                if let audioData = audioForRequest {
                    // Whisper path: send raw audio for server-side transcription (multilingual)
                    response = try await apiClient.sendAudioCommand(
                        audioData: audioData,
                        latitude: LocationManager.shared.currentLatitude,
                        longitude: LocationManager.shared.currentLongitude
                    )

                    // Update the user message with Whisper's transcription if it differs
                    if let whisperText = response.spokenResponse.isEmpty ? nil : text,
                       whisperText == "..." {
                        // The placeholder was used — update chat with what Whisper heard
                    }
                } else {
                    // Text path: Apple STT already transcribed, or user typed
                    var imageBase64: String?
                    if let photo = photoForRequest,
                       let jpegData = photo.jpegData(compressionQuality: 0.7) {
                        let data = jpegData.count > 500_000
                            ? (photo.jpegData(compressionQuality: 0.3) ?? jpegData)
                            : jpegData
                        imageBase64 = data.base64EncodedString()
                    }

                    response = try await apiClient.sendCommand(
                        transcript: text,
                        latitude: LocationManager.shared.currentLatitude,
                        longitude: LocationManager.shared.currentLongitude,
                        imageData: imageBase64
                    )
                }
                showStatus("Executed successfully")
                dismissStatusAfterDelay()
                handleCommandResponse(response)
                orbPhase = .success
                HapticEngine.success()
                returnToIdleAfterDelay(seconds: 1.5)
            } catch let error as APIError {
                showStatus("Failed: \(error.localizedDescription)")
                dismissStatusAfterDelay(seconds: 4)
                handleError(error)
                orbPhase = .error
                HapticEngine.error()
                returnToIdleAfterDelay(seconds: 2.0)
            } catch {
                showStatus("Failed: \(error.localizedDescription)")
                dismissStatusAfterDelay(seconds: 4)
                handleError(.networkError(error))
                orbPhase = .error
                HapticEngine.error()
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
        persistConversations()
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

        // Update remaining requests
        if let remaining = response.remainingRequests {
            remainingRequests = remaining
        }

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
                try? await Task.sleep(for: .milliseconds(15))
            }
            // Response stays on screen until user sends a new message
        }

        // Build tags from action plan steps
        var tags: [String] = []
        if let plan = response.actionPlan {
            tags = plan.steps.map { step in
                let parts = step.toolName.split(separator: ".")
                return String(parts.last ?? Substring(step.toolName))
            }
        }

        let clarificationOpts = response.clarification?.options
        let message = Message(
            content: response.spokenResponse,
            isUser: false,
            tags: tags.isEmpty ? nil : tags,
            planId: response.planId,
            requiresConfirmation: response.requiresConfirmation,
            deviceActions: response.deviceActions,
            attachments: response.attachments,
            clarificationOptions: clarificationOpts
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

        // Persist after each response
        persistConversations()

        // Refresh widget data in case the command changed settings (e.g. work address)
        fetchWidgetData(forceRefresh: true)

        // Advance post-onboarding guide after first response
        if guideStep == .nameCheck {
            advanceGuide()
        }
    }

    private func handleError(_ error: APIError) {
        isLoading = false
        errorMessage = error.localizedDescription

        let errorMsg = Message(
            content: error.localizedDescription,
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
