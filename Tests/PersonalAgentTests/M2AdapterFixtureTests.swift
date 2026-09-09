import Foundation
import Testing
import PAFoundation
import PASecurity
import PAProviders
import PAProvidersGrok
import PAProvidersOpenAI
import PAProvidersOpenAICompatible
import PAProvidersLocal

@Suite("M2 adapter fixtures")
struct M2AdapterFixtureTests {
    @Test func grokTranslatesAndDecodesThroughScriptedTransport() async throws {
        let body = Data(#"{"model":"grok-3","choices":[{"message":{"role":"assistant","content":"from-grok"},"finish_reason":"stop"}]}"#.utf8)
        let transport = ScriptedTransport(scripts: [.response(ProviderTransportResponse(statusCode: 200, body: body))])
        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "grok.api")
        await vault.store(Data("test-token".utf8), for: ref)
        let provider = GrokProvider(
            transport: transport,
            credentials: vault,
            configuration: ProviderConfiguration(
                providerID: GrokProviderBoundary.providerID,
                endpointURL: GrokProviderBoundary.defaultEndpoint,
                defaultModel: ModelID(rawValue: "grok-3"),
                credential: ref
            )
        )
        let response = try await provider.complete(LLMRequest(model: ModelID(rawValue: "grok-3"), prompt: "hi"))
        #expect(response.text == "from-grok")
        let recorded = await transport.recordedRequests()
        #expect(recorded.count == 1)
        #expect(recorded[0].url == GrokProviderBoundary.defaultEndpoint)
        #expect(recorded[0].headers["Authorization"] == "Bearer test-token")
        #expect(GrokProviderBoundary.liveNetworkVerified == false)
    }

    @Test func openaiMapsRateLimit() async throws {
        let transport = ScriptedTransport(scripts: [.response(ProviderTransportResponse(statusCode: 429, body: Data()))])
        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: OpenAIProviderBoundary.providerID, account: "openai.api")
        await vault.store(Data("k".utf8), for: ref)
        let provider = OpenAIProvider(
            transport: transport,
            credentials: vault,
            configuration: ProviderConfiguration(
                providerID: OpenAIProviderBoundary.providerID,
                endpointURL: OpenAIProviderBoundary.defaultEndpoint,
                defaultModel: ModelID(rawValue: "gpt-4o-mini"),
                credential: ref
            )
        )
        await #expect(throws: ProviderRuntimeError.rateLimited) {
            _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "gpt-4o-mini"), prompt: "x"))
        }
        #expect(OpenAIProviderBoundary.liveNetworkVerified == false)
    }

    @Test func compatibleRequiresConfiguredEndpoint() async {
        let provider = OpenAICompatibleProvider(
            transport: UnavailableTransport(),
            credentials: InMemoryCredentialVault(),
            configuration: ProviderConfiguration(
                providerID: OpenAICompatibleProviderBoundary.providerID,
                endpointURL: nil,
                defaultModel: ModelID(rawValue: "compatible")
            )
        )
        await #expect(throws: ProviderRuntimeError.invalidConfiguration) {
            _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "compatible"), prompt: "x"))
        }
    }

    @Test func localDecodesStreamFixture() async throws {
        let sse = """
        data: {"model":"local","choices":[{"delta":{"content":"hel"}}]}
        data: {"model":"local","choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}
        data: [DONE]
        """
        let transport = ScriptedTransport(
            scripts: [.response(ProviderTransportResponse(statusCode: 200, body: Data(sse.utf8)))]
        )
        let provider = LocalProvider(
            transport: transport,
            credentials: InMemoryCredentialVault(),
            configuration: ProviderConfiguration(
                providerID: LocalProviderBoundary.providerID,
                endpointURL: LocalProviderBoundary.defaultEndpoint,
                defaultModel: ModelID(rawValue: "local")
            )
        )
        var chunks: [String] = []
        var completed: LLMResponse?
        for try await event in provider.stream(LLMRequest(model: ModelID(rawValue: "local"), prompt: "x")) {
            switch event {
            case .delta(let text): chunks.append(text)
            case .completed(let response): completed = response
            case .toolCall: Issue.record("unexpected tool call")
            }
        }
        #expect(chunks == ["hel", "lo"])
        #expect(completed?.text == "hello")
        #expect(LocalProviderBoundary.intendedCompatibleServers.contains("ollama"))
        #expect(LocalProviderBoundary.liveNetworkVerified == false)
    }

    @Test func adaptersDoNotClaimUnimplementedCapabilities() {
        let grok = GrokProvider(transport: UnavailableTransport(), credentials: InMemoryCredentialVault())
        #expect(grok.capabilities.contains(.textGeneration))
        #expect(!grok.capabilities.contains(.vision))
        #expect(!grok.capabilities.contains(.embeddings))
        #expect(!grok.capabilities.contains(.toolCalling))
        #expect(!grok.capabilities.contains(.structuredOutput))
    }
}
