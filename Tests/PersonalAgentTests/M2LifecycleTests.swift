import Foundation
import Testing
import PAFoundation
import PAProviders

@Suite("M2 provider lifecycle")
struct M2LifecycleTests {
    @Test func configureReadyExecuteComplete() async throws {
        let runtime = ProviderRuntime(provider: DeterministicFakeProvider())
        #expect(await runtime.lifecycle == .unconfigured)
        try await runtime.configure(
            ProviderConfiguration(
                providerID: ProviderID(rawValue: "fake"),
                defaultModel: ModelID(rawValue: "fake-text")
            )
        )
        #expect(await runtime.lifecycle == .configured)
        try await runtime.ready()
        #expect(await runtime.lifecycle == .ready)
        let response = try await runtime.complete(
            LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "ping")
        )
        #expect(response.text == "ok")
        #expect(await runtime.lifecycle == .completed)
    }

    @Test func executeBeforeReadyFails() async {
        let runtime = ProviderRuntime(provider: DeterministicFakeProvider())
        await #expect(throws: ProviderRuntimeError.invalidConfiguration) {
            _ = try await runtime.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "x"))
        }
        #expect(await runtime.lifecycle == .unconfigured)
    }

    @Test func failureParksFailed() async throws {
        let runtime = ProviderRuntime(
            provider: DeterministicFakeProvider(script: .failure(.providerFailure))
        )
        try await arm(runtime)
        await #expect(throws: ProviderRuntimeError.providerFailure) {
            _ = try await runtime.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "x"))
        }
        #expect(await runtime.lifecycle == .failed)
    }

    @Test func timeoutParksFailed() async throws {
        let runtime = ProviderRuntime(
            provider: DeterministicFakeProvider(script: .hangUntilCancelled)
        )
        try await arm(runtime)
        await #expect(throws: ProviderRuntimeError.timeout) {
            _ = try await runtime.complete(
                LLMRequest(
                    model: ModelID(rawValue: "fake-text"),
                    messages: [ProviderMessage(role: .user, content: "x")],
                    timeoutNanoseconds: 5_000_000
                )
            )
        }
        #expect(await runtime.lifecycle == .failed)
    }

    @Test func cancellationPropagates() async throws {
        let runtime = ProviderRuntime(
            provider: DeterministicFakeProvider(script: .hangUntilCancelled)
        )
        try await arm(runtime)
        let task = Task {
            try await runtime.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "x"))
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // cooperative cancel of the caller
        } catch let error as ProviderRuntimeError {
            #expect(error == .cancelled || error == .timeout)
        }
    }

    private func arm(_ runtime: ProviderRuntime) async throws {
        try await runtime.configure(
            ProviderConfiguration(providerID: ProviderID(rawValue: "fake"), defaultModel: ModelID(rawValue: "fake-text"))
        )
        try await runtime.ready()
    }
}
