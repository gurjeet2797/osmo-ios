import Foundation
import MapKit
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

        // Map travel mode to Apple Maps direction mode
        let directionsMode: String
        switch travelMode.lowercased() {
        case "transit":
            directionsMode = MKLaunchOptionsDirectionsModeTransit
        case "walking":
            directionsMode = MKLaunchOptionsDirectionsModeWalking
        default:
            directionsMode = MKLaunchOptionsDirectionsModeDriving
        }

        // URL-encode the destination and open via maps:// URL for simplicity
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        let modeParam: String
        switch travelMode.lowercased() {
        case "transit": modeParam = "r"
        case "walking": modeParam = "w"
        default: modeParam = "d"
        }

        if let url = URL(string: "maps://?daddr=\(encoded)&dirflg=\(modeParam)") {
            await UIApplication.shared.open(url)
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: [
                    "opened_maps": .bool(true),
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
            error: "Could not open Maps"
        )
    }
}
