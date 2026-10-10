import Foundation

/// Shared fail-closed content policy for workspace surfaces and Agent tools.
public enum WorkspaceContentSafety {
    private static let blockedNames: Set<String> = [
        ".env", ".env.local", "credentials.json", "secrets.json", "api_keys.json",
        "id_rsa", "id_ed25519"
    ]
    private static let protectedMarkers = ["credential", "secret", "token", "apikey", "api_key", "api-key", "private_key", "private-key", "access_key", "access-key", "password"]
    private static let secretPatterns = [
        #"(?i)(?:api[_-]?key|access[_-]?(?:token|key)|refresh[_-]?token|client[_-]?secret|secret[_-]?key|signing[_-]?key|credential|password|private[_-]?key|authorization)[[:space:]]*[:=][[:space:]]*["']?[A-Za-z0-9/+=._-]{16,}"#,
        #"\b(?:sk-[A-Za-z0-9_-]{16,}|xai-[A-Za-z0-9_-]{16,}|or-v1-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|AIza[0-9A-Za-z_-]{35}|hf_[A-Za-z0-9]{30,}|npm_[A-Za-z0-9]{30,}|SK[0-9a-fA-F]{32})\b"#,
        #"\bAK(?:IA)[0-9A-Z]{16}\b"#,
        #"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)\bBearer[[:space:]]+[A-Za-z0-9._-]{16,}"#
    ]

    public static func isProtectedPath(_ path: String) -> Bool {
        // Normalize cross-platform separators before applying policy.
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.split(separator: "/").map { String($0).lowercased() }.contains { component in
            blockedNames.contains(component) || component.hasPrefix(".env.") || protectedMarkers.contains { component.contains($0) }
        }
    }

    public static func containsPotentialSecret(_ text: String) -> Bool {
        secretPatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}
