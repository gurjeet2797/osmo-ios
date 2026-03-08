import SwiftUI

struct MenuBarView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MacChatView()
            } else {
                MacSetupView()
            }
        }
        .frame(width: 360, height: 520)
        .background(MacCosmicBackground())
        .task {
            authManager.restoreSession()
        }
    }
}
