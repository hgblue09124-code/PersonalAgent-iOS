import Foundation
import PAFoundation

/// Metadata descriptor for an imported local GGUF model in app-owned storage.
public struct LocalModelDescriptor: Sendable, Codable, Equatable, Identifiable {
    public let id: ModelID
    public let name: String
    public let filename: String
    public let fileSizeBytes: Int64
    public let addedAt: Date
    public let architecture: String?
    public let quantization: String?
    public let parameterCount: String?
    public let contextWindow: Int?
    public let version: UInt32?
    public let tensorCount: UInt64?
    public let metadataCount: UInt64?

    public init(
        id: ModelID,
        name: String,
        filename: String,
        fileSizeBytes: Int64,
        addedAt: Date = Date(),
        architecture: String? = nil,
        quantization: String? = nil,
        parameterCount: String? = nil,
        contextWindow: Int? = nil,
        version: UInt32? = nil,
        tensorCount: UInt64? = nil,
        metadataCount: UInt64? = nil
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.fileSizeBytes = fileSizeBytes
        self.addedAt = addedAt
        self.architecture = architecture
        self.quantization = quantization
        self.parameterCount = parameterCount
        self.contextWindow = contextWindow
        self.version = version
        self.tensorCount = tensorCount
        self.metadataCount = metadataCount
    }
}

/// Errors raised during local model storage, validation, or selection operations.
public enum LocalModelStorageError: Error, Sendable, Equatable {
    case fileNotFound(URL)
    case accessDenied(URL)
    case invalidGGUFHeader(String)
    case unsupportedGGUFVersion(UInt32)
    case copyFailed(String)
    case modelNotFound(ModelID)
    case storageCorrupt(String)
}

/// Vendor-agnostic contract for managing local model storage, GGUF import, and selection.
public protocol LocalModelStorage: Sendable {
    func importModel(from sourceURL: URL, name: String?) async throws -> LocalModelDescriptor
    func listModels() async throws -> [LocalModelDescriptor]
    func getModel(id: ModelID) async throws -> LocalModelDescriptor?
    func deleteModel(id: ModelID) async throws
    func setActiveModel(id: ModelID?) async throws
    func activeModelID() async throws -> ModelID?
    func activeModelDescriptor() async throws -> LocalModelDescriptor?
}

/// Local model identity representation.
public struct LocalModelIdentity: Sendable, Codable, Equatable, Identifiable {
    public let id: ModelID
    public let name: String
    public let parameterCount: String?
    public let quantization: String?
    public let contextTokenLimit: Int
    public let fileSizeBytes: Int64?
    public let localURL: URL?

    public init(
        id: ModelID,
        name: String,
        parameterCount: String? = nil,
        quantization: String? = nil,
        contextTokenLimit: Int = 8192,
        fileSizeBytes: Int64? = nil,
        localURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.contextTokenLimit = contextTokenLimit
        self.fileSizeBytes = fileSizeBytes
        self.localURL = localURL
    }
}

/// Download / presence availability state for a local model.
public enum LocalModelAvailability: Sendable, Codable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case unsupported(reason: String)
    case error(String)
}

/// In-memory lifecycle state for a local model engine.
public enum LocalModelLifecycleState: Sendable, Codable, Equatable {
    case unloaded
    case loading(progress: Double)
    case loaded
    case unloading
    case failed(reason: String)
}

/// Model loading configuration options.
public struct LocalModelLoadingOptions: Sendable, Codable, Equatable {
    public let contextWindow: Int
    public let gpuLayers: Int?
    public let maxTokens: Int
    public let threadCount: Int?
    public let useMetal: Bool

    public init(
        contextWindow: Int = 8192,
        gpuLayers: Int? = nil,
        maxTokens: Int = 2048,
        threadCount: Int? = nil,
        useMetal: Bool = true
    ) {
        self.contextWindow = contextWindow
        self.gpuLayers = gpuLayers
        self.maxTokens = maxTokens
        self.threadCount = threadCount
        self.useMetal = useMetal
    }
}

/// Standalone request payload for local model generation.
public struct LocalModelGenerationRequest: Sendable, Codable, Equatable {
    public let prompt: String
    public let systemPrompt: String?
    public let maxTokens: Int?
    public let temperature: Double?
    public let stopSequences: [String]

    public init(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        stopSequences: [String] = []
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.stopSequences = stopSequences
    }
}

/// Stream chunk emitted during local streaming generation.
public struct LocalModelStreamChunk: Sendable, Codable, Equatable {
    public let textDelta: String
    public let finishReason: String?

    public init(textDelta: String, finishReason: String? = nil) {
        self.textDelta = textDelta
        self.finishReason = finishReason
    }
}

/// Non-streaming result of a local model generation request.
public struct LocalModelResponse: Sendable, Codable, Equatable {
    public let text: String
    public let finishReason: String
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(
        text: String,
        finishReason: String = "stop",
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.text = text
        self.finishReason = finishReason
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// Vendor-agnostic contract for on-device local model inference engines (MLX, llama.cpp, Core ML, Apple Foundation, etc.).
public protocol LocalModelEngine: Sendable {
    var identity: LocalModelIdentity { get }
    var availability: LocalModelAvailability { get async }
    var lifecycleState: LocalModelLifecycleState { get async }

    func load(options: LocalModelLoadingOptions) async throws
    func generate(request: LocalModelGenerationRequest) async throws -> LocalModelResponse
    func generateStream(request: LocalModelGenerationRequest) -> AsyncThrowingStream<LocalModelStreamChunk, Error>
    func cancel() async
    func unload() async throws
}
