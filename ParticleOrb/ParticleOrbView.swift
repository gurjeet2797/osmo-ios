import SwiftUI
import os.signpost

private let pointsOfInterest = OSLog(subsystem: "com.yourcompany.Osmo", category: .pointsOfInterest)

struct ParticleOrbView: View {
    @Bindable var viewModel: AppViewModel
    /// Number of particles to render (0 = use system default). Animatable.
    var visibleParticleCount: Int = 0
    /// Whether the orb responds to taps/drags. Disable during onboarding.
    var interactionEnabled: Bool = true

    @State private var system = ParticleSystem()
    @State private var opacity: Double = 0.0
    @State private var startDate = Date()
    @State private var glowIntensity: Float = 0.0

    // Per-particle fade-in tracking (two scalars — no shared mutable array)
    @State private var countChangeTime: TimeInterval = 0
    @State private var previousVisibleCount: Int = 0

    // State machine + motion controller
    @State private var stateMachine = ParticleStateMachine()
    @State private var activeController: any MotionController = IdleBreath()
    @State private var stateEntryTime: Double = 0

    // Drag/tap detection
    @State private var dragStartTime: Date?
    @State private var dragStartLocation: CGPoint?

    // Pre-rendered sprite
    @State private var spriteImage: CGImage?

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Track previous phase for state machine mapping
    @State private var previousOrbPhase: AppViewModel.OrbPhase = .idle

    private let canvasSize: CGFloat = 220

    /// Target glow level based on orb phase
    private var targetGlow: Float {
        switch viewModel.orbPhase {
        case .listening, .transcribing:
            return 1.0
        default:
            return 0.0
        }
    }

