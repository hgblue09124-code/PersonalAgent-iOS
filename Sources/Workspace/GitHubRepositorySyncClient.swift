import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubRepositoryLocation: Sendable, Equatable {
    public let owner: String
    public let repository: String
    public let branch: String

    public init(owner: String, repository: String, branch: String = "main") throws {
        let segmentPattern = #"^[A-Za-z0-9_.-]+$"#
        guard owner.range(of: segmentPattern, options: .regularExpression) != nil,
              repository.range(of: segmentPattern, options: .regularExpression) != nil,
              !owner.contains(".."), !repository.contains(".."),
              GitHubRepositorySyncClient.isSafeBranch(branch) else {
            throw GitHubRepositorySyncError.invalidRepository
        }
        self.owner = owner
        self.repository = repository
        self.branch = branch
    }
}

public enum GitHubRepositorySyncError: Error, Sendable, Equatable {
    case invalidRepository
    case authenticationRequired
    case invalidResponse
    case httpStatus(Int)
    case remoteConflict
    case unsafePath(String)
    case unsupportedFile(String)
    case fileTooLarge(String)
    case hashMismatch(String)
    case corruptState
}

public struct GitHubSyncHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol GitHubSyncHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitHubSyncHTTPResponse
}

public final class URLSessionGitHubSyncTransport: GitHubSyncHTTPTransport, @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> GitHubSyncHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubRepositorySyncError.invalidResponse
        }
        return GitHubSyncHTTPResponse(statusCode: http.statusCode, data: data)
    }
}

public struct GitHubRepositorySyncResult: Sendable, Equatable {
    public let commitSHA: String
    public let uploadedPaths: [String]
    public let downloadedPaths: [String]
    public let deletedPaths: [String]
    public let unchanged: Bool
}

private struct GitHubSyncState: Codable {
    var commitSHA: String
    var files: [String: String]
}

private struct GitHubObjectReference: Decodable { let sha: String }
private struct GitHubRefResponse: Decodable { let object: GitHubObjectReference }
private struct GitHubCommitResponse: Decodable { let tree: GitHubObjectReference }
private struct GitHubTreeResponse: Decodable {
    let sha: String
    let truncated: Bool
    let tree: [GitHubTreeEntry]
}
private struct GitHubTreeEntry: Decodable {
    let path: String
    let mode: String
    let type: String
    let sha: String
    let size: Int64?
}
private struct GitHubBlobResponse: Decodable {
    let sha: String
    let encoding: String
    let content: String
}
private struct GitHubSHAResponse: Decodable { let sha: String }

private struct GitHubLocalFile {
    let url: URL
    let data: Data
    let sha: String
    let mode: String
}

