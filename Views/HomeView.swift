import AVFoundation
import Speech
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(OnboardingManager.self) private var onboarding

    @State private var titleOpacity: Double = 0
    @State private var titleScale: CGFloat = 0.88
    @State private var titleBlur: CGFloat = 8
    @State private var lineWidth: CGFloat = 0
    @State private var subtitleOpacity: Double = 0
    @State private var bottomBarOpacity: Double = 0
    @State private var tipIndex: Int = 0
    @State private var tipOpacity: Double = 1.0

    private let tips: [String] = [
        "what can i help with?",
        "try: \"remind me to call mom at 5pm\"",
        "say: \"take a photo\"",
        "try: \"play some lo-fi music\"",
        "say: \"set brightness to 50%\"",
        "try: \"text Sarah i'm on my way\"",
        "say: \"what's on my calendar today?\"",
        "try: \"turn on the flashlight\"",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CosmicBackground(showComet: onboarding.isActive)

            VStack(spacing: 0) {
                // Top bar with auth — hidden during onboarding
                if !onboarding.isActive {
                    HStack {
                        Spacer()
                        if authManager.isAuthenticated {
                            Menu {
                                if let email = authManager.userEmail {
                                    Text(email)
                                }
                                Button("Sign Out", role: .destructive) {
                                    authManager.signOut()
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        } else {
                            Button {
                                Task { await authManager.signInWithGoogle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 14))
                                    Text("Sign In")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.06))
                                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                )
                            }
                            .disabled(authManager.isAuthenticating)
                            .opacity(authManager.isAuthenticating ? 0.5 : 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .opacity(bottomBarOpacity)
                }

                Spacer()

                if onboarding.isActive {
                    // MARK: - Onboarding content
                    onboardingContent
                } else {
                    // MARK: - Normal greeting + tips
                    normalContent
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.8), value: viewModel.hasUsedRecording)
            .animation(.easeInOut(duration: 0.5), value: onboarding.isActive)

            // Auth error toast
            if let error = authManager.authError {
                VStack {
                    Text(String(error.prefix(100)))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.3))
                                .stroke(Color.red.opacity(0.4), lineWidth: 0.5)
                        )
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Recalibration overlay (triggered from Settings)
            if onboarding.isRecalibrating {
                recalibrationOverlay
            }

            // Orb — always visible, particle count grows during onboarding
            VStack(spacing: 0) {
                Spacer()

                ParticleOrbView(
                    viewModel: viewModel,
                    visibleParticleCount: onboarding.isActive ? onboardingParticleCount : 0,
                    interactionEnabled: !onboarding.isActive
                )
                .opacity(bottomBarOpacity)
                .padding(.bottom, -20)
            }
            .ignoresSafeArea(edges: .bottom)

            // Live transcript + status — floating above bottom
            VStack(spacing: 2) {
                Spacer()

                if viewModel.isRecording && !viewModel.liveTranscript.isEmpty {
                    Text(viewModel.liveTranscript)
                        .font(.system(size: 14, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                }

                if let status = viewModel.statusMessage, viewModel.orbPhase != .sending {
                    Text(status)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.35))
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 16)
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            runEntrance()
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
            // Auto-advance onboarding when sign-in completes
            if isAuth && onboarding.isActive && onboarding.currentStep == .connect {
                onboarding.advance()
            }
        }
        .task {
            // Wait for entrance animation to finish
            try? await Task.sleep(for: .seconds(3.0))
            // Rotate tips every 4 seconds (paused while response is showing or onboarding)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4.0))
                guard viewModel.lastSpokenResponse == nil, !onboarding.isActive else { continue }
                withAnimation(.easeOut(duration: 0.5)) {
                    tipOpacity = 0
                }
                try? await Task.sleep(for: .seconds(0.5))
                tipIndex = (tipIndex + 1) % tips.count
                withAnimation(.easeIn(duration: 0.5)) {
                    tipOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Onboarding Content

    @ViewBuilder
    private var onboardingContent: some View {
        Spacer()
        Spacer()

        // Title + subtitle below center
        VStack(spacing: 16) {
            Text(onboarding.titleText)
                .font(.system(size: 32, weight: .thin))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 32)

            // Divider line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 60, height: 0.5)

            Text(onboarding.subtitleText)
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .opacity(onboarding.stepOpacity)

        if onboarding.currentStep == .wakeWord {
            calibrationSlotsView
                .opacity(onboarding.stepOpacity)
                .padding(.top, 24)
        }

        Spacer()

        // Button(s) between text and orb — easy thumb reach
        if onboarding.currentStep == .wakeWord {
            // Custom controls for wake word calibration
            wakeWordButtons
                .opacity(onboarding.stepOpacity)
                .padding(.bottom, 80)
        } else if let label = onboarding.buttonLabel {
            HStack(spacing: 12) {
                Button {
                    handleOnboardingAction()
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.06))
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                }

                if let skip = onboarding.skipLabel {
                    Button {
                        onboarding.advance()
                    } label: {
                        Text(skip)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
            }
            .opacity(onboarding.stepOpacity)
            .padding(.bottom, 80)
        }
    }

    /// Particle count grows evenly across onboarding steps: ~25 per step → 150 at done
    private var onboardingParticleCount: Int {
        let stepsCount = OnboardingManager.Step.allCases.count
        let perStep = 150 / stepsCount  // 25 per step
        let stepIndex = OnboardingManager.Step.allCases.firstIndex(of: onboarding.currentStep) ?? 0
        return max(perStep, perStep * (stepIndex + 1))
    }

    // MARK: - Calibration UI

    @ViewBuilder
    private var calibrationSlotsView: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 10) {
                    if index < onboarding.calibrationSamples.count {
                        // Completed
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.green.opacity(0.7))
                        Text(onboarding.calibrationSamples[index])
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    } else if index == onboarding.calibrationSamples.count && onboarding.isRecordingSample {
                        // Recording
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white.opacity(0.5))
                        Text("listening...")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        // Pending
                        Image(systemName: "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("---")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    Spacer()
                }
                .frame(maxWidth: 220)
            }
        }
    }

    @ViewBuilder
    private var wakeWordButtons: some View {
        HStack(spacing: 12) {
            if onboarding.calibrationComplete {
                Button {
                    onboarding.finalizeCalibration()
                    onboarding.advance()
                } label: {
                    Text("continue")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.06))
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                }
            } else {
                Button {
                    viewModel.wakeWordDetector.pause()
                    onboarding.recordCalibrationSample()
                    // Resume wake word after sample with delay
                    Task { @MainActor in
                        // Wait for recording flag to clear
                        while onboarding.isRecordingSample {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        try? await Task.sleep(for: .milliseconds(500))
                        viewModel.resumeWakeWordIfNeeded()
                    }
                } label: {
                    Text("tap to record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.06))
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                }
                .disabled(onboarding.isRecordingSample)
                .opacity(onboarding.isRecordingSample ? 0.4 : 1)
            }

            Button {
                onboarding.resetCalibrationState()
                onboarding.advance()
            } label: {
                Text("skip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Recalibration Overlay

    @ViewBuilder
    private var recalibrationOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("recalibrate your voice")
                    .font(.system(size: 28, weight: .thin))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.6))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.12), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 60, height: 0.5)

                Text("say 'osmo' three times so we recognize you")
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                calibrationSlotsView
                    .padding(.top, 8)

                Spacer()

                HStack(spacing: 12) {
                    if onboarding.calibrationComplete {
                        Button {
                            onboarding.finishRecalibration()
                            viewModel.resumeWakeWordIfNeeded()
                        } label: {
                            Text("done")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.06))
                                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                    } else {
                        Button {
                            viewModel.wakeWordDetector.pause()
                            onboarding.recordCalibrationSample()
                            Task { @MainActor in
                                while onboarding.isRecordingSample {
                                    try? await Task.sleep(for: .milliseconds(100))
                                }
                                try? await Task.sleep(for: .milliseconds(500))
                                viewModel.resumeWakeWordIfNeeded()
                            }
                        } label: {
                            Text("tap to record")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.06))
                                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .disabled(onboarding.isRecordingSample)
                        .opacity(onboarding.isRecordingSample ? 0.4 : 1)
                    }

                    Button {
                        onboarding.cancelRecalibration()
                        viewModel.resumeWakeWordIfNeeded()
                    } label: {
                        Text("cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Normal Content

    @ViewBuilder
    private var normalContent: some View {
        // Personalized greeting — fades away after first recording
        if !viewModel.hasUsedRecording {
            Text(greetingText)
                .font(.system(size: 32, weight: .thin))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 32)
                .opacity(titleOpacity)
                .scaleEffect(titleScale)
                .blur(radius: titleBlur)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.6), value: greetingText)
                .transition(.opacity)

            // Divider line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: lineWidth, height: 0.5)
                .padding(.top, 12)
                .transition(.opacity)
        }

        // Subtitle area: LLM response (typewriter), briefing card, or rotating tips
        Group {
            if viewModel.lastSpokenResponse != nil {
                Text(MarkdownParser.stripMarkdown(viewModel.displayedResponse))
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(8)
                    .frame(maxHeight: 160)
                    .transition(.opacity)
                    .onTapGesture {
                        viewModel.showChat = true
                    }
            } else if let briefing = viewModel.briefingText {
                Text(briefing)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.white.opacity(0.04))
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .transition(.opacity)
                    .onTapGesture {
                        viewModel.showChat = true
                    }
            } else {
                Text(tips[tipIndex])
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(tipOpacity)
                    .transition(.opacity)
            }
        }
        .opacity(subtitleOpacity)
        .padding(.top, viewModel.hasUsedRecording ? 0 : 10)
        .padding(.horizontal, 32)
        .frame(minHeight: 20)
        .animation(.easeInOut(duration: 0.4), value: viewModel.lastSpokenResponse == nil)
    }

    // MARK: - Onboarding Actions

    private func handleOnboardingAction() {
        switch onboarding.currentStep {
        case .welcome, .voiceFirst:
            onboarding.advance()
        case .connect:
            if authManager.isAuthenticated {
                onboarding.advance()
            } else {
                Task { @MainActor in
                    await authManager.signInWithGoogle()
                    if authManager.isAuthenticated && onboarding.currentStep == .connect {
                        onboarding.advance()
                    }
                }
            }
        case .microphone:
            Task { @MainActor in
                await requestSpeechAndMicrophoneAccess()
                onboarding.advance()
            }
        case .wakeWord:
            break
        case .calendar:
            Task { @MainActor in
                _ = await EventKitManager.shared.requestAccess()
                onboarding.advance()
            }
        case .done:
            break
        }
    }

    // MARK: - Helpers

    private var greetingText: String {
        if let name = authManager.firstName {
            return "Hi, \(name)"
        }
        return "Hi there"
    }

    /// Calls into nonisolated context so system API callbacks don't inherit
    /// @MainActor isolation (which causes dispatch_assert_queue crashes).
    private func requestSpeechAndMicrophoneAccess() async {
        await _requestSpeechAndMicrophoneAccess()
    }

    private func runEntrance() {
        // Title reveals with blur-to-sharp
        withAnimation(.easeOut(duration: 1.8)) {
            titleOpacity = 1
            titleScale = 1.0
            titleBlur = 0
        }

        // Line extends
        withAnimation(.easeOut(duration: 1.0).delay(0.6)) {
            lineWidth = 60
        }

        // Subtitles fade in
        withAnimation(.easeOut(duration: 0.8).delay(1.0)) {
            subtitleOpacity = 1
        }

        // Bottom bar appears last
        withAnimation(.easeOut(duration: 0.6).delay(1.6)) {
            bottomBarOpacity = 1
        }
    }
}

// MARK: - Nonisolated permission helpers

/// Runs speech + microphone permission requests outside @MainActor so the
/// system's background-thread callbacks don't trigger dispatch_assert_queue.
/// With SWIFT_APPROACHABLE_CONCURRENCY + SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor,
/// closures in @MainActor context get runtime main-queue assertions injected —
/// calling this from nonisolated context avoids that.
nonisolated private func _requestSpeechAndMicrophoneAccess() async {
    _ = await withUnsafeContinuation { (continuation: UnsafeContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
    _ = await AVAudioApplication.requestRecordPermission()
}
