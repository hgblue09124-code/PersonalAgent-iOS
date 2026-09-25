import Foundation

public enum DeviceThermalState: String, Sendable, Codable, Equatable, CaseIterable {
    case nominal, fair, serious, critical
}
public enum DeviceMemoryPressure: String, Sendable, Codable, Equatable, CaseIterable {
    case normal, warning, critical
}
public enum DeviceNetworkStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case unavailable, wifi, cellular, ethernet
}
public enum DeviceApplicationState: String, Sendable, Codable, Equatable, CaseIterable {
    case active, inactive, background
}
public struct DeviceStateSnapshot: Sendable, Codable, Equatable {
    public let thermalState: DeviceThermalState
    public let memoryPressure: DeviceMemoryPressure
    public let networkStatus: DeviceNetworkStatus
    public let applicationState: DeviceApplicationState
    public let availableStorageBytes: Int64
    public let timestamp: Date
    public init(thermalState: DeviceThermalState = .nominal, memoryPressure: DeviceMemoryPressure = .normal,
                networkStatus: DeviceNetworkStatus = .wifi, applicationState: DeviceApplicationState = .active,
                availableStorageBytes: Int64 = 10_000_000_000, timestamp: Date = Date()) {
        self.thermalState = thermalState; self.memoryPressure = memoryPressure
        self.networkStatus = networkStatus; self.applicationState = applicationState
        self.availableStorageBytes = availableStorageBytes; self.timestamp = timestamp
    }
}
public protocol DeviceCapabilityProviding: Sendable {
    var thermalState: DeviceThermalState { get async }
    var memoryPressure: DeviceMemoryPressure { get async }
    var networkStatus: DeviceNetworkStatus { get async }
    var applicationState: DeviceApplicationState { get async }
    var availableStorageBytes: Int64 { get async }
    func snapshot() async -> DeviceStateSnapshot
}
public final class DefaultDeviceCapabilityProvider: DeviceCapabilityProviding, @unchecked Sendable {
    private var currentSnapshot: DeviceStateSnapshot
    public init(initialSnapshot: DeviceStateSnapshot = DeviceStateSnapshot()) { self.currentSnapshot = initialSnapshot }
    public var thermalState: DeviceThermalState { get async { currentSnapshot.thermalState } }
    public var memoryPressure: DeviceMemoryPressure { get async { currentSnapshot.memoryPressure } }
    public var networkStatus: DeviceNetworkStatus { get async { currentSnapshot.networkStatus } }
    public var applicationState: DeviceApplicationState { get async { currentSnapshot.applicationState } }
    public var availableStorageBytes: Int64 { get async { currentSnapshot.availableStorageBytes } }
    public func snapshot() async -> DeviceStateSnapshot { currentSnapshot }
    public func updateSnapshot(_ newSnapshot: DeviceStateSnapshot) { currentSnapshot = newSnapshot }
}
