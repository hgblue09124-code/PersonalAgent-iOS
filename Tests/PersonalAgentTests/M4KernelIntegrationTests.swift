import Testing
import Foundation
import PAFoundation
import PAEvents
import PAKernel
import PAComposition
import PAMemory

@Suite("M4 Kernel Integration Tests")
struct M4KernelIntegrationTests {
    @Test func kernelInteractsWithMemoryPortWithoutExposingConcreteStore() async throws {
        let store = InMemoryMemoryStore()
        let runtime = MemoryRuntime(store: store)

        let coordination = KernelCoordinationBoundary(memory: runtime)
        #expect(coordination.isWiredForMemory)
        #expect(coordination.memory != nil)

        let agentRuntime = await AgentRuntime(
            identity: AgentIdentity(displayName: "TestAgent"),
            eventLog: InMemoryEventLog(),
            coordination: coordination
        )

        let state = await agentRuntime.currentState()
        #expect(state.identity.displayName == "TestAgent")
    }

    @Test func swappingStoreImplementationsPreservesKernelCoordinationBehavior() async throws {
        // Test 1: InMemoryMemoryStore
        let inMemoryStore = InMemoryMemoryStore()
        let inMemoryRuntime = MemoryRuntime(store: inMemoryStore)
        let coord1 = KernelCoordinationBoundary(memory: inMemoryRuntime)

        let rec = MemoryRecord(kind: .fact, content: "Test fact", provenance: Provenance(source: "test"))
        try await coord1.memory?.capture(rec)

        let fetched1 = try await coord1.memory?.retrieve(id: rec.id)
        #expect(fetched1?.content == "Test fact")

        // Test 2: FileBackedMemoryStore
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4KernelSwap_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileStore = try FileBackedMemoryStore(directoryURL: tempDir)
        let fileRuntime = MemoryRuntime(store: fileStore)
        let coord2 = KernelCoordinationBoundary(memory: fileRuntime)

        try await coord2.memory?.capture(rec)

        let fetched2 = try await coord2.memory?.retrieve(id: rec.id)
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
