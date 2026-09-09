import Testing
import PAFoundation
import PAKernel

@Suite("Concurrency surface")
struct ConcurrencyContractTests {
    @Test func agentStateCanCrossTasks() async {
        let state = AgentState(identity: AgentIdentity(displayName: "Personal"))
        let snapshot = await Task { state }.value
        #expect(snapshot.phase == .idle)
        #expect(snapshot.lifecycle == .created)
    }

    @Test func capabilityOptionSetIsSendableValue() async {
        let level: CapabilityLevel = [.read, .write]
        let copy = await Task { level }.value
        #expect(copy.contains(.read))
        #expect(copy.contains(.write))
        #expect(!copy.contains(.destructive))
    }
}
