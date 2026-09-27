import Foundation

public protocol KernelClock: Sendable {
    func now() -> Date
}

public struct SystemKernelClock: KernelClock, Sendable {
    public init() {}
    public func now() -> Date { Date() }
}
