import Foundation

/// Motion in the USER's point of view, in hand-scale units: +x = the user's right,
/// +y = down (screen convention). Mirroring is applied once, here, like CursorMapper does.
public struct MotionVector: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = MotionVector(dx: 0, dy: 0)
    public var magnitude: Double { (dx * dx + dy * dy).squareRoot() }
    public var isFinite: Bool { dx.isFinite && dy.isFinite }
}

public enum DominantAxis: String, Equatable, Sendable {
    /// Not enough movement to tell.
    case none
    case vertical
    case horizontal
    /// Diagonal: neither axis dominates. Never commits a directional gesture.
    case ambiguous

    /// `ratio`: how many times larger one component must be than the other.
    public static func of(_ motion: MotionVector, minimumMagnitude: Double, ratio: Double) -> DominantAxis {
        guard motion.isFinite, motion.magnitude >= minimumMagnitude else { return .none }
        let x = abs(motion.dx)
        let y = abs(motion.dy)
        if y >= x * ratio { return .vertical }
        if x >= y * ratio { return .horizontal }
        return .ambiguous
    }
}

/// Fixed-capacity FIFO. Appending when full drops the oldest element. No growth.
public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    private var start = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[start] = element
            start = (start + 1) % capacity
        }
    }

    /// Oldest → newest.
    public var elements: [Element] {
        guard start > 0 else { return storage }
        return Array(storage[start...] + storage[..<start])
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(start + storage.count - 1) % storage.count]
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        start = 0
    }
}

/// Bounded temporal record of the hand (≤ `window` seconds and ≤ `capacity` samples).
/// Everything derived from it is in hand-scale units and user space.
public struct FeatureHistory: Sendable {
    public struct Sample: Equatable, Sendable {
        public var time: TimeInterval
        /// Palm center in user space, image heights (aspect-corrected, mirrored if needed).
        public var palm: Point2D
        public var scale: Double
        public var pose: HandPose
    }

    public static let defaultWindow: TimeInterval = 0.5
    public let window: TimeInterval
    private var samples: RingBuffer<Sample>

    public init(window: TimeInterval = FeatureHistory.defaultWindow, capacity: Int = 32) {
        self.window = window
        self.samples = RingBuffer(capacity: capacity)
    }

    public var count: Int { samples.count }
    public var latest: Sample? { samples.last }
    public var all: [Sample] { samples.elements }

    /// Adds a frame. Out-of-order or non-finite data clears the history (never mixes timelines).
    public mutating func append(_ features: HandFeatures, pose: HandPose, mirrored: Bool) {
        let aspect = features.imageAspectRatio
        let x = mirrored ? (1 - features.palmCenter.x) : features.palmCenter.x
        let sample = Sample(time: features.timestamp, palm: Point2D(x: x * aspect, y: features.palmCenter.y), scale: features.scale, pose: pose)
        guard sample.time.isFinite, sample.palm.isFinite, sample.scale.isFinite, sample.scale > 0 else {
            clear()
            return
        }
        if let last = samples.last, sample.time <= last.time { clear() }
        samples.append(sample)
        trim(before: sample.time - window)
    }

    public mutating func clear() { samples.removeAll() }

    /// Net palm motion of the samples at or after `since` (and inside the window), in units of
    /// the latest hand scale. Zero with fewer than two samples.
    public func displacement(since: TimeInterval) -> MotionVector {
        let recent = samples.elements.filter { $0.time >= since }
        guard let first = recent.first, let last = recent.last, recent.count >= 2, last.scale > 0 else { return .zero }
        return MotionVector(dx: (last.palm.x - first.palm.x) / last.scale, dy: (last.palm.y - first.palm.y) / last.scale)
    }

    /// Motion between the last two samples and the time between them.
    public func lastStep() -> (motion: MotionVector, dt: TimeInterval)? {
        let all = samples.elements
        guard all.count >= 2 else { return nil }
        let a = all[all.count - 2]
        let b = all[all.count - 1]
        let dt = b.time - a.time
        guard dt > 0, b.scale > 0 else { return nil }
        return (MotionVector(dx: (b.palm.x - a.palm.x) / b.scale, dy: (b.palm.y - a.palm.y) / b.scale), dt)
    }

    /// Average velocity (hand scales per second) over the last `duration` seconds.
    public func velocity(over duration: TimeInterval = 0.1) -> MotionVector {
        guard let last = samples.last else { return .zero }
        let recent = samples.elements.filter { $0.time >= last.time - duration }
        guard let first = recent.first, recent.count >= 2, last.time > first.time, last.scale > 0 else { return .zero }
        let dt = last.time - first.time
        return MotionVector(dx: (last.palm.x - first.palm.x) / last.scale / dt, dy: (last.palm.y - first.palm.y) / last.scale / dt)
    }

    private mutating func trim(before cutoff: TimeInterval) {
        let kept = samples.elements.filter { $0.time >= cutoff }
        guard kept.count != samples.count else { return }
        samples.removeAll()
        for sample in kept { samples.append(sample) }
    }
}
