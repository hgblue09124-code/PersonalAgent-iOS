import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AgentOSSoftUpdateManifest: Codable, Sendable, Equatable {
    public let repository: String
    public let baseRevision: String
    public let version: String
    public let revision: String
    public let compatibility: String
    public let files: [File]

    public struct File: Codable, Sendable, Equatable {
        public let path: String
        public let sha256: String
        public let byteCount: Int64
        public let baseSHA256: String?
        public init(path: String, sha256: String, byteCount: Int64, baseSHA256: String? = nil) {
            self.path = path
            self.sha256 = sha256
            self.byteCount = byteCount
            self.baseSHA256 = baseSHA256
        }
    }

    public init(repository: String, baseRevision: String, version: String, revision: String,
                compatibility: String, files: [File]) {
        self.repository = repository
        self.baseRevision = baseRevision
        self.version = version
        self.revision = revision
        self.compatibility = compatibility
        self.files = files
    }
}

public enum AgentOSSoftUpdateError: Error, Sendable, Equatable, LocalizedError {
    case invalidManifest
    case alreadyCurrent
    case incompatibleRepository
    case staleRevision
    case unsafePath(String)
    case duplicatePath(String)
    case sizeLimit
    case hashMismatch(String)
    case localConflict(String)
    case invalidRemoteResponse

    public var errorDescription: String? {
        switch self {
        case .invalidManifest: return "The AgentOS update manifest is invalid."
        case .alreadyCurrent: return "AgentOS is already at this revision."
        case .incompatibleRepository: return "The update belongs to another repository."
        case .staleRevision: return "The update base revision is stale."
        case .unsafePath(let path): return "Unsafe update path: \(path)"
        case .duplicatePath(let path): return "Duplicate update path: \(path)"
        case .sizeLimit: return "The update exceeds the configured size limit."
        case .hashMismatch(let path): return "Integrity verification failed for \(path)."
        case .localConflict(let path): return "Local edits conflict with update file \(path)."
        case .invalidRemoteResponse: return "GitHub returned an incomplete or invalid update response."
        }
    }
}