/// Three-way, path-level sync against the GitHub Git Database API.
/// The last successful file-hash baseline is persisted outside the workspace.
/// Conflicting edits fail closed; branch updates are non-forced and parented to the
/// exact remote commit that was fetched. Credentials are injected and never persisted.
public actor GitHubRepositorySyncClient {
    public typealias TokenProvider = @Sendable () async throws -> String?

    public static let maximumFileBytes: Int64 = 10 * 1024 * 1024
    private let location: GitHubRepositoryLocation
    private let stateURL: URL
    private let apiBaseURL: URL
    private let transport: any GitHubSyncHTTPTransport
    private let tokenProvider: TokenProvider

    public init(
        location: GitHubRepositoryLocation,
        stateURL: URL,
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        transport: any GitHubSyncHTTPTransport = URLSessionGitHubSyncTransport(),
        tokenProvider: @escaping TokenProvider
    ) throws {
        guard apiBaseURL.scheme?.lowercased() == "https",
              apiBaseURL.host != nil else {
            throw GitHubRepositorySyncError.invalidRepository
        }
        self.location = location
        self.stateURL = stateURL.standardizedFileURL
        self.apiBaseURL = apiBaseURL
        self.transport = transport
        self.tokenProvider = tokenProvider
    }

    public func synchronize(workspaceURL: URL, commitMessage: String = "Sync AgentOS workspace") async throws -> GitHubRepositorySyncResult {
        let workspace = workspaceURL.standardizedFileURL
        guard workspace.path != stateURL.path,
              !Self.contains(workspace, child: stateURL),
              !Self.contains(stateURL, child: workspace),
              Self.isDirectory(workspace) else {
            throw GitHubRepositorySyncError.unsafePath(workspace.path)
        }
        guard let token = try await tokenProvider(), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubRepositorySyncError.authenticationRequired
        }

        let localFiles = try Self.scanLocalFiles(workspace)
        let oldState = try loadState()
        let refPath = "repos/\(location.owner)/\(location.repository)/git/ref/heads/\(location.branch)"
        let ref: GitHubRefResponse = try await get(refPath, token: token)
        let remoteCommitSHA = ref.object.sha
        let commit: GitHubCommitResponse = try await get("repos/\(location.owner)/\(location.repository)/git/commits/\(remoteCommitSHA)", token: token)
        let tree: GitHubTreeResponse = try await get("repos/\(location.owner)/\(location.repository)/git/trees/\(commit.tree.sha)?recursive=1", token: token)
        guard !tree.truncated else { throw GitHubRepositorySyncError.invalidResponse }

        var remoteFiles: [String: GitHubTreeEntry] = [:]
        for entry in tree.tree {
            guard Self.isSyncablePath(entry.path) else { continue }
            guard Self.isSafePath(entry.path) else {
                throw GitHubRepositorySyncError.unsafePath(entry.path)
            }
            guard entry.type == "blob", entry.mode == "100644" || entry.mode == "100755" else {
                throw GitHubRepositorySyncError.unsupportedFile(entry.path)
            }
            if let size = entry.size, size > Self.maximumFileBytes {
                throw GitHubRepositorySyncError.fileTooLarge(entry.path)
            }
            remoteFiles[entry.path] = entry
        }

        let allPaths = Set(localFiles.keys).union(remoteFiles.keys).union(oldState?.files.keys ?? Dictionary<String, String>().keys)
        var conflicts: [String] = []
        var localChanges: [String: GitHubLocalFile?] = [:]
        for path in allPaths.sorted() {
            let localSHA = localFiles[path]?.sha
            let remoteSHA = remoteFiles[path]?.sha
            let baseSHA = oldState?.files[path]
            let localChanged = localSHA != baseSHA
            let remoteChanged = remoteSHA != baseSHA
            if localChanged && remoteChanged && localSHA != remoteSHA {
                conflicts.append(path)
                continue
            }
            if localChanged && !remoteChanged {
                localChanges[path] = localFiles[path]
            }
        }
        guard conflicts.isEmpty else { throw GitHubRepositorySyncError.remoteConflict }

        var finalRemoteFiles = remoteFiles
        var treeChanges: [[String: Any]] = []
        var uploadedPaths: [String] = []
        var deletedPaths: [String] = []

        for path in localChanges.keys.sorted() {
            guard let maybeFile = localChanges[path] else { continue }
            if let file = maybeFile {
                let created: GitHubSHAResponse = try await post(
                    "repos/\(location.owner)/\(location.repository)/git/blobs",
                    token: token,
                    body: ["content": file.data.base64EncodedString(), "encoding": "base64"]
                )
                guard created.sha == file.sha else { throw GitHubRepositorySyncError.hashMismatch(path) }
                treeChanges.append(["path": path, "mode": file.mode, "type": "blob", "sha": created.sha])
                finalRemoteFiles[path] = GitHubTreeEntry(path: path, mode: file.mode, type: "blob", sha: created.sha, size: Int64(file.data.count))
                uploadedPaths.append(path)
            } else {
                treeChanges.append(["path": path, "mode": remoteFiles[path]?.mode ?? "100644", "type": "blob", "sha": NSNull()])
                finalRemoteFiles[path] = nil
                deletedPaths.append(path)
            }
        }

        var finalCommitSHA = remoteCommitSHA
        if !treeChanges.isEmpty {
            let newTree: GitHubSHAResponse = try await post(
                "repos/\(location.owner)/\(location.repository)/git/trees",
                token: token,
                body: ["base_tree": tree.sha, "tree": treeChanges]
            )
            let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { throw GitHubRepositorySyncError.invalidRepository }
            let newCommit: GitHubSHAResponse = try await post(
                "repos/\(location.owner)/\(location.repository)/git/commits",
                token: token,
                body: ["message": message, "tree": newTree.sha, "parents": [remoteCommitSHA]]
            )
            do {
                let _: GitHubRefResponse = try await patch(
                    "repos/\(location.owner)/\(location.repository)/git/refs/heads/\(location.branch)",
                    token: token,
                    body: ["sha": newCommit.sha, "force": false]
                )
            } catch GitHubRepositorySyncError.httpStatus(409) {
                throw GitHubRepositorySyncError.remoteConflict
            } catch GitHubRepositorySyncError.httpStatus(422) {
                throw GitHubRepositorySyncError.remoteConflict
            }
            finalCommitSHA = newCommit.sha
        }

        var downloadedPaths: [String] = []
        let allFinalPaths = Set(localFiles.keys).union(finalRemoteFiles.keys)
        for path in allFinalPaths.sorted() {
            let local = localFiles[path]
            let remote = finalRemoteFiles[path]
            if local?.sha == remote?.sha { continue }
            let destination = workspace.appendingPathComponent(path).standardizedFileURL
            guard Self.contains(workspace, child: destination) else {
                throw GitHubRepositorySyncError.unsafePath(path)
            }
            if let remote {
                let data = try await fetchBlob(remote.sha, path: path, token: token)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
                downloadedPaths.append(path)
            } else if local != nil {
                try FileManager.default.removeItem(at: destination)
                deletedPaths.append(path)
            }
        }

        let finalState = GitHubSyncState(
            commitSHA: finalCommitSHA,
            files: finalRemoteFiles.mapValues(\.sha)
        )
        try persistState(finalState)
        return GitHubRepositorySyncResult(
            commitSHA: finalCommitSHA,
            uploadedPaths: uploadedPaths.sorted(),
            downloadedPaths: downloadedPaths.sorted(),
            deletedPaths: Array(Set(deletedPaths)).sorted(),
            unchanged: treeChanges.isEmpty && downloadedPaths.isEmpty && deletedPaths.isEmpty
        )
    }

    public static func isSafeBranch(_ branch: String) -> Bool {
        !branch.isEmpty && !branch.hasPrefix("/") && !branch.contains("..")
            && branch.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil
            && !branch.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    public static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
            && !path.split(separator: "/").contains(where: { $0.lowercased() == ".git" })
    }

    private static func isSyncablePath(_ path: String) -> Bool {
        guard isSafePath(path) else { return false }
        let components = path.split(separator: "/").map(String.init)
        let blockedDirectories: Set<String> = [".git", ".build", "deriveddata", "node_modules", "pods", "cache", "logs", "memory", "models", "files"]
        if components.dropLast().contains(where: { blockedDirectories.contains($0.lowercased()) }) { return false }
        let name = components.last?.lowercased() ?? ""
        let blockedNames = [".env", ".env.local", "credentials.json", "secrets.json", "api_keys.json"]
        if blockedNames.contains(name) || name.contains("credential") || name.contains("secret") || name.contains("token") || name.contains("apikey") || name.hasSuffix(".gguf") || name.hasSuffix(".pem") || name.hasSuffix(".p12") || name.hasSuffix(".key") || name.hasSuffix(".mobileprovision") || name.hasSuffix(".sqlite") || name.hasSuffix(".db") {
            return false
        }
        return true
    }

    private static func scanLocalFiles(_ root: URL) throws -> [String: GitHubLocalFile] {
        var result: [String: GitHubLocalFile] = [:]
        func walk(_ directory: URL, relative: String) throws {
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
            for child in children {
                let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                guard isSafePath(path) else { throw GitHubRepositorySyncError.unsafePath(path) }
                if !isSyncablePath(path) { continue }
                let attributes: [FileAttributeKey: Any]
                do { attributes = try FileManager.default.attributesOfItem(atPath: child.path) }
                catch { throw GitHubRepositorySyncError.invalidResponse }
                guard let type = attributes[.type] as? FileAttributeType else { throw GitHubRepositorySyncError.unsupportedFile(path) }
                if type == .typeDirectory {
                    try walk(child, relative: path)
                } else if type == .typeSymbolicLink {
                    throw GitHubRepositorySyncError.unsafePath(path)
                } else if type == .typeRegular {
                    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                    guard size <= maximumFileBytes else { throw GitHubRepositorySyncError.fileTooLarge(path) }
                    let data = try Data(contentsOf: child, options: [.mappedIfSafe])
                    guard String(data: data, encoding: .utf8) != nil,
                          !data.contains(0) else { throw GitHubRepositorySyncError.unsupportedFile(path) }
                    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
                    result[path] = GitHubLocalFile(url: child, data: data, sha: GitBlobSHA1.hash(data), mode: permissions & 0o111 == 0 ? "100644" : "100755")
                } else {
                    throw GitHubRepositorySyncError.unsupportedFile(path)
                }
            }
        }
        try walk(root, relative: "")
        return result
    }

    private func loadState() throws -> GitHubSyncState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        do { return try JSONDecoder().decode(GitHubSyncState.self, from: Data(contentsOf: stateURL)) }
        catch { throw GitHubRepositorySyncError.corruptState }
    }

    private func persistState(_ state: GitHubSyncState) throws {
        let parent = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try encoder.encode(state).write(to: stateURL, options: .atomic) }
        catch { throw GitHubRepositorySyncError.corruptState }
    }

    private func fetchBlob(_ sha: String, path: String, token: String) async throws -> Data {
        let blob: GitHubBlobResponse = try await get("repos/\(location.owner)/\(location.repository)/git/blobs/\(sha)", token: token)
        guard blob.sha == sha, blob.encoding == "base64" else { throw GitHubRepositorySyncError.hashMismatch(path) }
        let encoded = blob.content.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: encoded), GitBlobSHA1.hash(data) == sha else {
            throw GitHubRepositorySyncError.hashMismatch(path)
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        try await send("GET", path: path, token: token, body: nil)
    }

    private func post<T: Decodable>(_ path: String, token: String, body: [String: Any]) async throws -> T {
        try await send("POST", path: path, token: token, body: body)
    }

    private func patch<T: Decodable>(_ path: String, token: String, body: [String: Any]) async throws -> T {
        try await send("PATCH", path: path, token: token, body: body)
    }

    private func send<T: Decodable>(_ method: String, path: String, token: String, body: [String: Any]?) async throws -> T {
        guard let url = URL(string: path, relativeTo: apiBaseURL)?.absoluteURL else {
            throw GitHubRepositorySyncError.invalidRepository
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubRepositorySyncError.httpStatus(response.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: response.data) }
        catch { throw GitHubRepositorySyncError.invalidResponse }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType) == .typeDirectory
    }

    private static func contains(_ root: URL, child: URL) -> Bool {
        child.path == root.path || child.path.hasPrefix(root.path + "/")
    }
}

private enum GitBlobSHA1 {
    static func hash(_ data: Data) -> String {
        var object = Data("blob \(data.count)\0".utf8)
        object.append(data)
        return SHA1.digest(object)
    }
}

private enum SHA1 {
    static func digest(_ data: Data) -> String {
        var bytes = Array(data)
        let bitCount = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
        }
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var w = Array(repeating: UInt32(0), count: 80)
            for i in 0..<16 {
                let j = offset + i * 4
                w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j + 1]) << 16 | UInt32(bytes[j + 2]) << 8 | UInt32(bytes[j + 3])
            }
            for i in 16..<80 { w[i] = rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1) }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20: f = (b & c) | ((~b) & d); k = 0x5A827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default: f = b ^ c ^ d; k = 0xCA62C1D6
                }
                let temp = rotate(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = rotate(b, 30); b = a; a = temp
            }
            h0 &+= a; h1 &+= b; h2 &+= c; h3 &+= d; h4 &+= e
        }
        return [h0, h1, h2, h3, h4].map { String(format: "%08x", $0) }.joined()
    }

    private static func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value << amount) | (value >> (32 - amount))
    }
}
