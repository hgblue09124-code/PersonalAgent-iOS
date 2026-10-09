import Foundation

public enum DurableWorkspaceSnapshotError: Error, Sendable, Equatable {
    case invalidWorkspace
    case invalidSnapshotIdentifier
    case snapshotNotFound
    case corruptManifest
    case unsupportedFileType(String)
    case verificationFailed(String)
    case ioFailure(String)
}

public struct DurableWorkspaceSnapshot: Codable, Sendable, Equatable, Identifiable {
    public struct Entry: Codable, Sendable, Equatable {
        public let relativePath: String
        public let isDirectory: Bool
        public let byteCount: Int64
        public let sha256: String?

        public init(relativePath: String, isDirectory: Bool, byteCount: Int64, sha256: String? = nil) {
            self.relativePath = relativePath
            self.isDirectory = isDirectory
            self.byteCount = byteCount
            self.sha256 = sha256
        }
    }

    public let id: String
    public let createdAt: Date
    public let entries: [Entry]

    public init(id: String, createdAt: Date, entries: [Entry]) {
        self.id = id
        self.createdAt = createdAt
        self.entries = entries
    }
}

/// Durable, app-owned filesystem snapshots for an AgentOS workspace.
///
/// Snapshots are stored outside the workspace tree. Symlinks and special files are
/// rejected rather than followed, and restore verifies the manifest's file sizes
/// before replacing the active workspace. The manifest is atomically persisted.
public actor DurableWorkspaceSnapshotStore {
    private let directoryURL: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL.standardizedFileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func listSnapshots() throws -> [DurableWorkspaceSnapshot] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var snapshots: [DurableWorkspaceSnapshot] = []
        for url in urls where url.lastPathComponent.range(
            of: "^[0-9a-fA-F-]{36}$",
            options: .regularExpression
        ) != nil {
            let manifestURL = url.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let snapshot = try decoder.decode(
                    DurableWorkspaceSnapshot.self,
                    from: Data(contentsOf: manifestURL)
                )
                guard snapshot.id == url.lastPathComponent else {
                    throw DurableWorkspaceSnapshotError.corruptManifest
                }
                snapshots.append(snapshot)
            } catch {
                throw DurableWorkspaceSnapshotError.corruptManifest
            }
        }
        return snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func createSnapshot(of workspaceURL: URL) throws -> DurableWorkspaceSnapshot {
        let workspace = workspaceURL.standardizedFileURL
        guard isDirectory(workspace),
              !contains(directoryURL, child: workspace),
              !contains(workspace, child: directoryURL),
              workspace.path != directoryURL.path else {
            throw DurableWorkspaceSnapshotError.invalidWorkspace
        }

        let id = UUID().uuidString.lowercased()
        let snapshotRoot = directoryURL.appendingPathComponent(id, isDirectory: true)
        let dataRoot = snapshotRoot.appendingPathComponent("data", isDirectory: true)
        do {
            try fileManager.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            var entries: [DurableWorkspaceSnapshot.Entry] = []
            try copyTree(from: workspace, to: dataRoot, relativePath: "", entries: &entries)
            let snapshot = DurableWorkspaceSnapshot(id: id, createdAt: Date(), entries: entries.sorted { $0.relativePath < $1.relativePath })
            let manifest = try encoder.encode(snapshot)
            try manifest.write(to: snapshotRoot.appendingPathComponent("manifest.json"), options: .atomic)
            return snapshot
        } catch let error as DurableWorkspaceSnapshotError {
            try? fileManager.removeItem(at: snapshotRoot)
            throw error
        } catch {
            try? fileManager.removeItem(at: snapshotRoot)
            throw DurableWorkspaceSnapshotError.ioFailure(error.localizedDescription)
        }
    }

    public func restore(snapshotID: String, to workspaceURL: URL) throws {
        guard snapshotID.range(of: "^[0-9a-fA-F-]{36}$", options: .regularExpression) != nil else {
            throw DurableWorkspaceSnapshotError.invalidSnapshotIdentifier
        }
        let workspace = workspaceURL.standardizedFileURL
        let snapshotRoot = directoryURL.appendingPathComponent(snapshotID, isDirectory: true)
        let manifestURL = snapshotRoot.appendingPathComponent("manifest.json")
        let dataRoot = snapshotRoot.appendingPathComponent("data", isDirectory: true)
        guard fileManager.fileExists(atPath: manifestURL.path),
              fileManager.fileExists(atPath: dataRoot.path) else {
            throw DurableWorkspaceSnapshotError.snapshotNotFound
        }
        guard !contains(directoryURL, child: workspace),
              !contains(workspace, child: directoryURL),
              workspace.path != directoryURL.path,
              fileManager.fileExists(atPath: workspace.deletingLastPathComponent().path) else {
            throw DurableWorkspaceSnapshotError.invalidWorkspace
        }

        let snapshot: DurableWorkspaceSnapshot
        do {
            snapshot = try decoder.decode(DurableWorkspaceSnapshot.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw DurableWorkspaceSnapshotError.corruptManifest
        }
        guard snapshot.id == snapshotID else {
            throw DurableWorkspaceSnapshotError.corruptManifest
        }
        try verify(snapshot: snapshot, dataRoot: dataRoot)

        let parent = workspace.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".\(workspace.lastPathComponent).restore-\(UUID().uuidString)")
        let backup = parent.appendingPathComponent(".\(workspace.lastPathComponent).backup-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)
            var ignored: [DurableWorkspaceSnapshot.Entry] = []
            try copyTree(from: dataRoot, to: stage, relativePath: "", entries: &ignored)
            let hadWorkspace = fileManager.fileExists(atPath: workspace.path)
            if hadWorkspace {
                try fileManager.moveItem(at: workspace, to: backup)
            }
            do {
                try fileManager.moveItem(at: stage, to: workspace)
            } catch {
                if hadWorkspace, fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: workspace)
                }
                throw error
            }
            if hadWorkspace {
                try? fileManager.removeItem(at: backup)
            }
        } catch let error as DurableWorkspaceSnapshotError {
            try? fileManager.removeItem(at: stage)
            throw error
        } catch {
            try? fileManager.removeItem(at: stage)
            throw DurableWorkspaceSnapshotError.ioFailure(error.localizedDescription)
        }
    }

    public func removeSnapshot(id: String) throws {
        guard id.range(of: "^[0-9a-fA-F-]{36}$", options: .regularExpression) != nil else {
            throw DurableWorkspaceSnapshotError.invalidSnapshotIdentifier
        }
        let url = directoryURL.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: url.path) else {
            throw DurableWorkspaceSnapshotError.snapshotNotFound
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw DurableWorkspaceSnapshotError.ioFailure(error.localizedDescription)
        }
    }

    private func verify(snapshot: DurableWorkspaceSnapshot, dataRoot: URL) throws {
        var seen = Set<String>()
        for entry in snapshot.entries {
            let path = entry.relativePath
            guard !path.isEmpty,
                  !path.hasPrefix("/"),
                  !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  seen.insert(path).inserted else {
                throw DurableWorkspaceSnapshotError.corruptManifest
            }
            let url = dataRoot.appendingPathComponent(path).standardizedFileURL
            guard contains(dataRoot, child: url) else {
                throw DurableWorkspaceSnapshotError.corruptManifest
            }
            let attrs: [FileAttributeKey: Any]
            do {
                attrs = try fileManager.attributesOfItem(atPath: url.path)
            } catch {
                throw DurableWorkspaceSnapshotError.verificationFailed(path)
            }
            let type = attrs[.type] as? FileAttributeType
            if entry.isDirectory {
                guard type == .typeDirectory else {
                    throw DurableWorkspaceSnapshotError.verificationFailed(path)
                }
            } else {
                guard type == .typeRegular,
                      (attrs[.size] as? NSNumber)?.int64Value == entry.byteCount,
                      let expectedDigest = entry.sha256,
                      try Self.sha256(of: url) == expectedDigest else {
                    throw DurableWorkspaceSnapshotError.verificationFailed(path)
                }
            }
        }
    }

    private func copyTree(
        from source: URL,
        to destination: URL,
        relativePath: String,
        entries: inout [DurableWorkspaceSnapshot.Entry]
    ) throws {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try fileManager.attributesOfItem(atPath: source.path)
        } catch {
            throw DurableWorkspaceSnapshotError.ioFailure(error.localizedDescription)
        }
        guard let type = attrs[.type] as? FileAttributeType else {
            throw DurableWorkspaceSnapshotError.unsupportedFileType(relativePath)
        }
        if type == .typeSymbolicLink {
            throw DurableWorkspaceSnapshotError.unsupportedFileType(relativePath)
        }
        if type == .typeDirectory {
            if !relativePath.isEmpty {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                entries.append(.init(relativePath: relativePath, isDirectory: true, byteCount: 0))
            }
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
            } catch {
                throw DurableWorkspaceSnapshotError.ioFailure(error.localizedDescription)
            }
            for child in children {
                let name = child.lastPathComponent
                guard name != ".", name != "..", !name.contains("/") else {
                    throw DurableWorkspaceSnapshotError.unsupportedFileType(relativePath)
                }
                let childRelative = relativePath.isEmpty ? name : relativePath + "/" + name
                try copyTree(
                    from: child,
                    to: destination.appendingPathComponent(name),
                    relativePath: childRelative,
                    entries: &entries
                )
            }
        } else if type == .typeRegular {
            let parent = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                throw DurableWorkspaceSnapshotError.ioFailure(error.localizedDescription)
            }
            entries.append(.init(
                relativePath: relativePath,
                isDirectory: false,
                byteCount: (attrs[.size] as? NSNumber)?.int64Value ?? 0,
                sha256: try Self.sha256(of: destination)
            ))
        } else {
            throw DurableWorkspaceSnapshotError.unsupportedFileType(relativePath)
        }
    }

    private static func sha256(of url: URL) throws -> String {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = WorkspaceSHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hasher.update(chunk)
            }
            return hasher.finalize()
        } catch {
            throw DurableWorkspaceSnapshotError.ioFailure(error.localizedDescription)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        ((try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType) == .typeDirectory
    }

    private func contains(_ root: URL, child: URL) -> Bool {
        child.path == root.path || child.path.hasPrefix(root.path + "/")
    }
}

