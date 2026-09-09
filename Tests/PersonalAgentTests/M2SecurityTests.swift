import Foundation
import Testing
import PAFoundation
import PASecurity
import PAProviders
import PAProvidersGrok
import PAEvents
import PAObservability

@Suite("M2 credential boundary")
struct M2SecurityTests {
    @Test func secretsStayOutOfEventsAndLogs() async throws {
        let secret = "sk-live-secret-DO-NOT-EMIT"
        let logger = RecordingLogger()
        let log = InMemoryEventLog()
        let body = Data(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#.utf8)
        let transport = ScriptedTransport(scripts: [.response(ProviderTransportResponse(statusCode: 200, body: body))])
        let vault = InMemoryCredentialVault()
        let ref = ProviderCredentialRef(providerID: GrokProviderBoundary.providerID, account: "grok.api")
        await vault.store(Data(secret.utf8), for: ref)
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
        let runtime = ProviderRuntime(provider: provider, eventLog: log, logger: logger)
        try await runtime.configure(
            ProviderConfiguration(
                providerID: GrokProviderBoundary.providerID,
                endpointURL: GrokProviderBoundary.defaultEndpoint,
                defaultModel: ModelID(rawValue: "grok-3"),
                credential: ref
            )
        )
        try await runtime.ready()
        _ = try await runtime.complete(LLMRequest(model: ModelID(rawValue: "grok-3"), prompt: "hi"))

        let events = await log.allEvents()
        let logs = logger.snapshot()
        let blobs = events.map { "\($0.kind.rawValue):\($0.payload)" } + logs.map { "\($0.message):\($0.metadata)" }
        for blob in blobs {
            #expect(!blob.contains(secret), "secret leaked in \(blob)")
        }
        #expect(events.contains { $0.payload["hasCredentialRef"] == "true" })
        let recorded = await transport.recordedRequests()
        #expect(recorded.first?.headers["Authorization"] == "Bearer \(secret)")
        #expect(recorded.first?.redactedHeaders["Authorization"] == "<redacted>")
    }

    @Test func errorDescriptionsDoNotCarryAuthorizationHeaders() {
        let error = ProviderRuntimeError.transport("Authorization: Bearer sk-live-secret-DO-NOT-EMIT")
        #expect(error.description == "transport")
        #expect(!error.description.contains("sk-live"))
    }
}

final class RecordingLogger: AgentLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [LogEvent] = []

    func log(_ event: LogEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [LogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
