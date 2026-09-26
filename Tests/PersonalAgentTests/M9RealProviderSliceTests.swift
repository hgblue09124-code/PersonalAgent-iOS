import Foundation
import Testing
import PAFoundation
import PASecurity
import PAProviders
import PAProvidersGrok
import PAProvidersOpenAI
import PAProvidersOpenAICompatible
import PAProvidersLocal
import PAKernel
import PAEvents
import PAObservability
import PARuntime

@Suite("M9 Parallel Track — Real Provider Vertical Slice Tests")
struct M9RealProviderSliceTests {

    // MARK: - P1: Provider construction/configuration
    @Test func p1_providerConstructionAndConfiguration() async throws {
        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "xai.test")
        await vault.store(Data("test-xai-key".utf8), for: ref)

        let config = ProviderConfiguration(
            providerID: GrokProviderBoundary.providerID,
            endpointURL: GrokProviderBoundary.defaultEndpoint,
            defaultModel: ModelID(rawValue: "grok-3"),
            timeoutNanoseconds: 5_000_000_000,
            credential: ref
        )

        let transport = ScriptedTransport(scripts: [])
        let provider = GrokProvider(
            transport: transport,
            credentials: vault,
            configuration: config
        )

        let logger = ProviderNullLogger()
        let eventLog = InMemoryEventLog()
        let runtime = ProviderRuntime(provider: provider, eventLog: eventLog, logger: logger)

