import Foundation
import PAFoundation

/// Shared HTTP chat adapter. Concrete modules supply identity, endpoint, and auth scheme.
public struct HTTPChatProvider: LLMProvider {
    public let identity: ProviderIdentity
    public let capabilities: ProviderCapabilities
    public let configuration: ProviderConfiguration
    private let transport: any ProviderTransport
    private let credentials: any CredentialResolving
    private let authorizationScheme: AuthorizationScheme

    public enum AuthorizationScheme: Sendable, Equatable {
        case none
        case bearer
    }

    public init(
        identity: ProviderIdentity,
        configuration: ProviderConfiguration,
        transport: any ProviderTransport,
        credentials: any CredentialResolving,
        capabilities: ProviderCapabilities = [.textGeneration, .streaming],
        authorizationScheme: AuthorizationScheme = .bearer
    ) {
        self.identity = identity
        self.configuration = configuration
        self.transport = transport
        self.credentials = credentials
        self.capabilities = capabilities
        self.authorizationScheme = authorizationScheme
    }

    public var health: ProviderHealth {
        get async {
            if configuration.endpointURL == nil { return .unavailable }
            return .unknown
        }
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try Task.checkCancellation()
        let wire = try await encode(request, stream: false)
        let response: ProviderTransportResponse
        do {
            response = try await transport.send(wire)
        } catch let error as ProviderRuntimeError {
            throw error
        } catch is CancellationError {
            throw ProviderRuntimeError.cancelled
        } catch {
            throw ProviderRuntimeError.networkFailure
        }
        return try ChatCompletionsCodec.decodeResponse(response)
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let wire = try await encode(request, stream: true)
                    let response = try await transport.send(wire)
                    if response.statusCode != 200 {
                        throw ProviderRuntimeError.from(statusCode: response.statusCode)
                    }
                    for event in try ChatCompletionsCodec.decodeStreamEvents(response.body) {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderRuntimeError.cancelled)
                } catch let error as ProviderRuntimeError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: ProviderRuntimeError.networkFailure)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func encode(_ request: LLMRequest, stream: Bool) async throws -> ProviderTransportRequest {
        guard let endpoint = configuration.endpointURL, !endpoint.isEmpty else {
            throw ProviderRuntimeError.invalidConfiguration
        }
        let header = try await authorizationHeader()
        return try ChatCompletionsCodec.encodeRequest(
            request,
            endpointURL: endpoint,
            authorizationHeader: header,
            stream: stream
        )
    }

    private func authorizationHeader() async throws -> String? {
        switch authorizationScheme {
        case .none:
            return nil
        case .bearer:
            guard let ref = configuration.credential else {
                throw ProviderRuntimeError.invalidConfiguration
            }
            guard let data = try await credentials.secretData(for: ref),
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty
            else {
                throw ProviderRuntimeError.authenticationFailure
            }
            return "Bearer \(token)"
        }
    }
}
