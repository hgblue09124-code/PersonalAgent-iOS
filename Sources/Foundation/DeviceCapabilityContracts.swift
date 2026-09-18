import Foundation

/// Thermal state of the underlying execution device.
public enum DeviceThermalState: String, Sendable, Codable, Equatable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical
}

/// Memory pressure state of the execution device.
public enum DeviceMemoryPressure: String, Sendable, Codable, Equatable, CaseIterable {
    case normal
    case warning
    case critical
}

/// Network connectivity status of the execution device.
public enum DeviceNetworkStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case unavailable
    case wifi
    case cellular
    case ethernet
}

/// Foreground / background application lifecycle state.
public enum DeviceApplicationState: String, Sendable, Codable, Equatable, CaseIterable {
    case active
    case inactive
    case background
}

/// Point-in-time snapshot of device operational capability signals.
public struct DeviceStateSnapshot: Sendable, Codable, Equatable {
    public let thermalState: DeviceThermalState
    public let memoryPressure: DeviceMemoryPressure
    public let networkStatus: DeviceNetworkStatus
    public let applicationState: DeviceApplicationState
    public let availableStorageBytes: Int64
    public let timestamp: Date

    public init(
        thermalState: DeviceThermalState = .nominal,
        memoryPressure: DeviceMemoryPressure = .normal,
        networkStatus: DeviceNetworkStatus = .wifi,
        applicationState: DeviceApplicationState = .active,
        availableStorageBytes: Int64 = 10_000_000_000,
        timestamp: Date = Date()
    ) {
        self.thermalState = thermalState
        self.memoryPressure = memoryPressure
        self.networkStatus = networkStatus
        self.applicationState = applicationState
        self.availableStorageBytes = availableStorageBytes
        self.timestamp = timestamp
    }
}

/// Contract for observing and querying device environment signals without importing UIKit or SwiftUI.
public protocol DeviceCapabilityProviding: Sendable {
    var thermalState: DeviceThermalState { get async }
    var memoryPressure: DeviceMemoryPressure { get async }
    var networkStatus: DeviceNetworkStatus { get async }
    var applicationState: DeviceApplicationState { get async }
    var availableStorageBytes: Int64 { get async }
    func snapshot() async -> DeviceStateSnapshot
}

/// Default pure-Swift, framework-independent device capability provider for runtime testing and headless execution.
public final class DefaultDeviceCapabilityProvider: DeviceCapabilityProviding, @unchecked Sendable {
    private var currentSnapshot: DeviceStateSnapshot

    public init(initialSnapshot: DeviceStateSnapshot = DeviceStateSnapshot()) {
        self.currentSnapshot = initialSnapshot
    }

    public var thermalState: DeviceThermalState {
        get async { currentSnapshot.thermalState }
    }

    public var memoryPressure: DeviceMemoryPressure {
        get async { currentSnapshot.memoryPressure }
    }

    public var networkStatus: DeviceNetworkStatus {
        get async { currentSnapshot.networkStatus }
    }

    public var applicationState: DeviceApplicationState {
        get async { currentSnapshot.applicationState }
    }

    public var availableStorageBytes: Int64 {
        get async { currentSnapshot.availableStorageBytes }
    }

    public func snapshot() async -> DeviceStateSnapshot {
        currentSnapshot
    }

    public func updateSnapshot(_ newSnapshot: DeviceStateSnapshot) {
        self.currentSnapshot = newSnapshot
    }
}
