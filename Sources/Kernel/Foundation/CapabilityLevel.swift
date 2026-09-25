
/// Permission / capability classes every action must declare.
public struct CapabilityLevel: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let read = CapabilityLevel(rawValue: 1 << 0)
    public static let write = CapabilityLevel(rawValue: 1 << 1)
    public static let execute = CapabilityLevel(rawValue: 1 << 2)
    public static let network = CapabilityLevel(rawValue: 1 << 3)
    public static let destructive = CapabilityLevel(rawValue: 1 << 4)

    public var requiresExplicitApproval: Bool {
        contains(.destructive) || contains(.execute) && contains(.network)
    }
}
