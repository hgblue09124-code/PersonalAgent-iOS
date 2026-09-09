import Foundation
import Testing
import PAFoundation
import PAProviders

@Suite("M2 provider concurrency")
struct M2ConcurrencyTests {
    @Test func twoRuntimesDoNotShareMutableState() async throws {
        let left = ProviderRuntime(
            provider: DeterministicFakeProvider(script: .success(LLMResponse(text: "L", finishReason: "stop")))
        )
        let right = ProviderRuntime(
            provider: DeterministicFakeProvider(script: .success(LLMResponse(text: "R", finishReason: "stop")))
        )
        try await configure(left)
        try await configure(right)
        async let l = left.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "a"))
        async let r = right.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "b"))
        let pair = try await (l, r)
        #expect(pair.0.text == "L")
        #expect(pair.1.text == "R")
        #expect(await left.lifecycle == .completed)
        #expect(await right.lifecycle == .completed)
    }

    @Test func catalogResolutionIsExplicit() {
        let fake = DeterministicFakeProvider()
        let catalog = ProviderCatalog(providers: [fake])
        #expect(catalog.resolve(ProviderID(rawValue: "fake")) != nil)
        #expect(catalog.resolve(ProviderID(rawValue: "grok")) == nil)
        #expect(catalog.identities.map(\.id.rawValue) == ["fake"])
    }

    private func configure(_ runtime: ProviderRuntime) async throws {
        try await runtime.configure(
            ProviderConfiguration(providerID: ProviderID(rawValue: "fake"), defaultModel: ModelID(rawValue: "fake-text"))
        )
        try await runtime.ready()
    }
}
