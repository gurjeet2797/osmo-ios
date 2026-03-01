import SwiftUI

@Observable
final class OnboardingManager {
    enum Step: Int, CaseIterable {
        case welcome
        case voiceFirst
        case connect
        case microphone
        case calendar
        case done
    }

    var currentStep: Step = .welcome
    var isActive: Bool { !hasCompleted }
    var stepOpacity: Double = 1.0

    @ObservationIgnored
    private var _hasCompleted: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var hasCompleted: Bool {
        get { _hasCompleted }
        set {
            _hasCompleted = newValue
            UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding")
        }
    }

    var titleText: String {
        switch currentStep {
        case .welcome: return "meet osmo"
        case .voiceFirst: return "your voice-first assistant"
        case .connect: return "let's connect"
        case .microphone: return "one more thing"
        case .calendar: return "stay organized"
        case .done: return "you're all set"
        }
    }

    var subtitleText: String {
        switch currentStep {
        case .welcome: return "a living companion for your digital life"
        case .voiceFirst: return "speak naturally. osmo listens, plans, and acts."
        case .connect: return "sign in with google to unlock calendar & email"
        case .microphone: return "osmo needs your voice to understand you"
        case .calendar: return "manage your schedule with a sentence"
        case .done: return "tap the orb to begin"
        }
    }

    var buttonLabel: String? {
        switch currentStep {
        case .welcome, .voiceFirst: return "continue"
        case .connect: return "sign in with google"
        case .microphone: return "enable microphone"
        case .calendar: return "enable calendar"
        case .done: return nil
        }
    }

    func advance() {
        let allSteps = Step.allCases
        guard let idx = allSteps.firstIndex(of: currentStep),
              idx + 1 < allSteps.count else {
            complete()
            return
        }

        withAnimation(.easeOut(duration: 0.3)) {
            stepOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.currentStep = allSteps[idx + 1]
            withAnimation(.easeIn(duration: 0.4)) {
                self.stepOpacity = 1.0
            }
        }

        // Auto-complete the "done" step after a pause
        if allSteps[idx + 1] == .done {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.complete()
            }
        }
    }

    func complete() {
        withAnimation(.easeOut(duration: 0.5)) {
            stepOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasCompleted = true
        }
    }
}
