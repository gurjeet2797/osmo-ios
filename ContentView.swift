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
            .preferredColorScheme(.dark)
            .task {
                authManager.restoreSession()
                viewModel.addGreetingIfNeeded()
            }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
