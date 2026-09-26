import Foundation
import PAKernel

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
    func modelFileURL(for id: ModelID) async throws -> URL?
}

