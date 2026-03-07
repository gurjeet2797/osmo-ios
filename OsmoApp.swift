import SwiftUI
import UIKit

@main
struct OsmoApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var pushDelegate
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
                .task {
                    // Request notification permission and register for APNs
                    let granted = await NotificationManager.shared.requestAccess()
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
        }
    }
}
