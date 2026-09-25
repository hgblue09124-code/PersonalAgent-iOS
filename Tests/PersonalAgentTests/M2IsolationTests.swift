import Testing
import PAFoundation
import PAArchitecture
import PAComposition
import PAKernel
import PAProviders

@Suite("M2 isolation")
struct M2IsolationTests {
    @Test func kernelDoesNotExposeProviderThroughCoordinationBoundary() async throws {
        let runtime = try await AgentRuntime(
            identity: AgentIdentity(displayName: "Personal"),
            eventLog: InMemoryEventLog()
        )
        #expect(await runtime.coordination.isWiredForModules == false)
        #expect(await runtime.coordination.modules == nil)
        let state = await runtime.currentState()
        #expect(state.lifecycle == .created)
    }

    @Test func providerRuntimeDoesNotMutateAgentLifecycle() async throws {
        let log = InMemoryEventLog()
        let agent = try await AgentRuntime(
            identity: AgentIdentity(displayName: "Personal"),
            eventLog: log
        )
