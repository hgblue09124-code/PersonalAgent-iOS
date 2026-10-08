import Foundation
import PAWorkspace

/// Read-only recursive search primitives for the AgentOS terminal.
/// All paths are resolved through AgentWorkspace, so traversal stays inside
/// the sandbox boundary enforced by the workspace implementation.
public struct TerminalWorkspaceSearch: Sendable {
    public init() {}

    public func find(
        named name: String? = nil,
        containingPath fragment: String? = nil,
        from root: String = "",
        workspace: AgentWorkspace
    ) async throws -> [AgentWorkspaceEntry] {
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFragment = fragment?.trimmingCharacters(in: .whitespacesAndNewlines)

        var results: [AgentWorkspaceEntry] = []
        var pending: [String] = [root]
        var visited = Set<String>()

        while let directory = pending.popLast() {
            guard visited.insert(directory).inserted else { continue }

            for entry in try await workspace.listDirectory(at: directory) {
                let path = entry.relativePath
                let basename = path.split(separator: "/").last.map(String.init) ?? path

                let nameMatches = normalizedName.map { basename == $0 } ?? true
                let pathMatches = normalizedFragment.map {
                    path.localizedCaseInsensitiveContains($0)
                } ?? true

                if nameMatches && pathMatches {
                    results.append(entry)
                }

                if entry.isDirectory && !isSymbolicLink(path, workspace: workspace) {
                    pending.append(path)
                }
            }
        }

        return results.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    
    private func isSymbolicLink(_ relativePath: String, workspace: AgentWorkspace) -> Bool {
        let url = workspace.rootURL.appendingPathComponent(relativePath)
        return (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    public func grep(
        pattern: String,
        from root: String = "",
        workspace: AgentWorkspace
    ) async throws -> [TerminalSearchMatch] {
        guard !pattern.isEmpty else {
            throw TerminalSearchError.emptyPattern
        }

        var matches: [TerminalSearchMatch] = []
        let files = try await find(from: root, workspace: workspace)
            .filter { !$0.isDirectory }

        for entry in files {
            let contents: String
            do {
                contents = try await workspace.readFile(at: entry.relativePath)
            } catch {
                continue
            }

            for (index, line) in contents.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).enumerated() {
                let text = String(line)
                if text.localizedCaseInsensitiveContains(pattern) {
                    matches.append(
                        TerminalSearchMatch(
                            path: entry.relativePath,
                            lineNumber: index + 1,
                            line: text
                        )
                    )
                }
            }
        }

        return matches
    }
}

public struct TerminalSearchMatch: Sendable, Equatable {
    public let path: String
    public let lineNumber: Int
    public let line: String

    public init(path: String, lineNumber: Int, line: String) {
        self.path = path
        self.lineNumber = lineNumber
        self.line = line
    }
}

public enum TerminalSearchError: Error, Sendable, Equatable {
    case emptyPattern
}
