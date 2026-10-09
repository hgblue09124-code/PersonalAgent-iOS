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

        public init(relativePath: String, isDirectory: Bool, byteCount: Int64) {
            self.relativePath = relativePath
            self.isDirectory = isDirectory
            self.byteCount = byteCount
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
                      (attrs[.size] as? NSNumber)?.int64Value == entry.byteCount else {
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
                byteCount: (attrs[.size] as? NSNumber)?.int64Value ?? 0
            ))
        } else {
            throw DurableWorkspaceSnapshotError.unsupportedFileType(relativePath)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        ((try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType) == .typeDirectory
    }

    private func contains(_ root: URL, child: URL) -> Bool {
        child.path == root.path || child.path.hasPrefix(root.path + "/")
    }
}