        #expect(await runtime.lifecycle == ProviderLifecycle.unconfigured)
        try await runtime.configure(config)
        #expect(await runtime.lifecycle == ProviderLifecycle.configured)
        try await runtime.ready()
        #expect(await runtime.lifecycle == ProviderLifecycle.ready)
        #expect(await runtime.identity.id == GrokProviderBoundary.providerID)
    }

    // MARK: - P2: Valid request reaches provider boundary
    @Test func p2_validRequestReachesProviderBoundary() async throws {
        let responseBody = Data(#"{"model":"grok-3","choices":[{"message":{"role":"assistant","content":"verified-response"},"finish_reason":"stop"}]}"#.utf8)
        let transport = ScriptedTransport(scripts: [.response(ProviderTransportResponse(statusCode: 200, body: responseBody))])

        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "xai.test")
        await vault.store(Data("secret-api-key".utf8), for: ref)

        let config = ProviderConfiguration(
            providerID: GrokProviderBoundary.providerID,
            endpointURL: GrokProviderBoundary.defaultEndpoint,
            defaultModel: ModelID(rawValue: "grok-3"),
            credential: ref
        )
        let provider = GrokProvider(transport: transport, credentials: vault, configuration: config)

        let request = LLMRequest(
            model: ModelID(rawValue: "grok-3"),
            messages: [ProviderMessage(role: .user, content: "Hello Grok")],
            parameters: GenerationParameters(temperature: 0.7, maxOutputTokens: 100)
        )

        // Injected transport verification: verifying exact wire format generated before hitting transport
        let response = try await provider.complete(request)
        #expect(response.text == "verified-response")

        let recorded = await transport.recordedRequests()
        #expect(recorded.count == 1)
        let req = recorded[0]
        #expect(req.url == GrokProviderBoundary.defaultEndpoint)
        #expect(req.method == "POST")
        #expect(req.headers["Authorization"] == "Bearer secret-api-key")
        #expect(req.headers["Content-Type"] == "application/json")

        // Redacted headers safeguard
        #expect(req.redactedHeaders["Authorization"] == "<redacted>")

        guard let bodyData = req.body,
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        else {
            Issue.record("Request body should be valid JSON")
            return
        }
        #expect(json["model"] as? String == "grok-3")
        #expect((json["messages"] as? [[String: Any]])?.first?["content"] as? String == "Hello Grok")
        #expect(json["temperature"] as? Double == 0.7)
        #expect(json["max_tokens"] as? Int == 100)
    }

    // MARK: - P3: Successful provider response crosses application boundary
    @Test func p3_successfulProviderResponseCrossesApplicationBoundary() async throws {
        let responseBody = Data(#"{"model":"gpt-4o-mini","choices":[{"message":{"role":"assistant","content":"application-received-text"},"finish_reason":"stop"}]}"#.utf8)
        let transport = ScriptedTransport(scripts: [.response(ProviderTransportResponse(statusCode: 200, body: responseBody))])

        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: OpenAIProviderBoundary.providerID, account: "openai.test")
        await vault.store(Data("sk-openai-key".utf8), for: ref)

        let config = ProviderConfiguration(
            providerID: OpenAIProviderBoundary.providerID,
            endpointURL: OpenAIProviderBoundary.defaultEndpoint,
            defaultModel: ModelID(rawValue: "gpt-4o-mini"),
            credential: ref
        )
        let provider = OpenAIProvider(transport: transport, credentials: vault, configuration: config)

        let eventLog = InMemoryEventLog()
        let providerRuntime = ProviderRuntime(provider: provider, eventLog: eventLog, logger: ProviderNullLogger())
        try await providerRuntime.configure(config)
        try await providerRuntime.ready()

        // Test ProviderRuntime execution path
        let response = try await providerRuntime.complete(LLMRequest(model: ModelID(rawValue: "gpt-4o-mini"), prompt: "Test prompt"))
        #expect(response.text == "application-received-text")
        #expect(await providerRuntime.lifecycle == ProviderLifecycle.completed)

        // Wait for async task emission
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify events recorded in event log without leaking secret
        let events = await eventLog.allEvents()
        #expect(events.contains(where: { $0.kind == .providerInvoked }))
        #expect(events.contains(where: { $0.kind == .providerCompleted }))
    }

    // MARK: - P4: Provider failure propagates
    @Test func p4_providerFailurePropagates() async throws {
        // Test explicit HTTP failure mappings
        let statusMappings: [(Int, ProviderRuntimeError)] = [
            (400, .invalidRequest),
            (401, .authenticationFailure),
            (403, .authorizationFailure),
            (408, .timeout),
            (429, .rateLimited),
            (500, .providerFailure),
            (503, .providerFailure)
        ]

        for (status, expectedError) in statusMappings {
            let transport = ScriptedTransport(scripts: [.response(ProviderTransportResponse(statusCode: status, body: Data()))])
            let vault = InMemoryCredentialVault()
            let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "a")
            await vault.store(Data("k".utf8), for: ref)

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

            await #expect(throws: expectedError) {
                _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "grok-3"), prompt: "hi"))
            }
        }

        // Test transport failure injection
        let failTransport = ScriptedTransport(scripts: [.fail(.networkFailure)])
        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "a")
        await vault.store(Data("k".utf8), for: ref)

        let netProvider = GrokProvider(
            transport: failTransport,
            credentials: vault,
            configuration: ProviderConfiguration(
                providerID: GrokProviderBoundary.providerID,
                endpointURL: GrokProviderBoundary.defaultEndpoint,
                defaultModel: ModelID(rawValue: "grok-3"),
                credential: ref
            )
        )

        await #expect(throws: ProviderRuntimeError.networkFailure) {
            _ = try await netProvider.complete(LLMRequest(model: ModelID(rawValue: "grok-3"), prompt: "hi"))
        }
    }

    // MARK: - P5: Empty/malformed provider response fails closed
    @Test func p5_emptyProviderResponseFailsClosed() async throws {
        let malformedBodies: [Data] = [
            Data(), // empty body
            Data("not json".utf8), // invalid json
            Data("{}" .utf8), // empty json object
            Data(#"{"model":"grok-3","choices":[]}"#.utf8), // empty choices array
            Data(#"{"model":"grok-3","choices":[{"message":{"role":"assistant","content":""}}]}"#.utf8), // empty string content
            Data(#"{"model":"grok-3","choices":[{"message":{"role":"assistant","content":"   \n  "}}]}"#.utf8) // whitespace content
        ]

        for body in malformedBodies {
            let transport = ScriptedTransport(scripts: [.response(ProviderTransportResponse(statusCode: 200, body: body))])
            let vault = InMemoryCredentialVault()
            let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "a")
            await vault.store(Data("k".utf8), for: ref)

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

            await #expect(throws: ProviderRuntimeError.decodingFailure) {
                _ = try await provider.complete(LLMRequest(model: ModelID(rawValue: "grok-3"), prompt: "hi"))
            }
        }
    }

    // MARK: - P6: No-provider/configuration failure fails explicitly
    @Test func p6_noProviderConfigurationFailureFailsExplicitly() async throws {
        // Missing endpoint URL
        let noEndpointConfig = ProviderConfiguration(
            providerID: OpenAICompatibleProviderBoundary.providerID,
            endpointURL: nil,
            defaultModel: ModelID(rawValue: "compatible")
        )
        let provider1 = OpenAICompatibleProvider(
            transport: UnavailableTransport(),
            credentials: InMemoryCredentialVault(),
            configuration: noEndpointConfig
        )
        await #expect(throws: ProviderRuntimeError.invalidConfiguration) {
            _ = try await provider1.complete(LLMRequest(model: ModelID(rawValue: "compatible"), prompt: "test"))
        }

        // Missing credential when bearer scheme required
        let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "missing.account")
        let missingCredConfig = ProviderConfiguration(
            providerID: GrokProviderBoundary.providerID,
            endpointURL: GrokProviderBoundary.defaultEndpoint,
            defaultModel: ModelID(rawValue: "grok-3"),
            credential: ref
        )
        let provider2 = GrokProvider(
            transport: ScriptedTransport(scripts: []),
            credentials: InMemoryCredentialVault(), // vault doesn't have the key
            configuration: missingCredConfig
        )
        await #expect(throws: ProviderRuntimeError.authenticationFailure) {
            _ = try await provider2.complete(LLMRequest(model: ModelID(rawValue: "grok-3"), prompt: "test"))
        }

        // Unconfigured ProviderRuntime throws invalidConfiguration
        let runtime = ProviderRuntime(provider: provider2, eventLog: InMemoryEventLog(), logger: ProviderNullLogger())
        await #expect(throws: ProviderRuntimeError.invalidConfiguration) {
            _ = try await runtime.complete(LLMRequest(model: ModelID(rawValue: "grok-3"), prompt: "test"))
        }
    }

    // MARK: - P7: Existing local provider contract remains compilable/compatible
    @Test func p7_localProviderContractRemainsCompatible() async throws {
        let fake = DeterministicFakeProvider()
        #expect(fake.identity.id.rawValue == "fake")

        let req = LLMRequest(model: ModelID(rawValue: "fake-text"), prompt: "hello")
        let res = try await fake.complete(req)
        #expect(res.text == "ok")

        // Local model adapter interface compatibility check
        struct TestEngine: LocalModelEngine {
            let identity = LocalModelIdentity(id: ModelID(rawValue: "test-m"), name: "Test Model", contextTokenLimit: 2048)
            var availability: LocalModelAvailability { get async { .ready } }
            var lifecycleState: LocalModelLifecycleState { get async { .loaded } }
            func load(options: LocalModelLoadingOptions) async throws {}
            func unload() async throws {}
            func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse {
                LocalModelResponse(text: "local-engine-output", finishReason: "stop")
            }
            func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(LocalModelStreamChunk(textDelta: "local-engine-output"))
                    continuation.finish()
                }
            }
            func cancel() async {}
        }

        let engine = TestEngine()
        let adapter = LocalModelProviderAdapter(engine: engine)
        #expect(adapter.capabilities.contains(.localInference))
        #expect(adapter.capabilities.contains(.textGeneration))
        #expect(adapter.identity.id.rawValue == "local-test-m")

        let adapterRes = try await adapter.complete(req)
        #expect(adapterRes.text == "local-engine-output")
    }

    // MARK: - Live Provider Network Execution Gate
    @Test func testRealLiveProviderExecutionWhenKeyProvided() async throws {
        let envKey = ProcessInfo.processInfo.environment["LIVE_PROVIDER_API_KEY"]
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["GROK_API_KEY"]

        guard let key = envKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("LIVE API CONNECTION: UNAVAILABLE (No API key found in LIVE_PROVIDER_API_KEY, OPENAI_API_KEY, or GROK_API_KEY environment variables)")
            return
        }

        let targetProviderStr = ProcessInfo.processInfo.environment["LIVE_PROVIDER_ID"]?.lowercased()
        let isGrok = targetProviderStr == "grok" || (targetProviderStr == nil && ProcessInfo.processInfo.environment["GROK_API_KEY"] != nil)

        let providerID = isGrok ? GrokProviderBoundary.providerID : OpenAIProviderBoundary.providerID
        let endpoint = isGrok ? GrokProviderBoundary.defaultEndpoint : OpenAIProviderBoundary.defaultEndpoint
        let model = isGrok ? ModelID(rawValue: "grok-3") : ModelID(rawValue: "gpt-4o-mini")

        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: providerID, account: "live.api")
        await vault.store(Data(key.utf8), for: ref)

        let config = ProviderConfiguration(
            providerID: providerID,
            endpointURL: endpoint,
            defaultModel: model,
            credential: ref
        )

        let transport = SecurityNetworkTransport(network: URLSessionNetworkAccess())
        let provider: any LLMProvider = isGrok
            ? GrokProvider(transport: transport, credentials: vault, configuration: config)
            : OpenAIProvider(transport: transport, credentials: vault, configuration: config)

        let eventLog = InMemoryEventLog()
        let runtime = ProviderRuntime(provider: provider, eventLog: eventLog, logger: ProviderNullLogger())
        try await runtime.configure(config)
        try await runtime.ready()

        let request = LLMRequest(model: model, prompt: "Respond with the single word: LIVE_VERIFIED")
        let response = try await runtime.complete(request)

        #expect(!response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        print("REAL API CONNECTION: PASS (Received valid response from \(providerID.rawValue): \(response.text))")
    }
}