/// Read-only transport: it never pushes commits or mutates the active workspace.
/// It downloads only bounded AgentOS text definitions into an isolated staging folder.
public actor AgentOSSoftUpdateClient {
    public static let manifestPath = "agentos-update.json"
    public static let maximumFiles = 256
    public static let maximumFileBytes: Int64 = 2 * 1024 * 1024
    public static let maximumTotalBytes: Int64 = 20 * 1024 * 1024

    private struct RefResponse: Decodable { let object: ObjectRef }
    private struct ObjectRef: Decodable { let sha: String }
    private struct CommitResponse: Decodable { let tree: ObjectRef }
    private struct TreeResponse: Decodable { let truncated: Bool; let tree: [TreeEntry] }
    private struct TreeEntry: Decodable { let path: String; let type: String; let sha: String; let size: Int64? }
    private struct BlobResponse: Decodable { let sha: String; let encoding: String; let content: String }

    private let location: GitHubRepositoryLocation
    private let apiBaseURL: URL
    private let transport: any GitHubSyncHTTPTransport
    private let tokenProvider: GitHubRepositorySyncClient.TokenProvider

    public init(location: GitHubRepositoryLocation,
                apiBaseURL: URL = URL(string: "https://api.github.com")!,
                transport: any GitHubSyncHTTPTransport = URLSessionGitHubSyncTransport(),
                tokenProvider: @escaping GitHubRepositorySyncClient.TokenProvider) throws {
        guard apiBaseURL.scheme?.lowercased() == "https", apiBaseURL.host != nil else {
            throw AgentOSSoftUpdateError.invalidRemoteResponse
        }
        self.location = location
        self.apiBaseURL = apiBaseURL
        self.transport = transport
        self.tokenProvider = tokenProvider
    }

    /// Fetches and verifies all declared files without touching the active workspace.
    /// The returned directory is owned by the caller and may be inspected before activation.
    public func stageUpdate(currentRevision: String, runtimeCompatibility: String,
                            workspaceURL: URL, stagingRootURL: URL,
                            locallyModifiedPaths: Set<String> = []) async throws -> (manifest: AgentOSSoftUpdateManifest, stagingURL: URL) {
        guard let token = try await tokenProvider(), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubRepositorySyncError.authenticationRequired
        }
        let remoteRef: RefResponse = try await get("repos/\(location.owner)/\(location.repository)/git/ref/heads/\(location.branch)", token: token)
        let commit: CommitResponse = try await get("repos/\(location.owner)/\(location.repository)/git/commits/\(remoteRef.object.sha)", token: token)
        let tree: TreeResponse = try await get("repos/\(location.owner)/\(location.repository)/git/trees/\(commit.tree.sha)?recursive=1", token: token)
        guard !tree.truncated else { throw AgentOSSoftUpdateError.invalidRemoteResponse }
        var entries: [String: TreeEntry] = [:]
        for entry in tree.tree where entry.type == "blob" {
            guard entries[entry.path] == nil else { throw AgentOSSoftUpdateError.invalidRemoteResponse }
            entries[entry.path] = entry
        }
        guard let manifestEntry = entries[Self.manifestPath] else { throw AgentOSSoftUpdateError.invalidManifest }
        let manifestData = try await fetchBlob(manifestEntry.sha, token: token, expectedSize: manifestEntry.size, path: Self.manifestPath)
        let manifest: AgentOSSoftUpdateManifest
        do { manifest = try JSONDecoder().decode(AgentOSSoftUpdateManifest.self, from: manifestData) }
        catch { throw AgentOSSoftUpdateError.invalidManifest }

        let repositoryKey = "\(location.owner)/\(location.repository)"
        guard manifest.repository.caseInsensitiveCompare(repositoryKey) == .orderedSame else {
            throw AgentOSSoftUpdateError.incompatibleRepository
        }
        if manifest.revision == currentRevision { throw AgentOSSoftUpdateError.alreadyCurrent }
        guard manifest.baseRevision == currentRevision else { throw AgentOSSoftUpdateError.staleRevision }
        guard !manifest.version.isEmpty, !manifest.revision.isEmpty,
              manifest.compatibility == runtimeCompatibility,
              manifest.files.count <= Self.maximumFiles else { throw AgentOSSoftUpdateError.invalidManifest }

        var paths = Set<String>()
        var total: Int64 = 0
        for file in manifest.files {
            guard Self.isAllowedPath(file.path) else { throw AgentOSSoftUpdateError.unsafePath(file.path) }
            guard paths.insert(file.path.lowercased()).inserted else { throw AgentOSSoftUpdateError.duplicatePath(file.path) }
            guard file.byteCount >= 0, file.byteCount <= Self.maximumFileBytes,
                  file.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                throw AgentOSSoftUpdateError.invalidManifest
            }
            total += file.byteCount
            guard total <= Self.maximumTotalBytes else { throw AgentOSSoftUpdateError.sizeLimit }
            if locallyModifiedPaths.contains(file.path) { throw AgentOSSoftUpdateError.localConflict(file.path) }
            guard let baseHash = file.baseSHA256,
                  baseHash == "missing" || baseHash.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { throw AgentOSSoftUpdateError.invalidManifest }
            let currentURL = workspaceURL.appendingPathComponent(file.path).standardizedFileURL
            guard currentURL.path.hasPrefix(workspaceURL.standardizedFileURL.path + "/") else {
                throw AgentOSSoftUpdateError.unsafePath(file.path)
            }
            if FileManager.default.fileExists(atPath: currentURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: currentURL.path)
                guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                    throw AgentOSSoftUpdateError.unsafePath(file.path)
                }
                let currentData = try Data(contentsOf: currentURL)
                guard SHA256Portable.hex(currentData).caseInsensitiveCompare(baseHash) == .orderedSame else {
                    throw AgentOSSoftUpdateError.localConflict(file.path)
                }
            } else if baseHash != "missing" {
                throw AgentOSSoftUpdateError.localConflict(file.path)
            }
        }

        let stagingURL = stagingRootURL.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        do {
            for file in manifest.files {
                guard let entry = entries[file.path] else { throw AgentOSSoftUpdateError.invalidManifest }
                let data = try await fetchBlob(entry.sha, token: token, expectedSize: entry.size, path: file.path)
                guard Int64(data.count) == file.byteCount,
                      SHA256Portable.hex(data).caseInsensitiveCompare(file.sha256) == .orderedSame else {
                    throw AgentOSSoftUpdateError.hashMismatch(file.path)
                }
                guard let text = String(data: data, encoding: .utf8), !data.contains(0),
                      !WorkspaceContentSafety.containsPotentialSecret(text) else {
                    throw AgentOSSoftUpdateError.invalidManifest
                }
                let destination = stagingURL.appendingPathComponent(file.path).standardizedFileURL
                guard destination.path.hasPrefix(stagingURL.standardizedFileURL.path + "/") else {
                    throw AgentOSSoftUpdateError.unsafePath(file.path)
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
            return (manifest, stagingURL)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    public static func sha256Hex(_ data: Data) -> String { SHA256Portable.hex(data) }

    public static func isAllowedPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let root = parts.first,
              [".agent", "agents", "skills", "modules", "tools", "config", "workspace"].contains(String(root)) else { return false }
        return ["md", "json", "txt"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private func fetchBlob(_ sha: String, token: String, expectedSize: Int64?, path: String) async throws -> Data {
        let blob: BlobResponse = try await get("repos/\(location.owner)/\(location.repository)/git/blobs/\(sha)", token: token)
        guard blob.sha == sha, blob.encoding == "base64" else { throw AgentOSSoftUpdateError.invalidRemoteResponse }
        guard let data = Data(base64Encoded: blob.content.filter { !$0.isWhitespace }),
              GitBlobSHA1.hash(data) == sha,
              Int64(data.count) <= Self.maximumFileBytes,
              expectedSize == nil || expectedSize == Int64(data.count) else {
            throw AgentOSSoftUpdateError.hashMismatch(path)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: apiBaseURL)?.absoluteURL else {
            throw AgentOSSoftUpdateError.invalidRemoteResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubRepositorySyncError.httpStatus(response.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: response.data) }
        catch { throw AgentOSSoftUpdateError.invalidRemoteResponse }
    }
}

/// Small portable SHA-256 implementation so update verification also works in Linux CI.
private enum SHA256Portable {
    private static let k: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    ]
    static func hex(_ data: Data) -> String {
        var bytes = Array(data)
        let bits = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        var h: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var w = Array(repeating: UInt32(0), count: 64)
            for i in 0..<16 {
                let j = offset + i * 4
                w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j+1]) << 16 | UInt32(bytes[j+2]) << 8 | UInt32(bytes[j+3])
            }
            for i in 16..<64 {
                let x = w[i-15], y = w[i-2]
                let s0 = rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3)
                let s1 = rotate(y, 17) ^ rotate(y, 19) ^ (y >> 10)
                w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
            }
            var a=h[0], b=h[1], c=h[2], d=h[3], e=h[4], f=h[5], g=h[6], z=h[7]
            for i in 0..<64 {
                let s1 = rotate(e,6) ^ rotate(e,11) ^ rotate(e,25)
                let ch = (e & f) ^ ((~e) & g)
                let t1 = z &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotate(a,2) ^ rotate(a,13) ^ rotate(a,22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                z=g; g=f; f=e; e=d &+ t1; d=c; c=b; b=a; a=t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= z
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
    private static func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}
