import Foundation

/// Copies legacy AgentOS state into the user-visible Documents directory without
/// deleting source data or overwriting files already present at the destination.
public enum AgentOSDirectoryMigration {
    public static func mergeMissingItems(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        guard sourceRoot.standardizedFileURL != destinationRoot.standardizedFileURL,
              fileManager.fileExists(atPath: sourceRoot.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: sourceRoot.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            return
        }

        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        try mergeDirectoryContents(from: sourceRoot, to: destinationRoot, fileManager: fileManager)
    }

    private static func mergeDirectoryContents(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        let children = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for child in children {
            try Task.checkCancellation()
            let attributes = try fileManager.attributesOfItem(atPath: child.path)
            let type = attributes[.type] as? FileAttributeType
            // Never follow or copy symlinks while migrating app state.
            guard type != .typeSymbolicLink else { continue }

            let target = destination.appendingPathComponent(child.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                let targetAttributes = try fileManager.attributesOfItem(atPath: target.path)
                let targetType = targetAttributes[.type] as? FileAttributeType
                if type == .typeDirectory && targetType == .typeDirectory {
                    try mergeDirectoryContents(from: child, to: target, fileManager: fileManager)
                }
                // A destination file wins conflicts; do not replace user-visible data.
                continue
            }

            if type == .typeDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                try mergeDirectoryContents(from: child, to: target, fileManager: fileManager)
            } else if type == .typeRegular {
                let temporary = destination.appendingPathComponent(
                    ".agentos-migration-\(UUID().uuidString).tmp"
                )
                do {
                    try fileManager.copyItem(at: child, to: temporary)
                    if fileManager.fileExists(atPath: target.path) {
                        try? fileManager.removeItem(at: temporary)
                    } else {
                        try fileManager.moveItem(at: temporary, to: target)
                    }
                } catch {
                    try? fileManager.removeItem(at: temporary)
                    throw error
                }
            }
        }
    }
}


/// Resolves the canonical local AgentOS root shared by composition and Terminal.
public enum AgentOSStorageLocation {
    public static func visibleRootURL(fileManager: FileManager = .default) throws -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AgentWorkspaceError.ioFailure("The app Documents directory is unavailable.")
        }
        let legacyRoots: [URL]
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            legacyRoots = [
                appSupport.appendingPathComponent("AgentOS", isDirectory: true),
                appSupport.appendingPathComponent("PersonalAgent/M8Product", isDirectory: true)
            ]
        } else {
            legacyRoots = []
        }
        return try prepareVisibleRoot(documentsDirectory: documents, legacyRoots: legacyRoots, fileManager: fileManager)
    }

    /// Testable migration entry point; each legacy root is merged without overwriting destination data.
    public static func prepareVisibleRoot(
        documentsDirectory: URL,
        legacyRoots: [URL],
        fileManager: FileManager = .default
    ) throws -> URL {
        let visibleRoot = documentsDirectory.appendingPathComponent("AgentOS", isDirectory: true)
        try fileManager.createDirectory(at: visibleRoot, withIntermediateDirectories: true)
        for legacyRoot in legacyRoots {
            try AgentOSDirectoryMigration.mergeMissingItems(from: legacyRoot, to: visibleRoot, fileManager: fileManager)
        }
        return visibleRoot
    }
}
