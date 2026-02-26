import Foundation
import simd

// MARK: - Shape Metadata

nonisolated struct ShapeMetadata: Sendable {
    let id: ShapeID
    let displayName: String
    let anchorY: Float
    let svgPathData: String?
}

// MARK: - Shape Library

/// Caching layer over ShapeRegistry. Avoids recomputing SVG sampling on every morph.
nonisolated final class ShapeLibrary: @unchecked Sendable {

    static let shared = ShapeLibrary()

    private var cache: [CacheKey: [SIMD2<Float>]] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Cache Key

    private struct CacheKey: Hashable {
        let shapeID: ShapeID
        let count: Int
        let radius: Float
    }

    // MARK: - Public API

    /// Returns cached target positions, computing and caching if needed.
    func targets(for shapeID: ShapeID, count: Int, radius: Float) -> [SIMD2<Float>] {
        let key = CacheKey(shapeID: shapeID, count: count, radius: radius)

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Compute outside the lock
        let result = ShapeRegistry.targets(for: shapeID, count: count, radius: radius)

        lock.lock()
        cache[key] = result
        lock.unlock()

        return result
    }

    /// Pre-compute all known shapes for a given particle count and radius.
    func warmCache(count: Int, radius: Float) {
        for shapeID in ShapeID.allCases {
            _ = targets(for: shapeID, count: count, radius: radius)
        }
    }

    /// Clear all cached data.
    func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