    var body: some View {
        particleCanvas
            .frame(width: canvasSize, height: canvasSize)
            .opacity(opacity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard interactionEnabled else { return }

                        // Track drag start for tap/long-press detection
                        if dragStartTime == nil {
                            dragStartTime = Date()
                            dragStartLocation = value.startLocation
                        }

                        let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)
                        let touchX = Float(value.location.x - center.x)
                        let touchY = Float(value.location.y - center.y)
                        system.applyTouch(at: SIMD2<Float>(touchX, touchY))

                        // Transition to armed on touch-down when idle
                        if stateMachine.currentState == .idle {
                            stateMachine.transition(to: .armed, at: CACurrentMediaTime(), envelope: .quick)
                            activeController = MotionControllerRegistry.controller(for: .armed)
                        }

                        // Long press detection (0.5s held, minimal movement)
                        if let start = dragStartTime,
                           let startLoc = dragStartLocation {
                            let held = Date().timeIntervalSince(start)
                            let dx = value.location.x - startLoc.x
                            let dy = value.location.y - startLoc.y
                            let dist = sqrt(dx * dx + dy * dy)
                            if held >= 0.5 && dist < 15 {
                                viewModel.showControlCenter = true
                                dragStartTime = nil
                                dragStartLocation = nil
                            }
                        }
                    }
                    .onEnded { value in
                        guard interactionEnabled else { return }
                        system.releaseTouch()

                        // Detect tap: short duration + minimal movement
                        if let start = dragStartTime,
                           let startLoc = dragStartLocation {
                            let duration = Date().timeIntervalSince(start)
                            let dx = value.location.x - startLoc.x
                            let dy = value.location.y - startLoc.y
                            let dist = sqrt(dx * dx + dy * dy)
                            if duration < 0.3 && dist < 15 {
                                handleTap()
                            }
                        }

                        dragStartTime = nil
                        dragStartLocation = nil

                        // Return to idle from armed if not in another state
                        if stateMachine.currentState == .armed {
                            stateMachine.transition(to: .idle, at: CACurrentMediaTime(), envelope: .quick)
                            activeController = MotionControllerRegistry.controller(for: .idle)
                        }
                    }
            )
            .onAppear {
                system.shapeRadius = 35.0
                // Pre-render particle sprite
                spriteImage = createParticleSprite()
                // Warm shape cache
                let count = reduceMotion ? 50 : ParticlePhysics.particleCount
                ShapeLibrary.shared.warmCache(count: count, radius: system.shapeRadius)
                withAnimation(.easeOut(duration: 1.2).delay(1.6)) {
                    opacity = 1.0
                }
                // Seed reveal tracking so initial particles appear immediately
                countChangeTime = Date().timeIntervalSinceReferenceDate
                previousVisibleCount = 0
            }
            .onChange(of: visibleParticleCount) { oldCount, newCount in
                guard newCount > 0, newCount != oldCount else { return }
                previousVisibleCount = oldCount
                countChangeTime = Date().timeIntervalSinceReferenceDate
            }
            .onChange(of: viewModel.orbPhase) { oldPhase, phase in
                let (motionState, envelope) = ParticleStateMachine.motionState(for: phase, previous: oldPhase)
                let time = CACurrentMediaTime()
                stateMachine.transition(to: motionState, at: time, envelope: envelope)
                activeController = MotionControllerRegistry.controller(for: motionState)
                stateEntryTime = time
                previousOrbPhase = oldPhase

                // Trigger shape morphs
                switch phase {
                case .listening:
                    system.transitionToListening()
                case .transcribing:
                    system.transitionToTranscribing()
                case .sending:
                    system.transitionToSending()
                case .success:
                    system.transitionToSuccess()
                case .error:
                    system.transitionToError()
                case .idle:
                    system.transitionToSwirl()
                }
            }
    }

    // MARK: - Particle Canvas

    private var particleCanvas: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let target = targetGlow

            Canvas { context, size in
                os_signpost(.begin, log: pointsOfInterest, name: "OrbFrame")

                // Compute state progress for motion controllers
                let stateElapsed = time - stateEntryTime
                let stateProgress = Float(min(stateElapsed / 2.0, 1.0)) // ~2s state lifetime

                // Get modulation from active controller
                let dt = Float(min(max(time - (system.lastFrameTime ?? time), 0), 1.0 / 30.0))
                var modulation = activeController.modulate(time: Float(time), dt: dt, stateProgress: stateProgress)

                // Apply envelope scale from state machine
                let _ = stateMachine.update(at: time)
                let envScale = stateMachine.envelopeScale
                modulation.globalScale *= envScale

                // Reduce motion: fewer particles, no bobbing, near-instant morph
                let fullCount = reduceMotion ? min(50, system.particles.count) : system.particles.count
                let particleCount = visibleParticleCount > 0 ? min(visibleParticleCount, fullCount) : fullCount

                os_signpost(.begin, log: pointsOfInterest, name: "OrbUpdate")
                system.update(at: time, modulation: modulation)
                os_signpost(.end, log: pointsOfInterest, name: "OrbUpdate")

                // Smoothly ramp glowIntensity toward target (~0.5s ease)
                let speed: Float = 3.0
                let glowDt = Float(min(max(time - (system.lastFrameTime ?? time), 0), 1.0 / 30.0))
                glowIntensity += (target - glowIntensity) * min(speed * glowDt, 1.0)
                let glow = Double(glowIntensity)

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let bobY = reduceMotion ? 0.0 : (sin(elapsed * 0.6) * 2.0 + sin(elapsed * 1.1) * 1.0)
                let globalScale = CGFloat(modulation.globalScale)

                // Gradual glow multipliers
                let glowBoost = 1.0 + glow * 0.8
                let coreBoost = 1.0 + glow * 0.4

                os_signpost(.begin, log: pointsOfInterest, name: "OrbDraw")

                for idx in 0..<particleCount {
                    let particle = system.particles[idx]
                    let scaledX = CGFloat(particle.position.x) * globalScale
                    let scaledY = CGFloat(particle.position.y) * globalScale
                    let screenX = center.x + scaledX
                    let screenY = center.y + scaledY + bobY
                    let pos = CGPoint(x: screenX, y: screenY)

                    let alpha = Double(particle.brightness)
                    let revealAlpha: Double
                    if idx < previousVisibleCount {
                        // Already-visible particles: fully revealed
                        revealAlpha = 1.0
                    } else {
                        // Newly added particles: fade in from countChangeTime over 1.2s
                        revealAlpha = min(1.0, max(0.0, (time - countChangeTime) / 1.2))
                    }
                    let finalAlpha = alpha * revealAlpha

                    // Try sprite-based drawing first
                    if let sprite = spriteImage {
                        let spriteSize = CGFloat(particle.size) * CGFloat(5.0 + glow * 2.0) * 2.0
                        let spriteRect = CGRect(
                            x: pos.x - spriteSize / 2,
                            y: pos.y - spriteSize / 2,
                            width: spriteSize,
                            height: spriteSize
                        )
                        context.opacity = finalAlpha * glowBoost
                        context.draw(Image(decorative: sprite, scale: 1.0), in: spriteRect)
                        context.opacity = 1.0
                    } else {
                        // Fallback: original radialGradient draws
                        let glowRadius = CGFloat(particle.size) * CGFloat(5.0 + glow * 2.0)
                        let glowRect = CGRect(
                            x: pos.x - glowRadius,
                            y: pos.y - glowRadius,
                            width: glowRadius * 2,
                            height: glowRadius * 2
                        )
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .radialGradient(
                                Gradient(colors: [
                                    .white.opacity(finalAlpha * 0.18 * glowBoost),
                                    .white.opacity(finalAlpha * 0.04 * glowBoost),
                                    .clear
                                ]),
                                center: pos,
                                startRadius: 0,
                                endRadius: glowRadius
                            )
                        )

                        let coreRadius = CGFloat(particle.size) * CGFloat(1.0 + glow * 0.3)
                        let coreRect = CGRect(
                            x: pos.x - coreRadius,
                            y: pos.y - coreRadius,
                            width: coreRadius * 2,
                            height: coreRadius * 2
                        )
                        context.fill(
                            Path(ellipseIn: coreRect),
                            with: .radialGradient(
                                Gradient(colors: [
                                    .white.opacity(min(finalAlpha * 0.95 * coreBoost, 1.0)),
                                    .white.opacity(finalAlpha * 0.3 * coreBoost),
                                    .clear
                                ]),
                                center: pos,
                                startRadius: 0,
                                endRadius: coreRadius
                            )
                        )
                    }
                }

                os_signpost(.end, log: pointsOfInterest, name: "OrbDraw")
                os_signpost(.end, log: pointsOfInterest, name: "OrbFrame")
            }
            .allowsHitTesting(false)
        }
        .colorEffect(
            ShaderLibrary.particleGlow(
                .float(Float(Date.now.timeIntervalSinceReferenceDate))
            )
        )
    }

    // MARK: - Sprite Pre-rendering

    /// Creates a pre-rendered CGImage of the particle glow pattern for faster per-particle drawing.
    private func createParticleSprite() -> CGImage? {
        let spriteSize = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: spriteSize,
            height: spriteSize,
            bitsPerComponent: 8,
            bytesPerRow: spriteSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let center = CGPoint(x: CGFloat(spriteSize) / 2, y: CGFloat(spriteSize) / 2)
        let radius = CGFloat(spriteSize) / 2

        // Outer glow
        let glowColors: [CGFloat] = [
            1, 1, 1, 0.18,
            1, 1, 1, 0.04,
            1, 1, 1, 0.0
        ]
        if let gradient = CGGradient(colorSpace: colorSpace, colorComponents: glowColors, locations: [0, 0.5, 1.0], count: 3) {
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }

        // Bright core
        let coreRadius = radius * 0.3
        let coreColors: [CGFloat] = [
            1, 1, 1, 0.95,
            1, 1, 1, 0.3,
            1, 1, 1, 0.0
        ]
        if let coreGradient = CGGradient(colorSpace: colorSpace, colorComponents: coreColors, locations: [0, 0.5, 1.0], count: 3) {
            ctx.drawRadialGradient(coreGradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: coreRadius, options: [])
        }

        return ctx.makeImage()
    }

    // MARK: - Actions

    private func handleTap() {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()

        if viewModel.isRecording {
            viewModel.stopRecordingAndSend()
        } else {
            viewModel.startRecording()
        }
    }
}
