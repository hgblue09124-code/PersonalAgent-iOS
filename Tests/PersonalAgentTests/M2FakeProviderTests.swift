import Foundation
import Testing
import PAFoundation
import PAProviders

@Suite("M2 deterministic fake provider")
struct M2FakeProviderTests {
    @Test func success() async throws {
        let provider = DeterministicFakeProvider(
            script: .success(LLMResponse(text: "alpha", finishReason: "stop"))
        )
        let response = try await provider.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "q"))
        #expect(response.text == "alpha")
    }

    @Test func failure() async {
        let provider = DeterministicFakeProvider(script: .failure(.networkFailure))
        await #expect(throws: ProviderRuntimeError.networkFailure) {
            _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "q"))
        }
    }

    @Test func timeoutScript() async {
        let provider = DeterministicFakeProvider(script: .timeout)
        await #expect(throws: ProviderRuntimeError.timeout) {
            _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "q"))
        }
    }

    @Test func unsupportedCapability() async {
        let provider = DeterministicFakeProvider(script: .unsupported(.vision))
        do {
            _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "q"))
            Issue.record("expected unsupported capability")
        } catch let error as ProviderRuntimeError {
            guard case .unsupportedCapability = error else {
                Issue.record("wrong error \(error)")
                return
            }
        } catch {
            Issue.record("wrong type \(error)")
        }
    }

    @Test func streamYieldsDeltaThenCompletion() async throws {
        let provider = DeterministicFakeProvider(
            script: .success(LLMResponse(text: "chunk", finishReason: "stop"))
        )
        var events: [LLMStreamEvent] = []
        for try await event in provider.stream(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "q")) {
            events.append(event)
        }
        #expect(events.first == .delta("chunk"))
        #expect(events.last == .completed(LLMResponse(text: "chunk", finishReason: "stop")))
    }

    @Test func streamCancellationFinishesWithCancelled() async {
        let provider = DeterministicFakeProvider(script: .hangUntilCancelled)
        let stream = provider.stream(LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "q"))
        let task = Task {
            for try await _ in stream {}
        }
        task.cancel()
        do {
            _ = try await task.value
        } catch let error as ProviderRuntimeError {
            #expect(error == .cancelled)
        } catch is CancellationError {
            // acceptable if the task itself is cancelled first
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
