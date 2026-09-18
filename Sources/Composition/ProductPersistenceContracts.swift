import Foundation
import PAFoundation
import PASecurity

/// Store for user conversation and UI session presentation records (isolated from Agent state).
public protocol SessionDataStore: Sendable {
    func recordCount() async throws -> Int
    func clearAll() async throws
}

/// In-memory conversation / session presentation data store.
public actor InMemorySessionDataStore: SessionDataStore {
    private var records: [String: String] = [:]

    public init() {}

    public func recordCount() async throws -> Int {
        records.count
    }

    public func clearAll() async throws {
        records.removeAll()
    }
}

/// Store for local model inventory, descriptors, and downloaded file metadata.
public protocol ModelMetadataStore: Sendable {
    func registerModel(id: ModelID, descriptorJSON: String) async throws
    func registeredModelIDs() async throws -> [ModelID]
}

/// In-memory model metadata store.
public actor InMemoryModelMetadataStore: ModelMetadataStore {
    private var metadata: [ModelID: String] = [:]

    public init() {}

    public func registerModel(id: ModelID, descriptorJSON: String) async throws {
        metadata[id] = descriptorJSON
    }

    public func registeredModelIDs() async throws -> [ModelID] {
        Array(metadata.keys)
    }
}

/// Store for user-facing app preferences (UI theme, active provider ID choice, etc.).
public protocol AppPreferencesStore: Sendable {
    func getValue(forKey key: String) async -> String?
    func setValue(_ value: String?, forKey key: String) async
}

/// In-memory app preferences store.
public actor InMemoryAppPreferencesStore: AppPreferencesStore {
    private var preferences: [String: String] = [:]

    public init() {}

    public func getValue(forKey key: String) async -> String? {
        preferences[key]
    }

    public func setValue(_ value: String?, forKey key: String) async {
        preferences[key] = value
    }
}

/// Product-level persistence boundary container ensuring strict directory and store isolation across domains.
public struct ProductPersistenceContainer: Sendable {
    public let baseDirectoryURL: URL
    public let agentDurableDirectoryURL: URL
    public let sessionDataDirectoryURL: URL
    public let modelMetadataDirectoryURL: URL
    public let appPreferencesDirectoryURL: URL
    public let secretsDirectoryURL: URL

    public let sessionDataStore: any SessionDataStore
    public let modelMetadataStore: any ModelMetadataStore
    public let appPreferencesStore: any AppPreferencesStore
    public let secretStore: any SecretStore

    public init(
        baseDirectoryURL: URL,
        sessionDataStore: (any SessionDataStore)? = nil,
        modelMetadataStore: (any ModelMetadataStore)? = nil,
        appPreferencesStore: (any AppPreferencesStore)? = nil,
        secretStore: (any SecretStore)? = nil
    ) throws {
        self.baseDirectoryURL = baseDirectoryURL
        self.agentDurableDirectoryURL = baseDirectoryURL.appendingPathComponent("AgentDurableState")
        self.sessionDataDirectoryURL = baseDirectoryURL.appendingPathComponent("SessionData")
        self.modelMetadataDirectoryURL = baseDirectoryURL.appendingPathComponent("ModelMetadata")
        self.appPreferencesDirectoryURL = baseDirectoryURL.appendingPathComponent("AppPreferences")
        self.secretsDirectoryURL = baseDirectoryURL.appendingPathComponent("Secrets")

        let fm = FileManager.default
        try fm.createDirectory(at: agentDurableDirectoryURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: sessionDataDirectoryURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: modelMetadataDirectoryURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: appPreferencesDirectoryURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: secretsDirectoryURL, withIntermediateDirectories: true)

        self.sessionDataStore = sessionDataStore ?? InMemorySessionDataStore()
        self.modelMetadataStore = modelMetadataStore ?? InMemoryModelMetadataStore()
        self.appPreferencesStore = appPreferencesStore ?? InMemoryAppPreferencesStore()
        self.secretStore = secretStore ?? InMemorySecretStore()
    }
}
