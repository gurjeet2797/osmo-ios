import SwiftUI

@Observable
final class OnboardingManager {
    enum Step: Int, CaseIterable {
        case welcome
        case voiceFirst
        case connect
        case microphone
        case wakeWord
        case calendar
        case done
    }

    var currentStep: Step = .welcome
    var isActive: Bool { !hasCompleted }
    var stepOpacity: Double = 1.0

    // MARK: - Calibration State

    var calibrationSamples: [String] = []
    var isRecordingSample: Bool = false
    var calibrationComplete: Bool = false
    var isRecalibrating: Bool = false

    @ObservationIgnored
    private var calibrator: VoiceCalibrator?

    /// 0.0 at welcome → 1.0 at done — drives orb growth
    var progress: CGFloat {
        let allSteps = Step.allCases
        guard let idx = allSteps.firstIndex(of: currentStep) else { return 0 }
        return CGFloat(idx) / CGFloat(max(allSteps.count - 1, 1))
    }

    @ObservationIgnored
    private var isAdvancing = false

    private(set) var hasCompleted: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            UserDefaults.standard.set(hasCompleted, forKey: "hasCompletedOnboarding")
        }
    }

    var titleText: String {
        switch currentStep {
        case .welcome: return "meet osmo"
        case .voiceFirst: return "your voice-first assistant"
        case .connect: return "let's connect"
        case .microphone: return "one more thing"
        case .wakeWord: return "teach osmo your voice"
        case .calendar: return "apple calendar too?"
        case .done: return "you're all set"
        }
    }

    var subtitleText: String {
        switch currentStep {
        case .welcome: return "a living companion for your digital life"
        case .voiceFirst: return "speak naturally. osmo listens, plans, and acts."
        case .connect: return "sign in with google to unlock calendar & email"
        case .microphone: return "osmo needs your voice to understand you"
        case .wakeWord: return "say 'osmo' three times so we recognize you"
        case .calendar: return "optionally connect your on-device calendar for local events"
        case .done: return "tap the orb to begin"
        }
    }

    var buttonLabel: String? {
        switch currentStep {
        case .welcome, .voiceFirst: return "continue"
        case .connect: return "sign in with google"
        case .microphone: return "enable microphone"
        case .wakeWord: return nil
        case .calendar: return "enable apple calendar"
        case .done: return nil
        }
    }

    /// Secondary action label — shown alongside the primary button for skippable steps.
    var skipLabel: String? {
        switch currentStep {
        case .wakeWord, .calendar: return "skip"
        default: return nil
        }
    }

    func advance() {
        guard !isAdvancing else { return }
        isAdvancing = true

        let allSteps = Step.allCases
        guard let idx = allSteps.firstIndex(of: currentStep),
              idx + 1 < allSteps.count else {
            isAdvancing = false
            complete()
            return
        }

        let nextStep = allSteps[idx + 1]

        withAnimation(.easeOut(duration: 0.3)) {
            stepOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            self.currentStep = nextStep
            self.isAdvancing = false
            withAnimation(.easeIn(duration: 0.4)) {
                self.stepOpacity = 1.0
            }

            // Auto-complete the "done" step after a pause
            if nextStep == .done {
                try? await Task.sleep(for: .seconds(2.5))
                self.complete()
            }
        }
    }

    func complete() {
        withAnimation(.easeOut(duration: 0.5)) {
            stepOpacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.hasCompleted = true
        }
    }

    // MARK: - Voice Calibration

    func recordCalibrationSample() {
        guard !isRecordingSample, calibrationSamples.count < 3 else { return }
        isRecordingSample = true

        if calibrator == nil {
            calibrator = VoiceCalibrator()
        }

        Task { @MainActor in
            do {
                let transcription = try await _recordCalibrationSample(calibrator: calibrator!)
                if !transcription.isEmpty {
                    calibrationSamples.append(transcription)
                }
                if calibrationSamples.count >= 3 {
                    calibrationComplete = true
                }
            } catch {
                // Silently handle — user can retry
            }
            isRecordingSample = false
        }
    }

    func finalizeCalibration() {
        let unique = Array(Set(calibrationSamples))
        VoiceCalibrator.saveUserVariants(unique)
        calibrator?.cancel()
        calibrator = nil
    }

    func startRecalibration() {
        calibrationSamples = []
        calibrationComplete = false
        isRecalibrating = true
    }

    func finishRecalibration() {
        finalizeCalibration()
        isRecalibrating = false
    }

    func cancelRecalibration() {
        calibrator?.cancel()
        calibrator = nil
        calibrationSamples = []
        calibrationComplete = false
        isRecalibrating = false
    }

    func resetCalibrationState() {
        calibrationSamples = []
        calibrationComplete = false
        calibrator?.cancel()
        calibrator = nil
    }
}

/// Runs calibration recording outside @MainActor to avoid dispatch_assert_queue issues.
nonisolated private func _recordCalibrationSample(calibrator: VoiceCalibrator) async throws -> String {
    try await calibrator.recordSample()
}
