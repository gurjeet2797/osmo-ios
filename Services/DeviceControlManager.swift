import AVFoundation
import Foundation
import UIKit

final class DeviceControlManager: Sendable {
    static let shared = DeviceControlManager()

    private init() {}

    func executeAction(_ action: DeviceAction) async -> DeviceActionResult {
        switch action.toolName {
        case "ios_device.copy_to_clipboard":
            return await copyToClipboard(action)
        case "ios_device.set_brightness":
            return await setBrightness(action)
        case "ios_device.flashlight":
            return toggleFlashlight(action)
        default:
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Unknown device action: \(action.toolName)"
            )
        }
    }

    // MARK: - Private

    @MainActor
    private func copyToClipboard(_ action: DeviceAction) -> DeviceActionResult {
        guard let text = action.args["text"]?.stringValue else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Missing text"
            )
        }

        UIPasteboard.general.string = text
        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: true,
            result: ["characters_copied": .int(text.count)],
            error: nil
        )
    }

    @MainActor
    private func setBrightness(_ action: DeviceAction) -> DeviceActionResult {
        guard let level = action.args["level"]?.doubleValue else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "Missing level"
            )
        }

        let clamped = min(max(level, 0.0), 1.0)
        UIScreen.main.brightness = clamped
        return DeviceActionResult(
            actionId: action.actionId,
            idempotencyKey: action.idempotencyKey,
            success: true,
            result: ["brightness": .double(clamped)],
            error: nil
        )
    }

    private func toggleFlashlight(_ action: DeviceAction) -> DeviceActionResult {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: "No flashlight available"
            )
        }

        let enabled = action.args["enabled"]?.boolValue ?? true
        let level = action.args["level"]?.doubleValue ?? 1.0

        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: Float(min(max(level, 0.0), 1.0)))
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: true,
                result: ["enabled": .bool(enabled)],
                error: nil
            )
        } catch {
            return DeviceActionResult(
                actionId: action.actionId,
                idempotencyKey: action.idempotencyKey,
                success: false,
                result: [:],
                error: error.localizedDescription
            )
        }
    }
}
