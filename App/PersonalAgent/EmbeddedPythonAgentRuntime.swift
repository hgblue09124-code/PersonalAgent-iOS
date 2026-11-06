import Foundation

enum EmbeddedPythonAgentRuntimeError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case invalidUTF8Result

    var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            return "Python Agent Runtime unavailable: \(message)"
        case .invalidUTF8Result:
            return "Python Agent Runtime returned a non-UTF8 plan."
        }
    }
}

/// Serializes calls into the single embedded CPython interpreter.
/// Python emits a versioned proposal only; Composition validates and dispatches it.
actor EmbeddedPythonAgentRuntime {
    static let shared = EmbeddedPythonAgentRuntime()

    func planRequest(text: String, allowedSkillIDs: Set<String>) throws -> Data {
        var bridgeError: NSError?
        let payload = PAPythonRuntimeBridge.planRequest(
            withText: text,
            allowedSkillIDs: allowedSkillIDs.sorted(),
            error: &bridgeError
        )
        guard let payload else {
            throw EmbeddedPythonAgentRuntimeError.unavailable(
                bridgeError?.localizedDescription ?? "No planner response was produced."
            )
        }
        guard let data = payload.data(using: .utf8) else {
            throw EmbeddedPythonAgentRuntimeError.invalidUTF8Result
        }
        return data
    }
}
