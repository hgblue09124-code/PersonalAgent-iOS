import Foundation

public struct WorkspacePath: Sendable, Hashable, Equatable {
    public let value: String

    public init(_ value: String) throws {
        let normalized = value.replacingOccurrences(of: "\\\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.hasPrefix("/"), !normalized.split(separator: "/").contains("..") else {
            throw AgentWorkspaceError.invalidPath(value)
        }
        self.value = normalized
    }
}

public struct AgentWorkspaceMetadata: Sendable, Equatable {
    public let relativePath: String
    public let isDirectory: Bool
    public let byteCount: Int

    public init(relativePath: String, isDirectory: Bool, byteCount: Int) {
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.byteCount = byteCount
    }
}

public struct AgentWorkspaceEntry: Sendable, Equatable {
    public let relativePath: String
    public let isDirectory: Bool

    public init(relativePath: String, isDirectory: Bool) {
        self.relativePath = relativePath
        self.isDirectory = isDirectory
    }
}

public enum AgentWorkspaceError: Error, Sendable, Equatable {
    case invalidPath(String)
    case escapesSandbox
    case missing(String)
    case notDirectory(String)
    case notFile(String)
    case ioFailure(String)
}

public protocol AgentWorkspace: Sendable {
    var rootURL: URL { get }

    func prepare() async throws
    func readFile(at relativePath: String) async throws -> String
    func writeFile(_ contents: String, to relativePath: String) async throws
    func appendFile(_ contents: String, to relativePath: String) async throws
    func listDirectory(at relativePath: String) async throws -> [AgentWorkspaceEntry]
    func exists(at relativePath: String) async throws -> Bool
    func metadata(at relativePath: String) async throws -> AgentWorkspaceMetadata
    func createDirectory(at relativePath: String) async throws
    func remove(at relativePath: String) async throws
    func copy(from sourcePath: String, to destinationPath: String) async throws
    func move(from sourcePath: String, to destinationPath: String) async throws
}

public actor LocalAgentWorkspace: AgentWorkspace {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public static func applicationSupport() throws -> LocalAgentWorkspace {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return LocalAgentWorkspace(
            rootURL: root.appendingPathComponent("AgentOS", isDirectory: true)
        )
    }

    public func prepare() async throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        for directory in ["agents", "skills", "modules", "tools", "workspace", "memory", "config", "logs", "cache"] {
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    public func readFile(at relativePath: String) async throws -> String {
        let url = try resolve(relativePath)
        guard isFile(url) else {
            if isDirectory(url) {
                throw AgentWorkspaceError.notFile(relativePath)
            }
            throw AgentWorkspaceError.missing(relativePath)
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    public func writeFile(_ contents: String, to relativePath: String) async throws {
        let url = try resolve(relativePath)
        try createParentDirectory(for: url)

        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    public func appendFile(_ contents: String, to relativePath: String) async throws {
        let url = try resolve(relativePath)
        try createParentDirectory(for: url)

        if !FileManager.default.fileExists(atPath: url.path) {
            try await writeFile(contents, to: relativePath)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contents.data(using: .utf8) ?? Data())
            try handle.close()
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    public func exists(at relativePath: String) async throws -> Bool {
        let url = try resolve(relativePath, allowingRoot: true)
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func metadata(at relativePath: String) async throws -> AgentWorkspaceMetadata {
        let url = try resolve(relativePath, allowingRoot: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentWorkspaceError.missing(relativePath)
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        return AgentWorkspaceMetadata(
            relativePath: relativePath,
            isDirectory: values.isDirectory == true,
            byteCount: values.fileSize ?? 0
        )
    }

    public func listDirectory(at relativePath: String) async throws -> [AgentWorkspaceEntry] {
        let url = try resolve(relativePath, allowingRoot: true)
        guard isDirectory(url) else {
            if FileManager.default.fileExists(atPath: url.path) {
                throw AgentWorkspaceError.notDirectory(relativePath)
            }
            throw AgentWorkspaceError.missing(relativePath)
        }

        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .map { child in
                let relative = child.path.replacingOccurrences(
                    of: rootURL.path + "/",
                    with: ""
                )
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                return AgentWorkspaceEntry(
                    relativePath: relative,
                    isDirectory: values?.isDirectory == true
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
        } catch let error as AgentWorkspaceError {
            throw error
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    public func createDirectory(at relativePath: String) async throws {
        let url = try resolve(relativePath, allowingRoot: true)

        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    public func remove(at relativePath: String) async throws {
        let url = try resolve(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentWorkspaceError.missing(relativePath)
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    public func copy(from sourcePath: String, to destinationPath: String) async throws {
        let source = try resolve(sourcePath)
        let destination = try resolve(destinationPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AgentWorkspaceError.missing(sourcePath)
        }
        try createParentDirectory(for: destination)

        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    public func move(from sourcePath: String, to destinationPath: String) async throws {
        let source = try resolve(sourcePath)
        let destination = try resolve(destinationPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw AgentWorkspaceError.missing(sourcePath)
        }
        try createParentDirectory(for: destination)

        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    private func resolve(_ relativePath: String, allowingRoot: Bool = false) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard allowingRoot else { throw AgentWorkspaceError.invalidPath(relativePath) }
            return rootURL
        }

        let path = trimmed.replacingOccurrences(of: "\\", with: "/")
        guard !path.hasPrefix("/") else {
            throw AgentWorkspaceError.invalidPath(relativePath)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            throw AgentWorkspaceError.escapesSandbox
        }

        let candidate = rootURL
            .appendingPathComponent(path, isDirectory: false)
            .standardizedFileURL

        guard candidate.path == rootURL.path || candidate.path.hasPrefix(rootURL.path + "/") else {
            throw AgentWorkspaceError.escapesSandbox
        }

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.path == resolvedRoot.path
                || resolvedCandidate.path.hasPrefix(resolvedRoot.path + "/") else {
            throw AgentWorkspaceError.escapesSandbox
        }

        return candidate
    }

    private func createParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        } catch {
            throw AgentWorkspaceError.ioFailure(error.localizedDescription)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
            return false
        }
        return values.isRegularFile == true
    }
}
