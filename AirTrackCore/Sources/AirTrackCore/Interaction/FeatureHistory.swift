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
///
/// Motion is measured robustly (PHASE 3A scroll fix): each step is the mean displacement of
/// the knuckles visible in BOTH frames, divided by the median hand scale of the window. A
/// knuckle or the wrist dropping out of a frame (typical near the bottom edge while moving
/// down) therefore never shows up as movement, and a one-frame scale jump never rescales the
/// motion. A step faster than `maximumPlausibleSpeed` is a detection glitch, not a hand: it is
/// recorded as "unknown" (no motion), never as a jump.
public struct FeatureHistory: Sendable {
    public struct Sample: Equatable, Sendable {
        public var time: TimeInterval
        /// Knuckles in user space, image heights (aspect-corrected, mirrored if needed).
        public var knuckles: [HandJoint: Point2D]
        public var scale: Double
        public var pose: HandPose
        /// Motion since the previous sample (hand scales, user space); nil when unknown.
        public var step: MotionVector?
        /// Time since the previous sample.
        public var stepDuration: TimeInterval
    }

    public static let defaultWindow: TimeInterval = 0.5
    /// Hand scales per second. Faster than any real hand motion over one frame.
    public static let maximumPlausibleSpeed: Double = 20
    /// Knuckles two frames must share for their motion to be trusted.
    public static let minimumCommonKnuckles = 2

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
        var knuckles: [HandJoint: Point2D] = [:]
        for (joint, p) in features.knuckles where p.isFinite {
            knuckles[joint] = Point2D(x: (mirrored ? 1 - p.x : p.x) * aspect, y: p.y)
        }
        let time = features.timestamp
        guard time.isFinite, features.scale.isFinite, features.scale > 0, !knuckles.isEmpty else {
            clear()
            return
        }
        if let last = samples.last, time <= last.time { clear() }

        var step: MotionVector?
        var duration: TimeInterval = 0
        if let previous = samples.last {
            duration = time - previous.time
            let common = knuckles.keys.filter { previous.knuckles[$0] != nil }
            if common.count >= Self.minimumCommonKnuckles, duration > 0 {
                var sum = Point2D.zero
                for joint in common { sum = sum + (knuckles[joint]! - previous.knuckles[joint]!) }
                let mean = sum * (1 / Double(common.count))
                let scale = medianScale(including: features.scale)
                let motion = MotionVector(dx: mean.x / scale, dy: mean.y / scale)
                if motion.isFinite, motion.magnitude / duration <= Self.maximumPlausibleSpeed {
                    step = motion
                }
            }
        }
        samples.append(Sample(time: time, knuckles: knuckles, scale: features.scale, pose: pose, step: step, stepDuration: duration))
        trim(before: time - window)
    }

    public mutating func clear() { samples.removeAll() }

    /// Net motion of the samples after `since` (inside the window), hand-scale units. Unknown
    /// steps count as no motion. Zero with fewer than two samples.
    public func displacement(since: TimeInterval) -> MotionVector {
        let recent = samples.elements.filter { $0.time >= since }
        guard recent.count >= 2 else { return .zero }
        var dx = 0.0
        var dy = 0.0
        for sample in recent.dropFirst() {
            if let step = sample.step {
                dx += step.dx
                dy += step.dy
            }
        }
        return MotionVector(dx: dx, dy: dy)
    }

    /// Motion between the last two samples and the time between them; nil when unknown.
    public func lastStep() -> (motion: MotionVector, dt: TimeInterval)? {
        guard let last = samples.last, let step = last.step, last.stepDuration > 0 else { return nil }
        return (step, last.stepDuration)
    }

    /// Average velocity (hand scales per second) over the last `duration` seconds.
    public func velocity(over duration: TimeInterval = 0.1) -> MotionVector {
        guard let last = samples.last else { return .zero }
        let recent = samples.elements.filter { $0.time >= last.time - duration }
        guard let first = recent.first, recent.count >= 2, last.time > first.time else { return .zero }
        let d = displacement(since: first.time)
        let dt = last.time - first.time
        return MotionVector(dx: d.dx / dt, dy: d.dy / dt)
    }

    /// Median hand scale of the recent samples (nil when empty).
    public var referenceScale: Double? {
        let scales = samples.elements.map(\.scale).sorted()
        return scales.isEmpty ? nil : scales[scales.count / 2]
    }

    /// Median hand scale of the window plus a new value: robust to one-frame scale jumps.
    private func medianScale(including scale: Double) -> Double {
        let scales = (samples.elements.map(\.scale) + [scale]).sorted()
        return scales[scales.count / 2]
    }

    private mutating func trim(before cutoff: TimeInterval) {
        let kept = samples.elements.filter { $0.time >= cutoff }
        guard kept.count != samples.count else { return }
        samples.removeAll()
        for sample in kept { samples.append(sample) }
    }
}
