import Foundation
import simd

// MARK: - Particle Data

nonisolated struct Particle: Sendable {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var targetPosition: SIMD2<Float>
    var baseHue: Float
    var currentHue: Float
    var size: Float
    var brightness: Float
    var phase: Float
    var orbitRadius: Float
    var orbitAngle: Float
    var orbitSpeed: Float
    var noiseOffsetX: Float
    var noiseOffsetY: Float
}

// MARK: - State Machine

nonisolated enum OrbState: Equatable, Sendable {
    case swirling
    case morphing(to: ShapeID)
    case displayingShape(ShapeID)
}

enum ShapeID: String, CaseIterable, Sendable {
    case orbit
    case microphone
}

// MARK: - Physics Constants

nonisolated enum ParticlePhysics: Sendable {
    static let particleCount = 150
    static let orbRadius: Float = 28.0
    static let springStiffness: Float = 5.0
    static let springDamping: Float = 2.8
    static let orbitBaseSpeed: Float = 0.6
    static let touchRepulsionRadius: Float = 50.0
    static let touchRepulsionForce: Float = 800.0
    static let maxVelocity: Float = 120.0
    static let hueShiftRate: Float = 0.0
    static let morphDuration: Double = 0.35
    static let noiseStrength: Float = 6.0
    static let noiseSpeed: Float = 1.2
}

// MARK: - Particle System

