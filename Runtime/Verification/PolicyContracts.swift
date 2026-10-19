import Foundation
import PAKernel

/// Default runtime policy is deliberately least-privilege.
/// Sensitive capabilities require an explicitly configured policy.
public struct DefaultPolicyEvaluator: PolicyEvaluating {
    public init() {}

    public func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        if intent.capabilities.isEmpty || intent.capabilities == .read {
            return .allow("Read-only action")
        }
        return .deny("Explicit capability grant required")
    }
}


/// Applies the user's explicit Agent capability toggles to runtime actions.
/// Read/write/execute/network are opt-in according to Settings; destructive
/// operations are never silently granted and always require the approval gate.
public struct SettingsBackedPolicyEvaluator: PolicyEvaluating {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func evaluate(_ intent: ActionIntent) async -> PolicyDecision {
        if intent.capabilities.contains(.read),
           !enabled("permissions.capability.read", defaultValue: true) {
            return .deny("Read capability is disabled in Settings")
        }
        if intent.capabilities.contains(.write),
           !enabled("permissions.capability.write", defaultValue: false) {
            return .deny("Write capability is disabled in Settings")
        }
        if intent.capabilities.contains(.execute),
           !enabled("permissions.capability.execute", defaultValue: false) {
            return .deny("Skill execution is disabled in Settings")
        }
        if intent.capabilities.contains(.network),
           !enabled("permissions.capability.network", defaultValue: false) {
            return .deny("Network capability is disabled in Settings")
        }
        if intent.capabilities.contains(.destructive) {
            return .approve("Destructive actions require explicit approval")
        }
        return .allow("Allowed by Agent capability settings")
    }

    private func enabled(_ key: String, defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
