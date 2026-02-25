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

    // Morphing
    private var morphStartTime: Double = 0
    private var morphSourcePositions: [SIMD2<Float>] = []
    private var morphTargetPositions: [SIMD2<Float>] = []

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

    func update(at time: Double) {
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = time
            return
        }

        let dt = Float(min(time - lastTime, 1.0 / 30.0))
        lastUpdateTime = time

        // Handle morphing progress
        if case .morphing(let shapeID) = state {
            let elapsed = time - morphStartTime
            let progress = Float(min(elapsed / ParticlePhysics.morphDuration, 1.0))

            if progress >= 1.0 {
                state = shapeID == .orbit ? .swirling : .displayingShape(shapeID)
            }

            for i in particles.indices {
                let src = morphSourcePositions.indices.contains(i) ? morphSourcePositions[i] : particles[i].position
                let dst = morphTargetPositions.indices.contains(i) ? morphTargetPositions[i] : swirlTarget(for: particles[i], time: time)
                // Quintic ease for ultra-smooth morph
                let x = progress
                let t = x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
                particles[i].targetPosition = src + (dst - src) * t
            }
        }

        // Physics update per particle
        for i in particles.indices {
            updateParticle(index: i, dt: dt, time: time)
        }
    }

    private func updateParticle(index i: Int, dt: Float, time: Double) {
        var p = particles[i]
        let t = Float(time)

        // Advance orbit angle
        p.orbitAngle += p.orbitSpeed * dt

        // Noise-driven wander for organic feel
        let nx = sin(t * ParticlePhysics.noiseSpeed + p.noiseOffsetX) * cos(t * 0.7 + p.phase)
        let ny = cos(t * ParticlePhysics.noiseSpeed * 0.8 + p.noiseOffsetY) * sin(t * 0.6 + p.phase * 1.3)
        let noise = SIMD2<Float>(nx, ny) * ParticlePhysics.noiseStrength

        // Compute target based on state
        switch state {
        case .swirling:
            p.targetPosition = swirlTarget(for: p, time: time) + noise

        case .morphing:
            break // Updated above

        case .displayingShape:
            if morphTargetPositions.indices.contains(i) {
                let base = morphTargetPositions[i]
                // Gentle breathing — expand/contract around shape
                let breathe: Float = 1.0 + sin(t * 2.0) * 0.05
                let breathedPos = base * breathe
                let osc = SIMD2<Float>(
                    sin(t * 0.8 + p.phase) * 1.5,
                    cos(t * 0.6 + p.phase * 1.2) * 1.5
                )
                p.targetPosition = breathedPos + osc + noise * 0.2
            }
        }

        // Soft spring force
        let displacement = p.targetPosition - p.position
        var force = displacement * ParticlePhysics.springStiffness - p.velocity * ParticlePhysics.springDamping

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

        // Brightness: gentle pulse
        let normalizedSpeed = min(speed / ParticlePhysics.maxVelocity, 1.0)
        let baseBrightness: Float = 0.5 + normalizedSpeed * 0.3
        let pulse = sin(t * 1.5 + p.phase) * 0.15
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
        let breathe = 1.0 + sin(t * 0.5 + particle.phase) * 0.12
        let r = particle.orbitRadius * breathe
        return SIMD2<Float>(
            cos(particle.orbitAngle) * r,
            sin(particle.orbitAngle) * r
        )
    }

    // MARK: - Nearest-Neighbor Assignment

    /// Greedy nearest-neighbor: each source picks its closest available target.
    /// Particles travel minimum distance — bottom stays bottom, top stays top.
    private func assignNearestNeighbor(
        sources: [SIMD2<Float>],
        targets: [SIMD2<Float>]
    ) -> [SIMD2<Float>] {
        let count = sources.count
        guard count > 0, !targets.isEmpty else { return sources }

        var result = [SIMD2<Float>](repeating: .zero, count: count)
        var usedTargets = [Bool](repeating: false, count: targets.count)

        // For each source, find the nearest unused target
        for si in 0..<count {
            var bestDist: Float = .greatestFiniteMagnitude
            var bestTi = -1
            for ti in 0..<targets.count where !usedTargets[ti] {
                let diff = sources[si] - targets[ti]
                let d = diff.x * diff.x + diff.y * diff.y
                if d < bestDist {
                    bestDist = d
                    bestTi = ti
                }
            }
            if bestTi >= 0 {
                result[si] = targets[bestTi]
                usedTargets[bestTi] = true
            } else {
                result[si] = sources[si]
            }
        }

        return result
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

        let rawTargets = ShapeRegistry.targets(
            for: shapeID,
            count: particles.count,
            radius: shapeRadius
        )

        morphSourcePositions = particles.map(\.position)
        morphTargetPositions = assignNearestNeighbor(
            sources: morphSourcePositions,
            targets: rawTargets
        )

        morphStartTime = t
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

        // For swirl, each particle returns to its own orbit — index-based
        morphSourcePositions = particles.map(\.position)
        morphTargetPositions = particles.map { swirlTarget(for: $0, time: t) }

        morphStartTime = t
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
        touchInfluence = min(touchInfluence + 0.15, 1.0)
    }

    func releaseTouch() {
        touchInfluence = 0
        touchPoint = nil
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