/// Small streaming SHA-256 implementation to keep workspace snapshot verification
/// portable across the Linux M3 runner and Apple platforms without extra dependencies.
struct WorkspaceSHA256 {
    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]
    private var pending: [UInt8] = []
    private var byteCount: UInt64 = 0

    private static let constants: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    ]

    mutating func update(_ data: Data) {
        byteCount &+= UInt64(data.count)
        pending.append(contentsOf: data)
        var offset = 0
        while pending.count - offset >= 64 {
            compress(Array(pending[offset..<(offset + 64)]))
            offset += 64
        }
        if offset > 0 { pending.removeFirst(offset) }
    }

    mutating func finalize() -> String {
        let bitCount = byteCount &* 8
        pending.append(0x80)
        while pending.count % 64 != 56 { pending.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            pending.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
        }
        var offset = 0
        while offset < pending.count {
            compress(Array(pending[offset..<(offset + 64)]))
            offset += 64
        }
        return state.map { String(format: "%08x", $0) }.joined()
    }

    static func digest(_ data: Data) -> String {
        var hasher = WorkspaceSHA256()
        hasher.update(data)
        return hasher.finalize()
    }

    private mutating func compress(_ block: [UInt8]) {
        var words = Array(repeating: UInt32(0), count: 64)
        for index in 0..<16 {
            let start = index * 4
            words[index] = (UInt32(block[start]) << 24)
                | (UInt32(block[start + 1]) << 16)
                | (UInt32(block[start + 2]) << 8)
                | UInt32(block[start + 3])
        }
        for index in 16..<64 {
            let x = words[index - 15]
            let y = words[index - 2]
            let s0 = rotateRight(x, 7) ^ rotateRight(x, 18) ^ (x >> 3)
            let s1 = rotateRight(y, 17) ^ rotateRight(y, 19) ^ (y >> 10)
            words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
        }

        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for index in 0..<64 {
            let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
            let choose = (e & f) ^ ((~e) & g)
            let t1 = h &+ s1 &+ choose &+ Self.constants[index] &+ words[index]
            let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ majority
            h = g; g = f; f = e; e = d &+ t1
            d = c; c = b; b = a; a = t1 &+ t2
        }
        state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
    }

    private func rotateRight(_ value: UInt32, _ amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

