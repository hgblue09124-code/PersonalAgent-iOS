import Foundation
import Testing
import PAKernel
import PAProviders
import PARuntime

@Suite("LLM reasoning streaming")
struct LLMReasonerStreamingTests {
    @Test("Reasoner forwards each delta and returns the assembled response")
    func forwardsDeltasAndReturnsAssembledResponse() async throws {
        let model = ModelID(rawValue: "stream-fixture")
        let provider = StreamingFixtureProvider(events: [
            .delta("A detailed "),
            .delta("answer."),
            .completed(LLMResponse(text: "A detailed answer.", finishReason: "stop", model: model))
        ])
        let recorder = StreamCallbackRecorder()
        let context = ContextBundle(
            perception: Perception(rawInput: "Explain this", source: "user"),
            memoryIDs: [],
            skillIDs: []
        )

        let result = try await LLMReasoner(provider: provider).reason(
            context: context,
            onGenerationStarted: { recorder.markStarted() },
            onDelta: { recorder.append($0) }
        )

        #expect(result.summary == "A detailed answer.")
        #expect(result.modelID == model)
        #expect(recorder.startedCount == 1)
        #expect(recorder.deltas == ["A detailed ", "answer."])
    }

    @Test("Reasoner fails closed when final completion contradicts streamed deltas")
    func mismatchedCompletionFailsClosed() async throws {
        let model = ModelID(rawValue: "stream-fixture")
        let provider = StreamingFixtureProvider(events: [
            .delta("partial response"),
            .completed(LLMResponse(text: "different final response", finishReason: "stop", model: model))
        ])
        let context = ContextBundle(
            perception: Perception(rawInput: "Explain this", source: "user"),
            memoryIDs: [],
            skillIDs: []
        )

        do {
            _ = try await LLMReasoner(provider: provider).reason(
                context: context,
                onGenerationStarted: {},
                onDelta: { _ in }
            )
            Issue.record("A stream whose final completion contradicts its deltas must fail closed")
        } catch let error as KernelError {
            #expect(error.description.contains("does not match emitted deltas"))
        }
    }

    @Test("Reasoner fails closed when a stream contains no text")
    func emptyStreamFailsClosed() async throws {
        let provider = StreamingFixtureProvider(events: [
            .completed(LLMResponse(text: "", finishReason: "stop", model: nil))
        ])
        let context = ContextBundle(
            perception: Perception(rawInput: "Explain this", source: "user"),
            memoryIDs: [],
            skillIDs: []
        )

        do {
            _ = try await LLMReasoner(provider: provider).reason(
                context: context,
                onGenerationStarted: {},
                onDelta: { _ in }
            )
            Issue.record("An empty reasoning stream must not be accepted as a response")
        } catch let error as KernelError {
            #expect(error.description.contains("stream returned empty output"))
        }
    }
}

private struct StreamingFixtureProvider: LLMProvider {
    let events: [LLMStreamEvent]
    private let model = ModelID(rawValue: "stream-fixture")

    var identity: ProviderIdentity {
        ProviderIdentity(
            id: ProviderID(rawValue: "stream-fixture"),
            displayName: "Streaming fixture",
            models: [ModelIdentity(id: model, displayName: "Fixture", contextTokenLimit: 1024)]
        )
    }

    var capabilities: ProviderCapabilities { [.streaming, .textGeneration] }
    var health: ProviderHealth { get async { .healthy } }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw ProviderRuntimeError.unavailable
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class StreamCallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStartedCount = 0
    private var storedDeltas: [String] = []

    var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStartedCount
    }

    var deltas: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedDeltas
    }

    func markStarted() {
        lock.lock()
        defer { lock.unlock() }
        storedStartedCount += 1
    }

    func append(_ delta: String) {
        lock.lock()
        defer { lock.unlock() }
        storedDeltas.append(delta)
    }
}
