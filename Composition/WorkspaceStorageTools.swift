import Foundation
import PAKernel
import PAWorkspace
import PATools

/// Read-only, bounded AgentOS workspace operations exposed through ToolModule/ModuleRuntime.
/// Sensitive storage roots are intentionally unreachable from this tool.
public struct WorkspaceReadTool: Tool {
    private let workspace: any AgentWorkspace

    public init(workspace: any AgentWorkspace) {
        self.workspace = workspace
    }

    public var manifest: ToolManifest {
        ToolManifest(
            id: ToolID(rawValue: "workspace.read"),
            name: "Workspace Read/Search",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            requiredCapabilities: [.read],
            inputSchema: SchemaDocument(identifier: "tool.workspace.read.input"),
            outputSchema: SchemaDocument(identifier: "tool.workspace.read.output")
        )
    }

    public func run(argumentsJSON: String) async throws -> String {
        let input = try WorkspaceToolCodec.decode(argumentsJSON)
        let operation = try WorkspaceToolCodec.requiredString("operation", in: input)
        switch operation {
        case "list":
            try WorkspaceToolCodec.requireKeys(input, allowed: ["operation", "path"])
            let path = try WorkspaceToolCodec.optionalString("path", in: input) ?? "workspace"
            try WorkspaceToolSafety.validatePath(path)
            let entries = try await workspace.listDirectory(at: path)
                .filter { WorkspaceToolSafety.isAllowedPath($0.relativePath) && !WorkspaceToolSafety.isProtectedFilename($0.relativePath) }
                .prefix(200)
            return try WorkspaceToolCodec.encode([
                "operation": operation,
                "path": path,
                "entries": entries.map { ["path": $0.relativePath, "isDirectory": $0.isDirectory] },
                "truncated": entries.count == 200,
            ])
        case "read":
            try WorkspaceToolCodec.requireKeys(input, allowed: ["operation", "path"])
            let path = try WorkspaceToolCodec.requiredString("path", in: input)
            try WorkspaceToolSafety.validateReadablePath(path)
            let metadata = try await workspace.metadata(at: path)
            guard !metadata.isDirectory else { throw AgentWorkspaceError.notFile(path) }
            guard metadata.byteCount <= WorkspaceToolSafety.maximumFileBytes else {
                throw WorkspaceStorageToolError.fileTooLarge
            }
            let content = try await workspace.readFile(at: path)
            guard !WorkspaceToolSafety.containsPotentialSecret(content) else {
                throw WorkspaceStorageToolError.secretLikeContent
            }
            return try WorkspaceToolCodec.encode([
                "operation": operation,
                "path": path,
                "content": content,
                "bytes": content.utf8.count,
                "verified": true,
            ])
        case "search":
            try WorkspaceToolCodec.requireKeys(input, allowed: ["operation", "query"])
            let query = try WorkspaceToolCodec.requiredString("query", in: input)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, query.count <= 256 else {
                throw WorkspaceStorageToolError.invalidInput("query must contain 1–256 characters")
            }
            var pending: [(path: String, depth: Int)] = WorkspaceToolSafety.roots.map { ($0, 0) }
            var visited = 0
            var matches: [String] = []
            while !pending.isEmpty && visited < 500 && matches.count < 50 {
                let current = pending.removeFirst()
                guard WorkspaceToolSafety.isAllowedPath(current.path) else { continue }
                let children = try await workspace.listDirectory(at: current.path)
                for entry in children where WorkspaceToolSafety.isAllowedPath(entry.relativePath) {
                    visited += 1
                    if entry.isDirectory {
                        if current.depth < 5 { pending.append((entry.relativePath, current.depth + 1)) }
                    } else if WorkspaceToolSafety.isReadableTextPath(entry.relativePath)
                                && !WorkspaceToolSafety.isProtectedFilename(entry.relativePath) {
                        let metadata = try await workspace.metadata(at: entry.relativePath)
                        guard metadata.byteCount <= WorkspaceToolSafety.maximumFileBytes else { continue }
                        let text = try await workspace.readFile(at: entry.relativePath)
                        guard !WorkspaceToolSafety.containsPotentialSecret(text) else { continue }
                        if text.localizedCaseInsensitiveContains(query) {
                            matches.append(entry.relativePath)
                            if matches.count >= 50 { break }
                        }
                    }
                    if visited >= 500 { break }
                }
            }
            return try WorkspaceToolCodec.encode([
                "operation": operation,
                "query": query,
                "matches": matches,
                "visited": visited,
                "truncated": visited >= 500 || matches.count >= 50,
            ])
        default:
            throw WorkspaceStorageToolError.invalidInput("operation must be list, read, or search")
        }
    }
}

