import Foundation
import PAFoundation
import PAObservability
import PASecurity

public struct ProviderIdentity: Hashable, Sendable, Codable {
    public let id: ProviderID
    public let displayName: String
    public let models: [ModelIdentity]

    public init(id: ProviderID, displayName: String, models: [ModelIdentity]) {
        self.id = id
        self.displayName = displayName
        self.models = models
    }
}

public struct ModelIdentity: Hashable, Sendable, Codable {
    public let id: ModelID
    public let displayName: String
    public let contextTokenLimit: Int

    public init(id: ModelID, displayName: String, contextTokenLimit: Int) {
        self.id = id
        self.displayName = displayName
        self.contextTokenLimit = contextTokenLimit
    }
}

public struct ProviderCapabilities: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let streaming = ProviderCapabilities(rawValue: 1 << 0)
    public static let structuredOutput = ProviderCapabilities(rawValue: 1 << 1)
    public static let toolCalling = ProviderCapabilities(rawValue: 1 << 2)
    public static let localInference = ProviderCapabilities(rawValue: 1 << 3)
    public static let textGeneration = ProviderCapabilities(rawValue: 1 << 4)
    public static let vision = ProviderCapabilities(rawValue: 1 << 5)
    public static let embeddings = ProviderCapabilities(rawValue: 1 << 6)
}

public struct ProviderMessage: Sendable, Equatable {
    public enum Role: String, Sendable, Equatable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct GenerationParameters: Sendable, Equatable {
    public let temperature: Double?
    public let maxOutputTokens: Int?

    public init(temperature: Double? = nil, maxOutputTokens: Int? = nil) {
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
    }

    public static let unspecified = GenerationParameters()
}

/// Semantic request. Adapters translate this into a provider wire format.
public struct LLMRequest: Sendable, Equatable {
    public let model: ModelID
    public let messages: [ProviderMessage]
    public let parameters: GenerationParameters
    public let toolsAllowed: Bool
    public let metadata: [String: String]
    public let timeoutNanoseconds: UInt64?

    public var prompt: String {
        messages.last(where: { $0.role == .user })?.content
            ?? messages.map(\.content).joined(separator: "\n")
    }

    public init(
        model: ModelID,
        messages: [ProviderMessage],
        parameters: GenerationParameters = .unspecified,
        toolsAllowed: Bool = false,
        metadata: [String: String] = [:],
        timeoutNanoseconds: UInt64? = nil
    ) {
        self.model = model
        self.messages = messages
        self.parameters = parameters
        self.toolsAllowed = toolsAllowed
        self.metadata = metadata
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    public init(model: ModelID, prompt: String, toolsAllowed: Bool = false) {
        self.init(
            model: model,
            messages: [ProviderMessage(role: .user, content: prompt)],
            toolsAllowed: toolsAllowed
        )
    }
}

public struct LLMResponse: Sendable, Equatable {
    public let text: String
    public let finishReason: String
    public let model: ModelID?

    public init(text: String, finishReason: String, model: ModelID? = nil) {
        self.text = text
        self.finishReason = finishReason
        self.model = model
    }
}

public enum LLMStreamEvent: Sendable, Equatable {
    case delta(String)
    case toolCall(name: String, argumentsJSON: String)
    case completed(LLMResponse)
}

public enum ProviderHealth: String, Sendable, Codable {
    case unknown
    case healthy
    case degraded
    case unavailable
}

/// Isolated from AgentLifecycle. Provider runtime parks these states.
public enum ProviderLifecycle: String, Sendable, Codable, Equatable {
    case unconfigured
    case configured
    case ready
    case executing
    case completed
    case failed
    case cancelled
}

public struct ProviderConfiguration: Sendable, Equatable {
    public let providerID: ProviderID
    public let endpointURL: String?
    public let defaultModel: ModelID
    public let timeoutNanoseconds: UInt64
    public let credential: ProviderCredentialRef?

    public init(
        providerID: ProviderID,
        endpointURL: String? = nil,
        defaultModel: ModelID,
        timeoutNanoseconds: UInt64 = 30_000_000_000,
        credential: ProviderCredentialRef? = nil
    ) {
        self.providerID = providerID
        self.endpointURL = endpointURL
        self.defaultModel = defaultModel
        self.timeoutNanoseconds = timeoutNanoseconds
        self.credential = credential
    }
}

public enum RetryClassification: String, Sendable, Equatable {
    case doNotRetry
    case retryableTransient
}

/// LLM is a reasoning engine. It is not the Agent Runtime.
public protocol LLMProvider: Sendable {
    var identity: ProviderIdentity { get }
    var capabilities: ProviderCapabilities { get }
    var health: ProviderHealth { get async }

    func complete(_ request: LLMRequest) async throws -> LLMResponse
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

public protocol ProviderSelecting: Sendable {
    func provider(for task: String) async -> ProviderID?
}

/// Explicit catalog. Not a service locator and not a global registry.
public struct ProviderCatalog: Sendable {
    private let providers: [ProviderID: any LLMProvider]

    public init(providers: [any LLMProvider] = []) {
        var map: [ProviderID: any LLMProvider] = [:]
        for provider in providers {
            map[provider.identity.id] = provider
        }
        self.providers = map
    }

    public var identities: [ProviderIdentity] {
        providers.values.map(\.identity).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func resolve(_ id: ProviderID) -> (any LLMProvider)? {
        providers[id]
    }
}

/// Credential refs may be held by composition, not by AgentState.
public struct ProviderBinding: Sendable, Equatable {
    public let providerID: ProviderID
    public let credential: ProviderCredentialRef?

    public init(providerID: ProviderID, credential: ProviderCredentialRef?) {
        self.providerID = providerID
        self.credential = credential
    }
}

public protocol CredentialResolving: Sendable {
    func secretData(for ref: ProviderCredentialRef) async throws -> Data?
}

public struct SecretStoreCredentials: CredentialResolving {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    public func secretData(for ref: ProviderCredentialRef) async throws -> Data? {
        try store.load(account: ref.account)
    }
}

public actor InMemoryCredentialVault: CredentialResolving {
    private var storage: [String: Data] = [:]

    public init() {}

    public func store(_ data: Data, for ref: ProviderCredentialRef) {
        storage[ref.account] = data
    }

    public func delete(_ ref: ProviderCredentialRef) {
        storage[ref.account] = nil
    }

    public func secretData(for ref: ProviderCredentialRef) async throws -> Data? {
        storage[ref.account]
    }
}
