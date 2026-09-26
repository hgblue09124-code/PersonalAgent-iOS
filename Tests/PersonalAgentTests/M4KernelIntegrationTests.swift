import PARuntime
import Testing
import Foundation
import PAEvents
import PAKernel
import PAComposition
import PAMemory

@Suite("M4 Kernel Integration Tests")
struct M4KernelIntegrationTests {
    @Test func kernelDoesNotExposeMemoryThroughCoordinationBoundary() async throws {
        let coordination = KernelCoordinationBoundary()
        #expect(coordination.isWiredForModules == false)
        #expect(coordination.modules == nil)

        let agentRuntime = try await AgentRuntime(
            identity: AgentIdentity(displayName: "TestAgent"),
            eventLog: InMemoryEventLog(),
            coordination: coordination
        )

        let state = await agentRuntime.currentState()
        #expect(state.identity.displayName == "TestAgent")
    }

    @Test func swappingStoreImplementationsPreservesMemoryRuntimeBehavior() async throws {
        let rec = MemoryRecord(
            kind: .fact,
            content: "Test fact",
            provenance: Provenance(source: "test")
        )

        let inMemoryRuntime = MemoryRuntime(store: InMemoryMemoryStore())
        try await inMemoryRuntime.capture(rec)
        let fetched1 = try await inMemoryRuntime.retrieve(id: rec.id)
        #expect(fetched1?.content == "Test fact")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4KernelSwap_\\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileStore = try FileBackedMemoryStore(directoryURL: tempDir)
        let fileRuntime = MemoryRuntime(store: fileStore)
        try await fileRuntime.capture(rec)

        let fetched2 = try await fileRuntime.retrieve(id: rec.id)
        #expect(fetched2?.content == "Test fact")
    }

    @Test func compositionRootWiresKernelAndMemoryOS() async throws {
        let root = try await M4CompositionRoot()
        #expect(root.milestone.milestone == "M4")
        #expect(root.milestone.memoryEngine == true)
        #expect(root.milestone.storageEngine == true)

        let count = try await root.currentMemoryCount()
        #expect(count == 0)
    }
}
