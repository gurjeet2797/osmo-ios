import SwiftUI

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
            .preferredColorScheme(.dark)
            .task {
                viewModel.authManager = authManager
                authManager.restoreSession()
                viewModel.addGreetingIfNeeded()
            }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
