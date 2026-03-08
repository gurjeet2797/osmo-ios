import AVFoundation
import Speech
import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(OnboardingManager.self) private var onboarding

    @State private var showFAQ = false
    @State private var titleOpacity: Double = 0
    @State private var titleScale: CGFloat = 0.88
    @State private var titleBlur: CGFloat = 8
    @State private var lineWidth: CGFloat = 0
    @State private var subtitleOpacity: Double = 0
    @State private var bottomBarOpacity: Double = 0
    @State private var responseOverflows: Bool = false
    @State private var guideTipCenter: CGPoint?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CosmicBackground(
                showComet: onboarding.isActive,
                guideTarget: guideTipCenter,
                cometFriendly: viewModel.hasUsedRecording,
                externalTouchPoint: viewModel.globalTouchPoint,
                externalTouchActive: viewModel.globalTouchActive
            )

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
                                Button {
                                    showFAQ = true
                                } label: {
                                    Label("What Can Osmo Do?", systemImage: "questionmark.circle")
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
        .sheet(isPresented: $showFAQ) {
            FAQView()
        }
        .task {
            runEntrance()
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
            // Auto-advance onboarding when sign-in completes
            if isAuth && onboarding.isActive && onboarding.currentStep == .connect {
                onboarding.advance()
            }
        }
        .onChange(of: onboarding.isActive) { _, isActive in
            if !isActive {
                // Onboarding just completed — start post-onboarding guide
                Task {
                    try? await Task.sleep(for: .seconds(1.0))
                    viewModel.startGuideIfNeeded()
                }
            }
        }
        .task {
            // If onboarding was already completed in a prior session, start guide on appear
            if !onboarding.isActive {
                try? await Task.sleep(for: .seconds(2.5))
                viewModel.startGuideIfNeeded()
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

        Spacer()

        // Button(s) between text and orb — easy thumb reach
        if let label = onboarding.buttonLabel {
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

    // MARK: - Normal Content

    @ViewBuilder
    private var normalContent: some View {
        // Weather or greeting — fades away after first recording or when response is showing
        if !viewModel.hasUsedRecording && viewModel.lastSpokenResponse == nil {
            if let temp = viewModel.weatherTemp {
                // Weather display
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        if let icon = viewModel.weatherIcon {
                            Image(systemName: icon)
                                .font(.system(size: 28, weight: .thin))
                                .foregroundStyle(.white.opacity(0.5))
                                .symbolRenderingMode(.hierarchical)
                        }
                        Text(temp)
                            .font(.system(size: 36, weight: .thin))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if let condition = viewModel.weatherCondition {
                        Text(condition)
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if let city = viewModel.weatherLocation {
                        Text(city)
                            .font(.system(size: 11, weight: .light, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 32)
                .opacity(titleOpacity)
                .scaleEffect(titleScale)
                .blur(radius: titleBlur)
                .transition(.opacity)
            } else {
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
            }

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

        // Subtitle area: LLM response (typewriter), widget cards, or guide tips
        Group {
            if viewModel.lastSpokenResponse != nil {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 6) {
                                Text(MarkdownParser.stripMarkdown(viewModel.displayedResponse))
                                    .font(.system(size: 13, weight: .light))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                // Guide hint right below response text
                                if viewModel.guideStep == .tapToType {
                                    guideTapToTypeHint
                                }
                            }
                            .padding(.vertical, 8)
                            .background(
                                GeometryReader { contentGeo in
                                    Color.clear
                                        .onChange(of: viewModel.displayedResponse) { _, _ in
                                            responseOverflows = contentGeo.size.height > geo.size.height
                                        }
                                        .onAppear {
                                            responseOverflows = contentGeo.size.height > geo.size.height
                                        }
                                }
                            )
                            .frame(minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                    }
                    .frame(maxHeight: 560)
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 16)
                            Color.black
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 24)
                        }
                    )

                    if responseOverflows && viewModel.guideStep != .tapToType {
                        HStack(spacing: 4) {
                            Text("tap for full details")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(1)
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 4)
                    }
                }
                .transition(.opacity)
                .onTapGesture {
                    HapticEngine.tap()
                    if viewModel.guideStep == .tapToType {
                        viewModel.completeGuide()
                        guideTipCenter = nil
                    }
                    viewModel.openChatWithCurrentConversation()
                }
            } else if viewModel.guideStep == .nameCheck {
                guideNameCheckTip
                    .transition(.opacity)
            } else if hasAnyWidgetData {
                homeWidgetStack
                    .transition(.opacity)
                    .onTapGesture {
                        HapticEngine.tap()
                        viewModel.openChatWithCurrentConversation()
                    }
            }
        }
        .opacity(subtitleOpacity)
        .padding(.top, viewModel.lastSpokenResponse != nil ? 0 : (viewModel.hasUsedRecording ? 0 : 10))
        .padding(.horizontal, 24)
        .frame(minHeight: 20)
        .animation(.easeInOut(duration: 0.4), value: viewModel.lastSpokenResponse == nil)
    }

    /// True when at least one home widget has actual data to display
    private var hasAnyWidgetData: Bool {
        for widget in viewModel.homeWidgets {
            switch widget {
            case .calendar: if !viewModel.upcomingEvents.isEmpty { return true }
            case .briefing: if viewModel.briefingText != nil { return true }
            case .email: if let e = viewModel.emailWidgetData, e.unreadCount > 0 { return true }
            case .commute: if let c = viewModel.commuteWidgetData, c.duration != nil { return true }
            case .weather: if viewModel.weatherTemp != nil { return true }
            }
        }
        return false
    }

    // MARK: - Home Widget Stack

    @ViewBuilder
    private var homeWidgetStack: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.homeWidgets, id: \.self) { widget in
                widgetCard(for: widget)
            }
        }
    }

    @ViewBuilder
    private func widgetCard(for widget: HomeWidgetType) -> some View {
        switch widget {
        case .calendar:
            if !viewModel.upcomingEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.upcomingEvents.prefix(2)) { event in
                        HStack(spacing: 6) {
                            Text(event.formattedTime)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            Text(event.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.04))
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        case .briefing:
            if let briefing = viewModel.briefingText {
                Text(briefing)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.white.opacity(0.04))
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
        case .email:
            if let email = viewModel.emailWidgetData, email.unreadCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("\(email.unreadCount) unread")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(email.topEmails.prefix(2)) { preview in
                        Text("\(preview.sender): \(preview.subject)")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.04))
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        case .commute:
            if let commute = viewModel.commuteWidgetData, let duration = commute.duration {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duration)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        if let dest = commute.destination {
                            Text("to \(dest)")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.04))
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        case .weather:
            if let temp = viewModel.weatherTemp, let condition = viewModel.weatherCondition {
                HStack(spacing: 8) {
                    if let icon = viewModel.weatherIcon {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text("\(temp) \(condition)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    if let city = viewModel.weatherLocation {
                        Spacer()
                        Text(city)
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.04))
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Guide Tips

    private var guideNameCheckTip: some View {
        VStack(spacing: 8) {
            Text("do I have your name right?")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Text("tap the orb and say \"my name is...\"")
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    let frame = geo.frame(in: .global)
                    guideTipCenter = CGPoint(x: frame.midX, y: frame.midY)
                }
            }
        )
    }

    private var guideTapToTypeHint: some View {
        Text("still wrong? tap here to type it instead")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 4)
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        let frame = geo.frame(in: .global)
                        guideTipCenter = CGPoint(x: frame.midX, y: frame.midY)
                    }
                }
            )
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
