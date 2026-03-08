import SwiftUI

@main
struct MacOSApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        MenuBarExtra("Osmo AI", systemImage: "sparkles") {
            MenuBarView()
                .environment(authManager)
                .onOpenURL { url in
                    if url.scheme == APIConfig.customURLScheme {
                        try? authManager.handleDeepLink(url: url)
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
