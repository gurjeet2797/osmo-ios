import SwiftUI
@preconcurrency import Translation

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = AppViewModel()
    @State private var lastForegroundRefresh: Date = .distantPast

    var body: some View {
        HomeView(viewModel: viewModel)
            .sheet(isPresented: $viewModel.showChat) {
                ChatSheetView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showHistory) {
                HistorySheetView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showControlCenter) {
                ControlCenterView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
            }
            .overlay {
                if viewModel.showVisionCamera || viewModel.orbPhase == .cameraTransition {
                    Color.black.opacity(0.5)
                        .blur(radius: 20)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.showVisionCamera)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.orbPhase)
                }
            }
            .overlay {
                if viewModel.showVisionCamera {
                    VisionCameraView { image in
                        viewModel.onPhotoCaptured(image)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.showVisionCamera)
                }
            }
            .fullScreenCover(item: $viewModel.pendingCameraAction) { action in
                CameraView(action: action) {
                    Task { @MainActor in
                        viewModel.pendingCameraAction = nil
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $viewModel.pendingMessageAction) { action in
                MessageComposeView(action: action) {
                    Task { @MainActor in
                        viewModel.pendingMessageAction = nil
                    }
                }
            }
            .translationTask(viewModel.pendingTranslationConfig) { session in
                guard let action = TranslationManager.shared.currentAction,
                      let text = action.args["text"]?.stringValue else {
                    return
                }
                let actionId = action.actionId
                let idempotencyKey = action.idempotencyKey
                let targetLang = action.args["target_language"]?.stringValue ?? ""

                // Bridge across isolation boundary — safe because translationTask
                // provides the session for exclusive use within this closure.
                let box = UncheckedSendableBox(session)
                let result: Result<String, Error> = await Task.detached {
                    do {
                        let response = try await box.value.translate(text)
                        return .success(response.targetText)
                    } catch {
                        return .failure(error)
                    }
                }.value

                switch result {
                case .success(let translated):
                    TranslationManager.shared.complete(DeviceActionResult(
                        actionId: actionId,
                        idempotencyKey: idempotencyKey,
                        success: true,
                        result: [
                            "translated_text": .string(translated),
                            "target_language": .string(targetLang),
                        ],
                        error: nil
                    ))
                case .failure(let error):
                    TranslationManager.shared.complete(DeviceActionResult(
                        actionId: actionId,
                        idempotencyKey: idempotencyKey,
                        success: false,
                        result: [:],
                        error: "Translation failed: \(error.localizedDescription)"
                    ))
                }
            }
            .preferredColorScheme(.dark)
            .task {
                viewModel.authManager = authManager
                authManager.restoreSession()
                await Task.yield()  // let SwiftUI finish layout before modifying state
                viewModel.loadPersistedConversations()
                viewModel.addGreetingIfNeeded()
                viewModel.fetchSuggestions()
                viewModel.fetchBriefing()
                viewModel.fetchPreferences()
                viewModel.fetchWidgetData()
                viewModel.fetchSubscriptionStatus()
                LocationManager.shared.requestPermissionAndStart()
                viewModel.fetchWeather()
                viewModel.fetchUpcomingEvents()
                viewModel.checkForProactiveNotifications()
            }
            .task {
                // Periodically check for proactive notifications (every 30 min)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1800))
                    viewModel.checkForProactiveNotifications()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Debounce: skip if refreshed within last 5 minutes
                    let now = Date()
                    guard now.timeIntervalSince(lastForegroundRefresh) > 300 else { return }
                    lastForegroundRefresh = now
                    viewModel.fetchUpcomingEvents()
                    viewModel.fetchWidgetData()
                    viewModel.fetchWeather()
                    viewModel.checkForProactiveNotifications()
                }
            }
    }
}

/// Wrapper to send a non-Sendable value across isolation boundaries when safety is guaranteed by context.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