/// Mutating workspace operations are narrow, text-only, size-bounded and read-back verified.
/// Move/remove are intentionally not exposed until a destructive-action approval port is wired.
public struct WorkspaceWriteTool: Tool {
    private let workspace: any AgentWorkspace

    public init(workspace: any AgentWorkspace) {
        self.workspace = workspace
    }

    public var manifest: ToolManifest {
        ToolManifest(
            id: ToolID(rawValue: "workspace.write"),
            name: "Workspace Write",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            requiredCapabilities: [.write],
            inputSchema: SchemaDocument(identifier: "tool.workspace.write.input"),
            outputSchema: SchemaDocument(identifier: "tool.workspace.write.output")
        )
    }

    public func run(argumentsJSON: String) async throws -> String {
        let input = try WorkspaceToolCodec.decode(argumentsJSON)
        let operation = try WorkspaceToolCodec.requiredString("operation", in: input)
        let path = try WorkspaceToolCodec.requiredString("path", in: input)
        try WorkspaceToolSafety.validateWritablePath(path)

        switch operation {
        case "write", "append":
            try WorkspaceToolCodec.requireKeys(input, allowed: ["operation", "path", "content"])
            let content = try WorkspaceToolCodec.requiredString("content", in: input)
            guard content.utf8.count <= WorkspaceToolSafety.maximumFileBytes else {
                throw WorkspaceStorageToolError.fileTooLarge
            }
            guard !WorkspaceToolSafety.containsPotentialSecret(content) else {
                throw WorkspaceStorageToolError.secretLikeContent
            }

            let existed = try await workspace.exists(at: path)
            let previous: String?
            if existed {
                let metadata = try await workspace.metadata(at: path)
                guard !metadata.isDirectory else { throw AgentWorkspaceError.notFile(path) }
                guard metadata.byteCount <= WorkspaceToolSafety.maximumFileBytes else {
                    throw WorkspaceStorageToolError.fileTooLarge
                }
                previous = try await workspace.readFile(at: path)
            } else {
                previous = nil
            }

            let expected: String
            if operation == "append" {
                expected = (previous ?? "") + content
                guard expected.utf8.count <= WorkspaceToolSafety.maximumFileBytes else {
                    throw WorkspaceStorageToolError.fileTooLarge
                }
            } else {
                expected = content
            }
            guard !WorkspaceToolSafety.containsPotentialSecret(expected) else {
                throw WorkspaceStorageToolError.secretLikeContent
            }

            if operation == "append" {
                try await workspace.appendFile(content, to: path)
            } else {
                try await workspace.writeFile(content, to: path)
            }

            let persisted = try await workspace.readFile(at: path)
            guard persisted == expected else {
                if let previous {
                    try? await workspace.writeFile(previous, to: path)
                } else {
                    try? await workspace.remove(at: path)
                }
                throw WorkspaceStorageToolError.verificationFailed(path)
            }
            return try WorkspaceToolCodec.encode([
                "operation": operation,
                "path": path,
                "bytes": persisted.utf8.count,
                "verified": true,
            ])
        case "mkdir":
            try WorkspaceToolCodec.requireKeys(input, allowed: ["operation", "path"])
            try await workspace.createDirectory(at: path)
            let metadata = try await workspace.metadata(at: path)
            guard metadata.isDirectory else {
                throw WorkspaceStorageToolError.verificationFailed(path)
            }
            return try WorkspaceToolCodec.encode([
                "operation": operation,
                "path": path,
                "verified": true,
            ])
        default:
            throw WorkspaceStorageToolError.invalidInput("operation must be write, append, or mkdir")
        }
    }
}

