import Foundation
import Testing
import PAKernel
import PAProviders
@testable import PAProvidersLocal

@Suite("Local Model Output Quality")
struct LocalModelOutputValidatorTests {
    @Test func repeatedTailIsCollapsed() {
        let input = "I am your personal agent and I can help you. I am your personal agent and I can help you."
        #expect(LocalModelOutputValidator.sanitize(text: input) == "I am your personal agent and I can help you.")
    }

    @Test func tripleRepeatedTailIsCollapsedToOne() {
        let block = "The Agent is ready to help with your request."
        let input = "\(block) \(block) \(block)"
        #expect(LocalModelOutputValidator.sanitize(text: input) == block)
    }

    @Test func repeatedSentenceVariantsAreCollapsed() {
        let input = "Bạn muốn tôi giúp gì? Bạn cần tôi thực hiện một nhiệm vụ cụ thể nào đó? Bạn cần tôi thực hiện một nhiệm vụ nào đó?"
        #expect(LocalModelOutputValidator.sanitize(text: input) == "Bạn cần tôi thực hiện một nhiệm vụ cụ thể nào đó?")
    }

    @Test func genericHelpQuestionDoesNotConsumeStatement() {
        let input = "How can I help? I can help you debug the Swift package and find the failing test."
        #expect(LocalModelOutputValidator.sanitize(text: input) == input)
    }

    @Test func genericHelpQuestionCollapsesToSpecificQuestion() {
        let input = "How can I help? Can you share the Swift test output so I can identify the failing module?"
        #expect(LocalModelOutputValidator.sanitize(text: input) == "Can you share the Swift test output so I can identify the failing module?")
    }

    @Test func normalResponseIsPreserved() {
        let input = "I found the model and imported it successfully."
        #expect(LocalModelOutputValidator.sanitize(text: input) == input)
    }

    @Test func intentionalShortRepetitionIsPreserved() {
        let input = "very very good"
        #expect(LocalModelOutputValidator.sanitize(text: input) == input)
    }
}


@Suite("Local Model Adapter Output Boundary")
struct LocalModelAdapterOutputBoundaryTests {
    private let repeated = "I am your personal agent and I can help you. I am your personal agent and I can help you."
    private let expected = "I am your personal agent and I can help you."

    @Test func completionReturnsSanitizedText() async throws {
        let adapter = LocalModelProviderAdapter(engine: RepeatingOutputEngine(text: repeated))
        let response = try await adapter.complete(
            LLMRequest(model: ModelID(rawValue: "test-model"), prompt: "hello")
        )
        #expect(response.text == expected)
    }

    @Test func streamDoesNotEmitUnsanitizedTokens() async throws {
        let adapter = LocalModelProviderAdapter(engine: RepeatingOutputEngine(text: repeated))
        var deltas: [String] = []
        var completedText: String?
        for try await event in adapter.stream(
            LLMRequest(model: ModelID(rawValue: "test-model"), prompt: "hello")
        ) {
            switch event {
            case .delta(let text):
                deltas.append(text)
            case .toolCall:
                Issue.record("Local model adapter must not emit tool calls for text-only generation.")
            case .completed(let response):
                completedText = response.text
            }
        }
        #expect(deltas.joined() == expected)
        #expect(completedText == expected)
    }
}

private struct RepeatingOutputEngine: LocalModelEngine {
    let text: String
    var identity: LocalModelIdentity {
        LocalModelIdentity(id: ModelID(rawValue: "test-model"), name: "Test model")
    }
    var availability: LocalModelAvailability { get async { .ready } }
    var lifecycleState: LocalModelLifecycleState { get async { .loaded } }

    func load(options: LocalModelLoadingOptions) async throws {}
    func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
        LocalModelResponse(text: text)
    }
    func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let midpoint = text.index(text.startIndex, offsetBy: text.count / 2)
            continuation.yield(LocalModelStreamChunk(textDelta: String(text[..<midpoint])))
            continuation.yield(LocalModelStreamChunk(textDelta: String(text[midpoint...])))
            continuation.finish()
        }
    }
    func cancel() async {}
    func unload() async throws {}
}
