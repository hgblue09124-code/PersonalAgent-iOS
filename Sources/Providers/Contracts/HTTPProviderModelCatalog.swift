import Foundation
import PAFoundation
import PASecurity

/// Discovers models exposed by an OpenAI-compatible HTTP endpoint.
/// Authentication is resolved through the existing SecretStore boundary.
public struct HTTPProviderModelCatalog: Sendable {
    private let modelsEndpoint: String
    private let credentialRef: ProviderCredentialRef
    private let credentials: any CredentialResolving
    private let network: any NetworkAccess

    public init(
        modelsEndpoint: String,
        credentialRef: ProviderCredentialRef,
        credentials: any CredentialResolving,
        network: any NetworkAccess
    ) {
        self.modelsEndpoint = modelsEndpoint
        self.credentialRef = credentialRef
        self.credentials = credentials
        self.network = network
    }

    public func discover() async throws -> [ModelIdentity] {
        guard let secret = try await credentials.secretData(for: credentialRef),
              let token = String(data: secret, encoding: .utf8),
              !token.isEmpty else {
            throw ProviderRuntimeError.authenticationFailure
        }

        let response: NetworkResponse
        do {
            response = try await network.data(for: NetworkRequest(
                url: modelsEndpoint,
                method: "GET",
                headers: ["Authorization": "Bearer \(token)"]
            ))
        } catch {
            throw ProviderRuntimeError.networkFailure
        }

        guard response.statusCode == 200 else {
            throw ProviderRuntimeError.from(statusCode: response.statusCode)
        }

        struct ModelItem: Decodable {
            let id: String
        }
        struct Payload: Decodable {
            let data: [ModelItem]
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: response.body)
            let models = payload.data
                .map { ModelIdentity(
                    id: ModelID(rawValue: $0.id),
                    displayName: $0.id,
                    contextTokenLimit: 0
                ) }
                .filter { Self.isChatModel($0.id.rawValue) }
                .sorted { $0.id.rawValue < $1.id.rawValue }

            guard !models.isEmpty else {
                throw ProviderRuntimeError.invalidConfiguration
            }
            return models
        } catch {
            throw ProviderRuntimeError.invalidConfiguration
        }
    }

    private static func isChatModel(_ id: String) -> Bool {
        let normalized = id.lowercased()
        let nonChatMarkers = [
            "embedding", "embed-", "whisper", "tts", "dall-e",
            "moderation", "transcription", "realtime"
        ]
        return !nonChatMarkers.contains { normalized.contains($0) }
    }
}
