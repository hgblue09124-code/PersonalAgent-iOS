import PAComposition
import PARuntime
import Foundation
import Testing
import PAArchitecture
import PAKernel
import PAProviders
import PAEvents
import PAFoundation

@Suite("M2 kernel isolation")
struct M2IsolationTests {
    @Test func kernelSourcesStayClearOfConcreteProvidersAndTransport() throws {
        let kernelDir = repositoryRoot().appendingPathComponent("Kernel")
        let files = try files(under: kernelDir, suffix: ".swift")
        #expect(!files.isEmpty)
        let banned = [
            "PAProvidersGrok", "PAProvidersOpenAI", "PAProvidersOpenAICompatible",
            "PAProvidersLocal", "GrokProvider", "OpenAIProvider",
            "OpenAICompatibleProvider", "LocalProvider", "URLSession",
            "api.x.ai", "api.openai.com",
        ]
        var hits: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned where text.contains(token) {
                hits.append("\(file.lastPathComponent) contains \(token)")
            }
        }
        #expect(hits.isEmpty)
    }

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
        let providerRuntime = ProviderRuntime(provider: DeterministicFakeProvider(), eventLog: log)
        try await providerRuntime.configure(
            ProviderConfiguration(providerID: ProviderID(rawValue: "fake"), defaultModel: ModelID(rawValue: "fake-text"))
        )
        try await providerRuntime.ready()
        _ = try await providerRuntime.complete(
            LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "x")
        )
        #expect(await agent.currentState().lifecycle == .created)
        #expect(await providerRuntime.lifecycle == .completed)
    }
}
