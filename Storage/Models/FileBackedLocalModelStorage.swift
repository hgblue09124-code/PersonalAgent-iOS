import Foundation
import PAKernel
import PAProviders
import PAGGUF

/// Internal persistent index state for local model metadata and active selection.
private struct LocalModelIndex: Codable, Sendable {
    var descriptors: [String: LocalModelDescriptor]
    var activeModelID: String?

    init(descriptors: [String: LocalModelDescriptor] = [:], activeModelID: String? = nil) {
        self.descriptors = descriptors
        self.activeModelID = activeModelID
    }
}

#if canImport(Foundation) && (os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS))
private func startSecurityScopedAccess(for url: URL) -> Bool {
    url.startAccessingSecurityScopedResource()
}

private func stopSecurityScopedAccess(for url: URL) {
    url.stopAccessingSecurityScopedResource()
}
#else
private func startSecurityScopedAccess(for url: URL) -> Bool {
    false
}

private func stopSecurityScopedAccess(for url: URL) {}
#endif

/// File-backed GGUF storage manager handling security-scoped URL import,
/// GGUF header validation, app-owned file copying, metadata indexing, and active model selection.
public actor FileBackedLocalModelStorage: LocalModelStorage {
    private let modelsDirectoryURL: URL
    private let indexFileURL: URL
    private let parser: GGUFModelParser
    private let fileManager: FileManager
    private var index: LocalModelIndex

    public init(modelsDirectoryURL: URL, fileManager: FileManager = .default) throws {
        self.modelsDirectoryURL = modelsDirectoryURL
        self.indexFileURL = modelsDirectoryURL.appendingPathComponent("models_index.json")
        self.parser = GGUFModelParser()
        self.fileManager = fileManager

        if !fileManager.fileExists(atPath: modelsDirectoryURL.path) {
            try fileManager.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: indexFileURL.path) {
            do {
                let data = try Data(contentsOf: indexFileURL)
                let decoder = JSONDecoder()
                self.index = try decoder.decode(LocalModelIndex.self, from: data)
            } catch {
                throw LocalModelStorageError.storageCorrupt("Failed to read models index: \(error.localizedDescription)")
            }
        } else {
            self.index = LocalModelIndex()
        }
    }

    public func importModel(from sourceURL: URL, name: String? = nil) async throws -> LocalModelDescriptor {
        let modelExtension = sourceURL.pathExtension.lowercased()
        guard modelExtension == "gguf" || modelExtension == "litertlm" else {
            throw LocalModelStorageError.invalidGGUFHeader("Only .gguf and .litertlm model files can be imported.")
        }

        let isAccessing = startSecurityScopedAccess(for: sourceURL)
        defer {
            if isAccessing {
                stopSecurityScopedAccess(for: sourceURL)
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw LocalModelStorageError.fileNotFound(sourceURL)
        }

        let sourceAttributes: [FileAttributeKey: Any]
        do {
            sourceAttributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        } catch {
            throw LocalModelStorageError.fileNotFound(sourceURL)
        }
        let minimumFileSize: Int64 = modelExtension == "gguf" ? 24 : 1
        guard let sourceSize = sourceAttributes[.size] as? NSNumber,
              sourceSize.int64Value >= minimumFileSize else {
            throw LocalModelStorageError.invalidGGUFHeader("Local model file is empty or smaller than its minimum supported size.")
        }

        let summary: GGUFMetadataSummary?
        do {
            summary = modelExtension == "gguf"
                ? try parser.parseHeaderAndMetadata(at: sourceURL)
                : nil
        } catch let error as GGUFParseError {
            switch error {
            case .invalidMagic(let magic):
                throw LocalModelStorageError.invalidGGUFHeader("Invalid GGUF magic bytes: \(String(format: "0x%08X", magic))")
            case .unsupportedVersion(let version):
                throw LocalModelStorageError.unsupportedGGUFVersion(version)
            case .truncatedFile:
                throw LocalModelStorageError.invalidGGUFHeader("Truncated GGUF file")
            case .stringDecodingFailed:
                throw LocalModelStorageError.invalidGGUFHeader("GGUF string decoding failed")
            case .invalidContextLength:
                throw LocalModelStorageError.invalidGGUFHeader("Invalid GGUF context length")
            }
        } catch {
            throw LocalModelStorageError.invalidGGUFHeader(error.localizedDescription)
        }

        let modelIDRaw = "local-\(modelExtension)-\(UUID().uuidString.lowercased())"
        let modelID = ModelID(rawValue: modelIDRaw)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "gguf" : sourceURL.pathExtension
        let destinationFilename = "\(modelIDRaw).\(fileExtension)"
        let destinationURL = modelsDirectoryURL.appendingPathComponent(destinationFilename)

        let fileSizeBytes = sourceSize.int64Value

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            let copiedAttributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            guard let copiedSize = copiedAttributes[.size] as? NSNumber,
                  copiedSize.int64Value == fileSizeBytes else {
                throw LocalModelStorageError.copyFailed("Imported model file size does not match the source.")
            }
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            if let storageError = error as? LocalModelStorageError {
                throw storageError
            }
            throw LocalModelStorageError.copyFailed("Failed to copy GGUF model file to app storage: \(error.localizedDescription)")
        }

        let displayName = name ?? sourceURL.deletingPathExtension().lastPathComponent
        let descriptor = LocalModelDescriptor(
            id: modelID,
            name: displayName,
            filename: destinationFilename,
            fileSizeBytes: fileSizeBytes,
            addedAt: Date(),
            architecture: summary?.architecture ?? (modelExtension == "litertlm" ? "litert-lm" : nil),
            quantization: nil,
            parameterCount: nil,
            contextWindow: summary?.contextLength.map(Int.init),
            version: summary?.version,
            tensorCount: summary?.tensorCount,
            metadataCount: summary?.metadataCount
        )

        index.descriptors[modelID.rawValue] = descriptor
        do {
            try persistIndex()
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            index.descriptors.removeValue(forKey: modelID.rawValue)
            throw error
        }

        return descriptor
    }

    public func listModels() async throws -> [LocalModelDescriptor] {
        Array(index.descriptors.values).sorted { $0.addedAt < $1.addedAt }
    }

    public func getModel(id: ModelID) async throws -> LocalModelDescriptor? {
        index.descriptors[id.rawValue]
    }

    public func deleteModel(id: ModelID) async throws {
        guard let descriptor = index.descriptors[id.rawValue] else {
            throw LocalModelStorageError.modelNotFound(id)
        }

        let previousIndex = index
        let fileURL = modelsDirectoryURL.appendingPathComponent(descriptor.filename)

        // Persist the metadata removal before deleting the large model file. If
        // persistence fails, the original file is untouched and can be retried.
        index.descriptors.removeValue(forKey: id.rawValue)
        if index.activeModelID == id.rawValue {
            index.activeModelID = nil
        }
        do {
            try persistIndex()
        } catch {
            index = previousIndex
            throw error
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            let removalError = error
            index = previousIndex
            do {
                try persistIndex()
            } catch {
                throw LocalModelStorageError.storageCorrupt(
                    "Model file deletion failed and metadata rollback also failed: \(error.localizedDescription)"
                )
            }
            throw removalError
        }
    }

    public func setActiveModel(id: ModelID?) async throws {
        let previousActiveModelID = index.activeModelID
        if let id {
            guard index.descriptors[id.rawValue] != nil else {
                throw LocalModelStorageError.modelNotFound(id)
            }
            index.activeModelID = id.rawValue
        } else {
            index.activeModelID = nil
        }
        do {
            try persistIndex()
        } catch {
            index.activeModelID = previousActiveModelID
            throw error
        }
    }

    public func activeModelID() async throws -> ModelID? {
        if let descriptor = try await activeModelDescriptor() {
            return descriptor.id
        }
        return nil
    }

    public func activeModelDescriptor() async throws -> LocalModelDescriptor? {
        guard let raw = index.activeModelID else { return nil }
        guard let descriptor = index.descriptors[raw] else {
            index.activeModelID = nil
            try? persistIndex()
            return nil
        }

        let fileURL = modelsDirectoryURL.appendingPathComponent(descriptor.filename)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw LocalModelStorageError.fileNotFound(fileURL)
        }

        return descriptor
    }

    public func modelFileURL(for id: ModelID) async throws -> URL? {
        guard let descriptor = index.descriptors[id.rawValue] else { return nil }
        let url = modelsDirectoryURL.appendingPathComponent(descriptor.filename)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func persistIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: indexFileURL, options: .atomic)
    }
}
