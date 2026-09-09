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
}

public struct LLMRequest: Sendable, Equatable {
    public let model: ModelID
    public let prompt: String
    public let toolsAllowed: Bool

    public init(model: ModelID, prompt: String, toolsAllowed: Bool = false) {
        self.model = model
        self.prompt = prompt
        self.toolsAllowed = toolsAllowed
    }
}

public struct LLMResponse: Sendable, Equatable {
    public let text: String
    public let finishReason: String

    public init(text: String, finishReason: String) {
        self.text = text
        self.finishReason = finishReason
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

public enum ProviderRuntimeError: Error, Sendable, Equatable {
    case unavailable
    case contextLimitExceeded
    case unsupportedCapability(String)
    case transport(String)
    case decoding(String)
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

/// Credential refs may be held by composition, not by AgentState.
public struct ProviderBinding: Sendable, Equatable {
    public let providerID: ProviderID
    public let credential: ProviderCredentialRef?

    public init(providerID: ProviderID, credential: ProviderCredentialRef?) {
        self.providerID = providerID
        self.credential = credential
    }
}