nonisolated final class ParticleSystem: @unchecked Sendable {
    private(set) var particles: [Particle]
    private(set) var state: OrbState = .swirling

    // Touch
    private var touchPoint: SIMD2<Float>?
    private var touchInfluence: Float = 0
    private var touchActive: Bool = false

    // Morph controller (replaces inline morph logic)
    let morphController = MorphController()

    // Current modulation (stored for swirlTarget access to breathe params)
    private(set) var currentModulation: MotionModulation = .idle

    // Timing
    private var lastUpdateTime: Double?
    /// Exposed for external dt calculations (glow ramp)
    var lastFrameTime: Double? { lastUpdateTime }

    // Shape target radius
    var shapeRadius: Float = 30.0

    init() {
        particles = Self.generateParticles(count: ParticlePhysics.particleCount)
    }

    // MARK: - Update Loop

    func update(at time: Double, modulation: MotionModulation = .idle) {
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = time
            return
        }

        let rawDelta = time - lastTime
        let dt = Float(min(max(rawDelta, 0), 1.0 / 30.0))
        lastUpdateTime = time
        currentModulation = modulation

        // Smooth touch influence ramp (time-based instead of per-call flat increment)
        if touchActive {
            touchInfluence = min(touchInfluence + 3.0 * dt, 1.0)
        } else {
            touchInfluence = max(touchInfluence - 4.0 * dt, 0.0)
            if touchInfluence <= 0.001 {
                touchPoint = nil
            }
        }

        // Handle morphing via MorphController
        if case .morphing(let shapeID) = state {
            if let interpolated = morphController.update(at: time) {
                for i in particles.indices where i < interpolated.count {
                    particles[i].targetPosition = interpolated[i]
                }
                // Check if morph completed
                if !morphController.isActive {
                    state = shapeID == .orbit ? .swirling : .displayingShape(shapeID)
                }
            } else {
                // Morph controller no longer active — finalize
                state = shapeID == .orbit ? .swirling : .displayingShape(shapeID)
            }
        }

        // Physics update per particle
        for i in particles.indices {
            updateParticle(index: i, dt: dt, time: time, modulation: modulation)
        }
    }

    private func updateParticle(index i: Int, dt: Float, time: Double, modulation: MotionModulation) {
        var p = particles[i]
        let t = Float(time)

        // Advance orbit angle using modulation speed multiplier
        p.orbitAngle += p.orbitSpeed * modulation.orbitSpeedMultiplier * dt

        // Noise-driven wander with modulation multiplier
        let nx = sin(t * ParticlePhysics.noiseSpeed + p.noiseOffsetX) * cos(t * 0.7 + p.phase)
        let ny = cos(t * ParticlePhysics.noiseSpeed * 0.8 + p.noiseOffsetY) * sin(t * 0.6 + p.phase * 1.3)
        let noise = SIMD2<Float>(nx, ny) * ParticlePhysics.noiseStrength * modulation.noiseMultiplier

        // Compute target based on state
        switch state {
        case .swirling:
            p.targetPosition = swirlTarget(for: p, time: time) + noise

        case .morphing:
            break // Updated above via MorphController

        case .displayingShape:
            if let targets = morphController.targetPositions, targets.indices.contains(i) {
                let base = targets[i]
                // Gentle breathing using modulation params
                let breathe: Float = 1.0 + sin(t * modulation.breatheFrequency * 4.0) * modulation.breatheAmplitude * 0.4
                let breathedPos = base * breathe
                let osc = SIMD2<Float>(
                    sin(t * 0.8 + p.phase) * 1.5,
                    cos(t * 0.6 + p.phase * 1.2) * 1.5
                )
                p.targetPosition = breathedPos + osc + noise * 0.2
            }
        }

        // Soft spring force using modulation stiffness/damping
        let displacement = p.targetPosition - p.position
        var force = displacement * modulation.springStiffness - p.velocity * modulation.springDamping

        // Touch repulsion
        if let touch = touchPoint, touchInfluence > 0.01 {
            let toParticle = p.position - touch
            let dist = simd_length(toParticle)
            if dist < ParticlePhysics.touchRepulsionRadius && dist > 0.001 {
                let normalizedDist = dist / ParticlePhysics.touchRepulsionRadius
                let falloff = (1.0 - normalizedDist) * (1.0 - normalizedDist)
                let repulsion = simd_normalize(toParticle) * ParticlePhysics.touchRepulsionForce * falloff * touchInfluence
                force += repulsion
            }
        }

        // Integrate
        p.velocity += force * dt
        let speed = simd_length(p.velocity)
        if speed > ParticlePhysics.maxVelocity {
            p.velocity = simd_normalize(p.velocity) * ParticlePhysics.maxVelocity
        }
        p.position += p.velocity * dt

        // Brightness using modulation params
        let normalizedSpeed = min(speed / ParticlePhysics.maxVelocity, 1.0)
        let baseBrightness = modulation.brightnessBase + normalizedSpeed * 0.3
        let pulse = sin(t * 1.5 + p.phase) * modulation.brightnessPulseAmp
        p.brightness = baseBrightness + pulse

        // Shape-specific brightness modulation
        if case .displayingShape(.microphone) = state {
            p.brightness *= 0.8 + 0.2 * sin(t * 2.5 + p.phase)
        }

        p.currentHue = 0 // unused, white

        particles[i] = p
    }

    // MARK: - Swirl Target

    private func swirlTarget(for particle: Particle, time: Double) -> SIMD2<Float> {
        let t = Float(time)
        let breathe = 1.0 + sin(t * currentModulation.breatheFrequency + particle.phase) * currentModulation.breatheAmplitude
        let r = particle.orbitRadius * breathe
        return SIMD2<Float>(
            cos(particle.orbitAngle) * r,
            sin(particle.orbitAngle) * r
        )
    }

    // MARK: - State Transitions

    func morphToShape(_ shapeID: ShapeID, at time: Double? = nil) {
        // Skip if already displaying or morphing to this shape
        switch state {
        case .displayingShape(let current) where current == shapeID:
            return
        case .morphing(let target) where target == shapeID:
            return
        default:
            break
        }

        let t = time ?? (lastUpdateTime ?? 0)

        let rawTargets = ShapeLibrary.shared.targets(
            for: shapeID,
            count: particles.count,
            radius: shapeRadius
        )

        let sources = particles.map(\.position)
        morphController.begin(from: sources, to: rawTargets, at: t, duration: ParticlePhysics.morphDuration)
        state = .morphing(to: shapeID)
    }

    func transitionToSwirl(at time: Double? = nil) {
        // Skip if already swirling or morphing to orbit
        switch state {
        case .swirling:
            return
        case .morphing(let target) where target == .orbit:
            return
        default:
            break
        }

        let t = time ?? (lastUpdateTime ?? 0)

        let sources = particles.map(\.position)
        let targets = particles.map { swirlTarget(for: $0, time: t) }
        morphController.begin(from: sources, to: targets, at: t, duration: ParticlePhysics.morphDuration)
        state = .morphing(to: .orbit)
    }

    // Convenience transition methods for the voice flow

    func transitionToListening(at time: Double? = nil) {
        morphToShape(.microphone, at: time)
    }

    func transitionToTranscribing(at time: Double? = nil) {
        morphToShape(.microphone, at: time)
    }

    func transitionToSending(at time: Double? = nil) {
        transitionToSwirl(at: time)
    }

    func transitionToSuccess(at time: Double? = nil) {
        transitionToSwirl(at: time)
    }

    func transitionToError(at time: Double? = nil) {
        transitionToSwirl(at: time)
    }

    // MARK: - Touch

    func applyTouch(at point: SIMD2<Float>) {
        touchPoint = point
        touchActive = true
    }

    func releaseTouch() {
        touchActive = false
    }

    // MARK: - Generation

    private static func generateParticles(count: Int) -> [Particle] {
        (0..<count).map { _ in
            let angle = Float.random(in: 0...(Float.pi * 2))
            let ring = Float.random(in: 0...1)
            let radius: Float
            if ring < 0.5 {
                radius = Float.random(in: 12...22)
            } else if ring < 0.8 {
                radius = Float.random(in: 22...32)
            } else {
                radius = Float.random(in: 32...40)
            }

            let pos = SIMD2<Float>(cos(angle) * radius, sin(angle) * radius)

            return Particle(
                position: pos,
                velocity: .zero,
                targetPosition: pos,
                baseHue: 0,
                currentHue: 0,
                size: Float.random(in: 0.8...2.2),
                brightness: Float.random(in: 0.4...0.9),
                phase: Float.random(in: 0...(Float.pi * 2)),
                orbitRadius: radius,
                orbitAngle: angle,
                orbitSpeed: Float.random(in: 0.3...0.9) * (Bool.random() ? 1.0 : -1.0),
                noiseOffsetX: Float.random(in: 0...100),
                noiseOffsetY: Float.random(in: 0...100)
            )
        }
    }
}
