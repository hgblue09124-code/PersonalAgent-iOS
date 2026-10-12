import Foundation

public enum AgentUpdateKind: String, Codable, Sendable {
    case soft
    case hard
}

public struct AgentUpdateFile: Codable, Sendable, Equatable {
    public let path: String
    public let sha256: String
    public let byteCount: Int64

    public init(path: String, sha256: String, byteCount: Int64) {
        self.path = path
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct AgentUpdateManifest: Codable, Sendable, Equatable {
    public let repository: String?
    public let baseRevision: String?
    public let version: String
    public let revision: String
    public let kind: AgentUpdateKind
    public let compatibility: String
    public let checksum: String
    public let files: [AgentUpdateFile]

    public init(version: String, revision: String, kind: AgentUpdateKind, compatibility: String, checksum: String, repository: String? = nil, baseRevision: String? = nil, files: [AgentUpdateFile] = []) {
        self.version = version
        self.revision = revision
        self.kind = kind
        self.compatibility = compatibility
        self.checksum = checksum
        self.repository = repository
        self.baseRevision = baseRevision
        self.files = files
    }
}

public enum AgentUpdateState: Sendable, Equatable {
    case idle, downloaded, staged, validated, snapshotted, activated, rolledBack
}

public enum AgentUpdateError: Error, Equatable {
    case invalidManifest
    case incompatible
    case repositoryMismatch
    case baseRevisionMismatch
    case unsafePath(String)
    case unexpectedFile(String)
    case invalidFileMetadata(String)
    case updateTooLarge
    case localConflict(String)
    case checksumMismatch
    case invalidTransition
    case rollbackUnavailable
}

/// Fail-closed policy and transaction boundary. Network, hashing, and filesystem
/// snapshot I/O are injected responsibilities; downloaded content is never executed.
public actor AgentUpdateManager {
    public static let maximumFileCount = 256
    public static let maximumFileBytes: Int64 = 2 * 1024 * 1024
    public static let maximumTotalBytes: Int64 = 20 * 1024 * 1024
    private static let allowedRoots: Set<String> = [".agent", "agents", "skills", "modules", "tools", "config", "workspace", "memory"]
    private static let allowedExtensions: Set<String> = ["md", "json", "txt"]

    public private(set) var state: AgentUpdateState = .idle
    public private(set) var activeManifest: AgentUpdateManifest?
    private var snapshotAvailable = false

    public init() {}

    public static func decodeManifest(_ data: Data) throws -> AgentUpdateManifest {
        do {
            let manifest = try JSONDecoder().decode(AgentUpdateManifest.self, from: data)
            try validateManifestShape(manifest)
            return manifest
        } catch let error as AgentUpdateError {
            throw error
        } catch {
            throw AgentUpdateError.invalidManifest
        }
    }

    public static func isAllowedPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"), !path.contains(":") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let root = parts.first, allowedRoots.contains(String(root)) else { return false }
        return allowedExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private static func validateManifestShape(_ manifest: AgentUpdateManifest) throws {
        guard !manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.compatibility.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.checksum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.kind == .soft, manifest.revision.count <= 128, manifest.version.count <= 128,
              manifest.compatibility.count <= 128, manifest.checksum.count <= 256,
              manifest.files.count <= maximumFileCount else { throw AgentUpdateError.invalidManifest }
        if let repository = manifest.repository, repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AgentUpdateError.invalidManifest
        }
        if let base = manifest.baseRevision, base.count > 128 { throw AgentUpdateError.invalidManifest }

        var paths = Set<String>()
        var total: Int64 = 0
        for file in manifest.files {
            guard isAllowedPath(file.path) else { throw AgentUpdateError.unsafePath(file.path) }
            guard paths.insert(file.path).inserted, file.byteCount >= 0, file.byteCount <= maximumFileBytes,
                  file.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                throw AgentUpdateError.invalidFileMetadata(file.path)
            }
            total += file.byteCount
            guard total <= maximumTotalBytes else { throw AgentUpdateError.updateTooLarge }
        }
    }

    public func download(_ manifest: AgentUpdateManifest) throws {
        guard state == .idle || state == .rolledBack else { throw AgentUpdateError.invalidTransition }
        try Self.validateManifestShape(manifest)
        activeManifest = manifest
        snapshotAvailable = false
        state = .downloaded
    }

    public func stage() throws {
        guard state == .downloaded else { throw AgentUpdateError.invalidTransition }
        state = .staged
    }

    /// Caller supplies hashes and the exact staged file set after downloading into staging.
    public func validate(runtimeCompatibility: String, actualChecksum: String, repository: String? = nil,
                         currentRevision: String? = nil, actualFiles: Set<String>? = nil,
                         locallyModifiedPaths: Set<String> = []) throws {
        guard state == .staged, let manifest = activeManifest else { throw AgentUpdateError.invalidTransition }
        if let expected = manifest.repository, expected != repository { throw AgentUpdateError.repositoryMismatch }
        if let base = manifest.baseRevision, base != currentRevision { throw AgentUpdateError.baseRevisionMismatch }
        guard manifest.compatibility == runtimeCompatibility else { throw AgentUpdateError.incompatible }
        guard manifest.checksum.caseInsensitiveCompare(actualChecksum) == .orderedSame else { throw AgentUpdateError.checksumMismatch }
        let declared = Set(manifest.files.map(\.path))
        if let actualFiles, actualFiles != declared {
            let path = actualFiles.subtracting(declared).sorted().first ?? declared.subtracting(actualFiles).sorted().first ?? "unknown"
            throw AgentUpdateError.unexpectedFile(path)
        }
        if let conflict = locallyModifiedPaths.intersection(declared).sorted().first {
            throw AgentUpdateError.localConflict(conflict)
        }
        state = .validated
    }

    public func snapshot() throws {
        guard state == .validated else { throw AgentUpdateError.invalidTransition }
        snapshotAvailable = true
        state = .snapshotted
    }

    public func activate() throws {
        guard state == .snapshotted else { throw AgentUpdateError.invalidTransition }
        state = .activated
    }

    public func rollback() throws {
        guard snapshotAvailable, state == .activated else { throw AgentUpdateError.rollbackUnavailable }
        state = .rolledBack
    }
}
