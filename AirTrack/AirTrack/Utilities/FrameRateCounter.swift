import Foundation

/// Events per second over a sliding 1-second window.
struct FrameRateCounter {
    private var times: [TimeInterval] = []

    mutating func tick(at now: TimeInterval) -> Double {
        times.append(now)
        let cutoff = now - 1
        if let firstKept = times.firstIndex(where: { $0 > cutoff }), firstKept > 0 {
            times.removeFirst(firstKept)
        }
        guard times.count > 1, let first = times.first, now > first else { return 0 }
        return Double(times.count - 1) / (now - first)
    }

    mutating func reset() {
        times.removeAll()
    }
}
