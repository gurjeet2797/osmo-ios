import SwiftUI

@main
struct OsmoApp: App {
    @State private var authManager = AuthManager()
    @State private var onboardingManager = OnboardingManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(onboardingManager)
                .onOpenURL { url in
                    // Handle osmo:// deep links from OAuth callback
                    if url.scheme == APIConfig.customURLScheme {
                        try? authManager.handleDeepLink(url: url)
                    }
                }
        }
    }
}
