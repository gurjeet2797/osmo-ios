import Foundation
import UIKit

final class AppLauncherManager: Sendable {
    static let shared = AppLauncherManager()

    private static let appSchemes: [String: String] = [
        "maps": "maps://",
        "apple maps": "maps://",
        "phone": "tel://",
        "mail": "mailto://",
        "email": "mailto://",
        "facetime": "facetime://",
        "shortcuts": "shortcuts://",
        "settings": "App-prefs://",
        "photos": "photos-redirect://",
        "health": "x-apple-health://",
        "wallet": "shoebox://",
        "weather": "weather://",
        "clock": "clock-alarm://",
        "notes": "mobilenotes://",
        "files": "shareddocuments://",
        "safari": "x-web-search://",
        "app store": "itms-apps://",
        "music": "music://",
        "podcasts": "podcasts://",
        "news": "applenews://",
        "reminders": "x-apple-reminderkit://",
        "calendar": "calshow://",
        "messages": "sms://",
        "calculator": "calc://",
        "camera": "camera://",
        "contacts": "contacts://",
        "findmy": "findmy://",
        "find my": "findmy://",
        "home": "com.apple.home://",
        "books": "ibooks://",
        "translate": "translate://",
        "tips": "x-apple-tips://",
        "voice memos": "voicememos://",
        "watch": "bridgeos-companion://",
        "fitness": "fitnessapp://",
    ]

    private init() {}

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        switch action.toolName {
        case "ios_app_launcher.open_app":
            return await openApp(action)
        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown action: \(action.toolName)"
            )
        }
    }

    @MainActor
    private func openApp(_ action: DeviceAction) -> DeviceActionResult {
        guard let appName = action.args["app_name"]?.stringValue else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Missing app_name"
            )
        }

        let key = appName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let scheme = Self.appSchemes[key], let url = URL(string: scheme) {
            UIApplication.shared.open(url)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["opened_app": .string(appName)],
                error: nil
            )
        }

        // Fallback: search the App Store
        let searchQuery = appName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appName
        if let storeURL = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=\(searchQuery)") {
            UIApplication.shared.open(storeURL)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["searched_app_store": .string(appName)],
                error: nil
            )
        }

        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: false,
            result: [:],
            error: "Could not open \(appName)"
        )
    }
}
