import Foundation
import Testing
import PAWorkspace

@Suite("AgentOS directory migration")
struct AgentOSDirectoryMigrationTests {
    @Test func mergesMissingNestedFilesAndPreservesDestinationConflicts() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("legacy", isDirectory: true)
        let destination = base.appendingPathComponent("visible", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("memory", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("memory", isDirectory: true), withIntermediateDirectories: true)
        try "old-only".write(to: source.appendingPathComponent("memory/old.md"), atomically: true, encoding: .utf8)
        try "legacy-value".write(to: source.appendingPathComponent("memory/conflict.md"), atomically: true, encoding: .utf8)
        try "user-value".write(to: destination.appendingPathComponent("memory/conflict.md"), atomically: true, encoding: .utf8)

        try AgentOSDirectoryMigration.mergeMissingItems(from: source, to: destination)
        try AgentOSDirectoryMigration.mergeMissingItems(from: source, to: destination)

        #expect(try String(contentsOf: destination.appendingPathComponent("memory/old.md"), encoding: .utf8) == "old-only")
        #expect(try String(contentsOf: destination.appendingPathComponent("memory/conflict.md"), encoding: .utf8) == "user-value")
        #expect(try String(contentsOf: source.appendingPathComponent("memory/conflict.md"), encoding: .utf8) == "legacy-value")
    }

    @Test func visibleRootMergesBothLegacyLocationsWithoutReplacingUserFiles() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let documents = base.appendingPathComponent("Documents", isDirectory: true)
        let oldTerminal = base.appendingPathComponent("Support/AgentOS", isDirectory: true)
        let oldRuntime = base.appendingPathComponent("Support/PersonalAgent/M8Product", isDirectory: true)
        try FileManager.default.createDirectory(at: oldTerminal, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldRuntime, withIntermediateDirectories: true)
        try "terminal-state".write(to: oldTerminal.appendingPathComponent("terminal.md"), atomically: true, encoding: .utf8)
        try "runtime-state".write(to: oldRuntime.appendingPathComponent("runtime.md"), atomically: true, encoding: .utf8)

        let root = try AgentOSStorageLocation.prepareVisibleRoot(
            documentsDirectory: documents,
            legacyRoots: [oldTerminal, oldRuntime]
        )

        #expect(root.lastPathComponent == "AgentOS")
        #expect(try String(contentsOf: root.appendingPathComponent("terminal.md"), encoding: .utf8) == "terminal-state")
        #expect(try String(contentsOf: root.appendingPathComponent("runtime.md"), encoding: .utf8) == "runtime-state")
        #expect(FileManager.default.fileExists(atPath: oldTerminal.appendingPathComponent("terminal.md").path))
        #expect(FileManager.default.fileExists(atPath: oldRuntime.appendingPathComponent("runtime.md").path))
    }

    @Test func skipsSymbolicLinksAndLeavesSourceIntact() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("legacy", isDirectory: true)
        let destination = base.appendingPathComponent("visible", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let outside = base.appendingPathComponent("outside.txt")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("linked.txt"), withDestinationURL: outside)
        try "safe".write(to: source.appendingPathComponent("safe.txt"), atomically: true, encoding: .utf8)

        try AgentOSDirectoryMigration.mergeMissingItems(from: source, to: destination)

        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("linked.txt").path))
        #expect(try String(contentsOf: destination.appendingPathComponent("safe.txt"), encoding: .utf8) == "safe")
        #expect(try String(contentsOf: source.appendingPathComponent("safe.txt"), encoding: .utf8) == "safe")
    }
}
