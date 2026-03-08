import UIKit

enum HapticEngine {
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Soft tap — orb tap, response tap, opening sheets
    static func tap() {
        softImpact.impactOccurred()
    }

    /// Light tick — tab switches, toggles, selection changes
    static func tick() {
        selection.selectionChanged()
    }

    /// Subtle texture — comet proximity, background touch
    static func texture(intensity: CGFloat = 0.5) {
        lightImpact.impactOccurred(intensity: intensity)
    }

    /// Success — command completed
    static func success() {
        notification.notificationOccurred(.success)
    }

    /// Error feedback
    static func error() {
        notification.notificationOccurred(.error)
    }

    /// Swipe-up — control center reveal
    static func swipe() {
        mediumImpact.impactOccurred(intensity: 0.6)
    }

    /// Recording start — distinct feel
    static func recordStart() {
        mediumImpact.impactOccurred(intensity: 0.7)
    }

    /// Recording stop/send
    static func recordStop() {
        softImpact.impactOccurred(intensity: 0.8)
    }
}
