import Foundation
import Testing
import PAFoundation
import PAProviders
import PASecurity

@Suite("M2 provider contract")
struct M2ContractTests {
    @Test func requestKeepsPromptCompatibilityAndMessages() {
        let request = LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "hello")
        #expect(request.prompt == "hello")
        #expect(request.messages == [ProviderMessage(role: .user, content: "hello")])
        #expect(request.toolsAllowed == false)
    }

    @Test func requestSupportsSystemAndParameters() {
        let request = LLMRequest(
            model: ModelID(rawValue: "grok-3"),
            messages: [
                ProviderMessage(role: .system, content: "stay terse"),
                ProviderMessage(role: .user, content: "ping"),
            ],
            parameters: GenerationParameters(temperature: 0.2, maxOutputTokens: 16),
            metadata: ["trace": "t1"]
        )
        #expect(request.prompt == "ping")
        #expect(request.parameters.temperature == 0.2)
        #expect(request.metadata["trace"] == "t1")
    }

    @Test func identityAndCapabilitiesAreTyped() {
        let identity = ProviderIdentity(
            id: ProviderID(rawValue: "fake"),
            displayName: "Deterministic Fake",
            models: [ModelIdentity(id: ModelID(rawValue: "fake-text"), displayName: "Fake Text", contextTokenLimit: 8192)]
        )
        let provider = DeterministicFakeProvider(identity: identity)
        #expect(provider.identity.id.rawValue == "fake")
        #expect(provider.capabilities.contains(.textGeneration))
        #expect(provider.capabilities.contains(.streaming))
        #expect(!provider.capabilities.contains(.vision))
        #expect(!provider.capabilities.contains(.embeddings))
        #expect(!provider.capabilities.contains(.toolCalling))
    }

    @Test func errorCategoriesMapFromHTTPStatus() {
        #expect(ProviderRuntimeError.from(statusCode: 401) == .authenticationFailure)
        #expect(ProviderRuntimeError.from(statusCode: 403) == .authorizationFailure)
        #expect(ProviderRuntimeError.from(statusCode: 429) == .rateLimited)
        #expect(ProviderRuntimeError.from(statusCode: 400) == .invalidRequest)
        #expect(ProviderRuntimeError.from(statusCode: 500) == .providerFailure)
        #expect(ProviderRuntimeError.timeout.retryClassification == .retryableTransient)
        #expect(ProviderRuntimeError.authenticationFailure.retryClassification == .doNotRetry)
        #expect(ProviderRuntimeError.cancelled.retryClassification == .doNotRetry)
    }

    @Test func errorsDoNotEmbedRawTransportBodies() {
        #expect(ProviderRuntimeError.decoding("secret-should-not-leak").description == "decoding")
        #expect(ProviderRuntimeError.transport("Authorization: Bearer abc").description == "transport")
    }

    @Test func codecEncodesSemanticRequestWithoutExposingSDKTypes() throws {
        let request = LLMRequest(
            model: ModelID(rawValue: "grok-3"),
            messages: [
                ProviderMessage(role: .system, content: "sys"),
                ProviderMessage(role: .user, content: "hi"),
            ],
            parameters: GenerationParameters(temperature: 0.1, maxOutputTokens: 8)
        )
        let wire = try ChatCompletionsCodec.encodeRequest(
            request,
            endpointURL: "https://example.invalid/v1/chat/completions",
            authorizationHeader: "Bearer test-token",
            stream: false
        )
        #expect(wire.method == "POST")
        #expect(wire.headers["Authorization"] == "Bearer test-token")
        #expect(wire.redactedHeaders["Authorization"] == "<redacted>")
        let json = try JSONSerialization.jsonObject(with: wire.body!) as! [String: Any]
        #expect(json["model"] as? String == "grok-3")
        #expect(json["stream"] as? Bool == false)
        let messages = json["messages"] as! [[String: String]]
        #expect(messages[0]["role"] == "system")
        #expect(messages[1]["content"] == "hi")
    }

    @Test func codecDecodesAssistantMessage() throws {
        let body = Data(#"{"model":"grok-3","choices":[{"message":{"role":"assistant","content":"pong"},"finish_reason":"stop"}]}"#.utf8)
        let response = try ChatCompletionsCodec.decodeResponse(
            ProviderTransportResponse(statusCode: 200, body: body)
        )
        #expect(response.text == "pong")
        #expect(response.finishReason == "stop")
        #expect(response.model?.rawValue == "grok-3")
    }

    @Test func codecMapsUnauthorized() {
        #expect(throws: ProviderRuntimeError.authenticationFailure) {
            _ = try ChatCompletionsCodec.decodeResponse(
                ProviderTransportResponse(statusCode: 401, body: Data("{}".utf8))
            )
        }
    }
}
