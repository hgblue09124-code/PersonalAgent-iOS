import Foundation

public protocol KernelClock: Sendable {
    func now() async -> Date
}

public struct SystemKernelClock: KernelClock {
    public init() {}
    public func now() async -> Date { Date() }
}

/// Monotonic clock for deterministic tests. Isolated so it stays Sendable.
public actor ControllableKernelClock: KernelClock {
    private var current: Date

    public init(start: Date = Date(timeIntervalSince1970: 0)) {
        self.current = start
    }

    public func now() -> Date { current }

    public func advance(_ interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
    }
}