private enum WorkspaceToolSafety {
    static let roots = ["agents", "skills", "modules", "tools", "workspace"]
    static let maximumFileBytes = 256 * 1024
    static let readableExtensions: Set<String> = ["md", "txt", "json", "yaml", "yml", "swift"]

    static func isAllowedPath(_ path: String) -> Bool {
        let normalized = path.lowercased()
        return roots.contains {
            normalized == $0 || normalized.hasPrefix($0 + "/")
        }
    }

    static func validatePath(_ path: String) throws {
        _ = try WorkspacePath(path)
        guard isAllowedPath(path) else { throw WorkspaceStorageToolError.forbiddenPath }
    }

    static func validateReadablePath(_ path: String) throws {
        try validatePath(path)
        guard isReadableTextPath(path) else {
            throw WorkspaceStorageToolError.unsupportedFile
        }
        try validateFilename(path)
    }

    static func validateWritablePath(_ path: String) throws {
        try validateReadablePath(path)
    }

    static func isReadableTextPath(_ path: String) -> Bool {
        readableExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    static func isProtectedFilename(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let blocked = [".env", ".env.local", "credentials.json", "secrets.json", "api_keys.json", "id_rsa", "id_ed25519"]
        return blocked.contains(name)
            || ["credential", "secret", "token", "apikey"].contains { marker in name.contains(marker) }
    }

    static func validateFilename(_ path: String) throws {
        guard !isProtectedFilename(path) else {
            throw WorkspaceStorageToolError.forbiddenPath
        }
    }

    static func containsPotentialSecret(_ text: String) -> Bool {
        let patterns = [
            #"(?i)(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|private[_-]?key)[[:space:]]*[:=][[:space:]]*["']?[A-Za-z0-9/+=._-]{16,}"#,
            #"\b(?:sk-[A-Za-z0-9]{16,}|xai-[A-Za-z0-9-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#,
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            #"(?i)\bBearer[[:space:]]+[A-Za-z0-9._-]{16,}"#,
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

private enum WorkspaceToolCodec {
    static func decode(_ source: String) throws -> [String: Any] {
        guard let data = source.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkspaceStorageToolError.invalidInput("arguments must be a JSON object")
        }
        return object
    }

    static func requiredString(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = object[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceStorageToolError.invalidInput("missing string field: \(key)")
        }
        return value
    }

    static func optionalString(_ key: String, in object: [String: Any]) throws -> String? {
        guard let value = object[key] else { return nil }
        guard let string = value as? String else {
            throw WorkspaceStorageToolError.invalidInput("field must be a string: \(key)")
        }
        return string
    }

    static func requireKeys(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else {
            throw WorkspaceStorageToolError.invalidInput("unexpected input fields")
        }
    }

    static func encode(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw WorkspaceStorageToolError.invalidInput("result is not valid JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let value = String(data: data, encoding: .utf8) else {
            throw WorkspaceStorageToolError.invalidInput("could not encode result")
        }
        return value
    }
}

private enum WorkspaceStorageToolError: Error, LocalizedError {
    case invalidInput(String)
    case forbiddenPath
    case unsupportedFile
    case fileTooLarge
    case secretLikeContent
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let reason): return "Workspace tool input rejected: \(reason)"
        case .forbiddenPath: return "Workspace tool path is outside the allowed roots or targets a protected filename."
        case .unsupportedFile: return "Workspace tools accept only supported text/Markdown files."
        case .fileTooLarge: return "Workspace tool file exceeds the 256 KiB limit."
        case .secretLikeContent: return "Workspace tool rejected secret-like content."
        case .verificationFailed(let path): return "Workspace write verification failed for \(path)."
        }
    }
}
