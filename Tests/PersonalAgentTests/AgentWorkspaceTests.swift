import Foundation
import Testing
import PAWorkspace

@Suite("AgentOS workspace sandbox")
struct AgentWorkspaceTests {
    private func makeWorkspace() throws -> (LocalAgentWorkspace, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalAgentWorkspace-\(UUID().uuidString)", isDirectory: true)
        return (LocalAgentWorkspace(rootURL: root), root)
    }

    @Test func workspaceCreatesCanonicalAgentOSLayout() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try await workspace.prepare()

        for directory in ["agents", "skills", "modules", "tools", "workspace", "memory", "config", "logs", "cache"] {
            let url = root.appendingPathComponent(directory, isDirectory: true)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func workspaceReadsWritesAndListsFiles() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try await workspace.prepare()
        try await workspace.writeFile("# Calculator\n", to: "skills/calculator/Skill.md")
        try await workspace.appendFile("rule: deterministic\n", to: "skills/calculator/Skill.md")

        #expect(try await workspace.readFile(at: "skills/calculator/Skill.md") == "# Calculator\nrule: deterministic\n")

        let entries = try await workspace.listDirectory(at: "skills")
        #expect(entries == [AgentWorkspaceEntry(relativePath: "skills/calculator", isDirectory: true)])
    }

    @Test func workspaceRejectsTraversalAndAbsolutePaths() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try await workspace.prepare()

        await #expect(throws: AgentWorkspaceError.escapesSandbox) {
            try await workspace.readFile(at: "../outside.txt")
        }

        await #expect(throws: AgentWorkspaceError.invalidPath("/outside.txt")) {
            try await workspace.readFile(at: "/outside.txt")
        }
    }

    @Test func workspaceRejectsSymlinkEscape() async throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try await workspace.prepare()

        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let link = root.appendingPathComponent("escape.txt")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside
        )

        await #expect(throws: AgentWorkspaceError.escapesSandbox) {
            try await workspace.readFile(at: "escape.txt")
        }
    }
}
