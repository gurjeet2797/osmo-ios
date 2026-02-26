import Foundation
import simd

// MARK: - Morph Controller

/// Extracted morph logic with circular-shift assignment for stable particle transitions.
nonisolated final class MorphController: @unchecked Sendable {

    private(set) var isActive: Bool = false
    private(set) var targetPositions: [SIMD2<Float>]?

    private var sourcePositions: [SIMD2<Float>] = []
    private var assignedTargets: [SIMD2<Float>] = []
    private var startTime: Double = 0
    private var duration: Double = 0.35

    // MARK: - Public API

    /// Start a morph from current positions to new targets.
    /// Uses circular-shift assignment (best rotation) when counts match,
    /// falls back to greedy nearest-neighbor when they differ.
    func begin(from sources: [SIMD2<Float>], to targets: [SIMD2<Float>], at time: Double, duration: Double = 0.35) {
        self.sourcePositions = sources
        self.duration = duration
        self.startTime = time

        if sources.count == targets.count && !sources.isEmpty {
            self.assignedTargets = circularShiftAssign(sources: sources, targets: targets)
        } else {
            self.assignedTargets = greedyNearestNeighbor(sources: sources, targets: targets)
        }

        self.targetPositions = assignedTargets
        self.isActive = true
    }

    /// Advance the morph. Returns interpolated positions, or nil if morph is complete/inactive.
    func update(at time: Double) -> [SIMD2<Float>]? {
        guard isActive else { return nil }

        let elapsed = time - startTime
        let progress = Float(min(elapsed / duration, 1.0))

        if progress >= 1.0 {
            isActive = false
            return assignedTargets
        }

        // Quintic smoothstep
        let x = progress
        let t = x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

        let count = min(sourcePositions.count, assignedTargets.count)
        var result = [SIMD2<Float>](repeating: .zero, count: sourcePositions.count)

        for i in 0..<count {
            result[i] = sourcePositions[i] + (assignedTargets[i] - sourcePositions[i]) * t
        }
        // Any extra source particles beyond target count stay at source
        for i in count..<sourcePositions.count {
            result[i] = sourcePositions[i]
        }

        return result
    }

    /// Force-complete the morph immediately.
    func cancel() {
        isActive = false
    }

    /// Progress from 0 to 1 (or 1 if inactive).
    func progress(at time: Double) -> Float {
        guard isActive else { return 1.0 }
        return Float(min((time - startTime) / duration, 1.0))
    }

    // MARK: - Circular Shift Assignment

    /// Find the rotation offset that minimizes total squared distance.
    /// O(N^2) for N particles — 150 particles = 22,500 ops, negligible per-morph.
    private func circularShiftAssign(sources: [SIMD2<Float>], targets: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let n = sources.count
        guard n > 0 else { return [] }

        var bestOffset = 0
        var bestCost: Float = .greatestFiniteMagnitude

        for offset in 0..<n {
            var cost: Float = 0
            for i in 0..<n {
                let ti = (i + offset) % n
                let diff = sources[i] - targets[ti]
                cost += diff.x * diff.x + diff.y * diff.y
            }
            if cost < bestCost {
                bestCost = cost
                bestOffset = offset
            }
        }

        var result = [SIMD2<Float>](repeating: .zero, count: n)
        for i in 0..<n {
            result[i] = targets[(i + bestOffset) % n]
        }
        return result
    }

    // MARK: - Greedy Nearest Neighbor (fallback)

    private func greedyNearestNeighbor(sources: [SIMD2<Float>], targets: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let count = sources.count
        guard count > 0, !targets.isEmpty else { return sources }

        var result = [SIMD2<Float>](repeating: .zero, count: count)
        var used = [Bool](repeating: false, count: targets.count)

        for si in 0..<count {
            var bestDist: Float = .greatestFiniteMagnitude
            var bestTi = -1
            for ti in 0..<targets.count where !used[ti] {
                let diff = sources[si] - targets[ti]
                let d = diff.x * diff.x + diff.y * diff.y
                if d < bestDist {
                    bestDist = d
                    bestTi = ti
                }
            }
            if bestTi >= 0 {
                result[si] = targets[bestTi]
                used[bestTi] = true
            } else {
                result[si] = sources[si]
            }
        }

        return result
    }
}
