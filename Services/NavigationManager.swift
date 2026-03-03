import Foundation
import UIKit

final class NavigationManager: Sendable {
    static let shared = NavigationManager()

    private init() {}

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        switch action.toolName {
        case "ios_navigation.open_in_maps":
            return await openInMaps(action)
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
    private func openInMaps(_ action: DeviceAction) async -> DeviceActionResult {
        guard let destination = action.args["destination"]?.stringValue else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Missing destination"
            )
        }

        let travelMode = action.args["travel_mode"]?.stringValue ?? "driving"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination

        // Map travel mode to Google Maps parameter
        let googleMode: String
        switch travelMode.lowercased() {
        case "transit": googleMode = "transit"
        case "walking": googleMode = "walking"
        default: googleMode = "driving"
        }

        // Try Google Maps app first
        if let appURL = URL(string: "comgooglemaps://?daddr=\(encoded)&directionsmode=\(googleMode)"),
           UIApplication.shared.canOpenURL(appURL) {
            await UIApplication.shared.open(appURL)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: [
                    "opened_maps": .bool(true),
                    "app": .string("google_maps"),
                    "destination": .string(destination),
                    "travel_mode": .string(travelMode),
                ],
                error: nil
            )
        }

        // Fall back to Google Maps web (opens in Safari)
        if let webURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(encoded)&travelmode=\(googleMode)") {
            await UIApplication.shared.open(webURL)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: [
                    "opened_maps": .bool(true),
                    "app": .string("safari_google_maps"),
                    "destination": .string(destination),
                    "travel_mode": .string(travelMode),
                ],
                error: nil
            )
        }

        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: false,
            result: [:],
            error: "Could not open Google Maps"
        )
    }
}
