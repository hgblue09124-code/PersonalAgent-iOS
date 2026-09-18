
import Foundation

public struct AgentID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct GoalID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct SkillID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ToolID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ModuleID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ProviderID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ModelID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct MemoryRecordID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct TraceID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct EventID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct ActionID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}

public struct PlanID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID().uuidString }
}
