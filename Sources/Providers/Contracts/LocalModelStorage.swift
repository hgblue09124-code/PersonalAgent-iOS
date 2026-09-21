import Foundation
import PAFoundation
import PAProviders

/// Descriptor representing an imported local GGUF model in app-owned storage.
public struct LocalModelDescriptor: Sendable, Codable, Equatable, Identifiable {
    public let id: ModelID
    public let name: String
    public let filename: String
    public let fileSizeBytes: Int64
    public let formatVersion: UInt32
    public let architecture: String?
    public let contextTokenLimit: Int
    public let importedAt: Date
    public let localRelativePath: String

    public init(
        id: ModelID,
        name: String,
        filename: String,
        fileSizeBytes: Int64,
        formatVersion: UInt32,
        architecture: String? = nil,
        contextTokenLimit: Int = 8192,
        importedAt: Date = Date(),
        localRelativePath: String
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.fileSizeBytes = fileSizeBytes
        self.formatVersion = formatVersion
        self.architecture = architecture
        self.contextTokenLimit = contextTokenLimit
        self.importedAt = importedAt
        self.localRelativePath = localRelativePath
    }

    public func toModelIdentity(baseDirectoryURL: URL) -> LocalModelIdentity {
        let fullURL = baseDirectoryURL.appendingPathComponent(localRelativePath)
        return LocalModelIdentity(
            id: id,
            name: name,
            parameterCount: nil,
            quantization: nil,
            contextTokenLimit: contextTokenLimit,
            fileSizeBytes: fileSizeBytes,
            localURL: fullURL
        )
    }
}

/// Explicit error states for local model storage operations.
public enum LocalModelStorageError: Error, Sendable, Equatable {
    case securityScopeAccessFailed(URL)
    case invalidGGUFHeader(String)
    case fileCopyFailed(String)
    case modelNotFound(ModelID)
    case unreadableFile(URL)
    case storageCorrupted(String)
}

/// Storage contract for local GGUF model management.
public protocol LocalModelStorageStore: Sendable {
    var baseDirectoryURL: URL { get }
    func importModel(from sourceURL: URL, name: String?) async throws -> LocalModelDescriptor
    func listModels() async throws -> [LocalModelDescriptor]
    func selectActiveModel(id: ModelID?) async throws
    func getActiveModelID() async throws -> ModelID?
    func getActiveModelDescriptor() async throws -> LocalModelDescriptor?
    func deleteModel(id: ModelID) async throws
}

/// Actor/class managing GGUF model persistence in app-owned directory.
public actor FileBackedLocalModelStorage: LocalModelStorageStore {
    public let baseDirectoryURL: URL
    public let modelsDirectoryURL: URL
    private let indexFileURL: URL
    private let parser: GGUFModelParser

    private struct IndexState: Codable {
        var models: [ModelID: LocalModelDescriptor]
        var activeModelID: ModelID?
    }

    public init(baseDirectoryURL: URL) throws {
        self.baseDirectoryURL = baseDirectoryURL
        self.modelsDirectoryURL = baseDirectoryURL.appendingPathComponent("Models")
        self.indexFileURL = baseDirectoryURL.appendingPathComponent("models_index.json")
        self.parser = GGUFModelParser()

        let fm = FileManager.default
        try fm.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    public func importModel(from sourceURL: URL, name userDefinedName: String? = nil) async throws -> LocalModelDescriptor {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        #endif

        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw LocalModelStorageError.unreadableFile(sourceURL)
        }

        let summary: GGUFMetadataSummary
        do {
            summary = try parser.parseHeaderAndMetadata(at: sourceURL)
        } catch {
            throw LocalModelStorageError.invalidGGUFHeader("Failed to parse GGUF file header: \(error)")
        }

        let filename = sourceURL.lastPathComponent
        let modelIDString = "gguf-\(UUID().uuidString.prefix(8))"
        let modelID = ModelID(rawValue: modelIDString)
        let modelDirURL = modelsDirectoryURL.appendingPathComponent(modelIDString)

        do {
            try fm.createDirectory(at: modelDirURL, withIntermediateDirectories: true)
            let destinationURL = modelDirURL.appendingPathComponent(filename)
            try fm.copyItem(at: sourceURL, to: destinationURL)

            let attributes = try fm.attributesOfItem(atPath: destinationURL.path)
            let fileSize = (attributes[.size] as? Int64) ?? 0

            let name = userDefinedName ?? (filename as NSString).deletingPathExtension
            let relativePath = "Models/\(modelIDString)/\(filename)"
            let contextLimit = Int(summary.contextLength ?? 8192)

            let descriptor = LocalModelDescriptor(
                id: modelID,
                name: name,
                filename: filename,
                fileSizeBytes: fileSize,
                formatVersion: summary.version,
                architecture: summary.architecture,
                contextTokenLimit: contextLimit > 0 ? contextLimit : 8192,
                importedAt: Date(),
                localRelativePath: relativePath
            )

            var state = try loadIndexState()
            state.models[modelID] = descriptor
            if state.activeModelID == nil {
                state.activeModelID = modelID
            }
            try saveIndexState(state)

            return descriptor
        } catch let err as LocalModelStorageError {
            try? fm.removeItem(at: modelDirURL)
            throw err
        } catch {
            try? fm.removeItem(at: modelDirURL)
            throw LocalModelStorageError.fileCopyFailed("Failed to copy imported model file: \(error.localizedDescription)")
        }
    }

    public func listModels() async throws -> [LocalModelDescriptor] {
        let state = try loadIndexState()
        return Array(state.models.values).sorted(by: { $0.importedAt < $1.importedAt })
    }

    public func selectActiveModel(id: ModelID?) async throws {
        var state = try loadIndexState()
        if let id {
            guard state.models[id] != nil else {
                throw LocalModelStorageError.modelNotFound(id)
            }
            state.activeModelID = id
        } else {
            state.activeModelID = nil
        }
        try saveIndexState(state)
    }

    public func getActiveModelID() async throws -> ModelID? {
        let state = try loadIndexState()
        return state.activeModelID
    }

    public func getActiveModelDescriptor() async throws -> LocalModelDescriptor? {
        let state = try loadIndexState()
        guard let activeID = state.activeModelID else { return nil }
        return state.models[activeID]
    }

    public func deleteModel(id: ModelID) async throws {
        var state = try loadIndexState()
        guard state.models[id] != nil else {
            throw LocalModelStorageError.modelNotFound(id)
        }

        let modelDirURL = modelsDirectoryURL.appendingPathComponent(id.rawValue)
        try? FileManager.default.removeItem(at: modelDirURL)

        state.models.removeValue(forKey: id)
        if state.activeModelID == id {
            state.activeModelID = state.models.keys.first
        }
        try saveIndexState(state)
    }

    // MARK: - Private Index Persistence

    private func loadIndexState() throws -> IndexState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: indexFileURL.path) else {
            return IndexState(models: [:], activeModelID: nil)
        }

        do {
            let data = try Data(contentsOf: indexFileURL)
            return try JSONDecoder().decode(IndexState.self, from: data)
        } catch {
            throw LocalModelStorageError.storageCorrupted("Index file corrupted: \(error.localizedDescription)")
        }
    }

    private func saveIndexState(_ state: IndexState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: indexFileURL, options: .atomic)
    }
}
