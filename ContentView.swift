import SwiftUI
@preconcurrency import Translation

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = AppViewModel()

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
            .fullScreenCover(item: $viewModel.pendingCameraAction) { action in
                CameraView(action: action) {
                    viewModel.pendingCameraAction = nil
                }
                .ignoresSafeArea()
            }
            .sheet(item: $viewModel.pendingMessageAction) { action in
                MessageComposeView(action: action) {
                    viewModel.pendingMessageAction = nil
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
                viewModel.addGreetingIfNeeded()
                LocationManager.shared.requestPermissionAndStart()
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
