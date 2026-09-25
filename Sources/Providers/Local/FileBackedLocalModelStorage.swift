import Foundation
import PAFoundation
import PAProviders

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
        let isAccessing = startSecurityScopedAccess(for: sourceURL)
        defer {
            if isAccessing {
                stopSecurityScopedAccess(for: sourceURL)
            }
        }

        // Files.app / iCloud / other File Provider URLs may require coordinated
        // reads before the bytes are available to the app. Keep the security-scoped
        // access alive for the complete coordinated import operation.
        let summary: GGUFMetadataSummary
        do {
            summary = try coordinatedRead(sourceURL) { readableURL in
                try parser.parseHeaderAndMetadata(at: readableURL)
            }
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
            }
        } catch {
            throw LocalModelStorageError.invalidGGUFHeader(error.localizedDescription)
        }

        let modelIDRaw = "local-gguf-\(UUID().uuidString.lowercased())"
        let modelID = ModelID(rawValue: modelIDRaw)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "gguf" : sourceURL.pathExtension
        let destinationFilename = "\(modelIDRaw).\(fileExtension)"
        let destinationURL = modelsDirectoryURL.appendingPathComponent(destinationFilename)

        var fileSizeBytes: Int64 = 0
        if let attrs = try? fileManager.attributesOfItem(atPath: sourceURL.path),
           let size = attrs[.size] as? Int64 {
            fileSizeBytes = size
        }

        do {
            try coordinatedRead(sourceURL) { readableURL in
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: readableURL, to: destinationURL)
            }
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
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
            architecture: summary.architecture,
            quantization: nil,
            parameterCount: nil,
            contextWindow: summary.contextLength != nil ? Int(summary.contextLength!) : nil,
            version: summary.version,
            tensorCount: summary.tensorCount,
            metadataCount: summary.metadataCount
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

    private func coordinatedRead<T>(_ sourceURL: URL, _ operation: (URL) throws -> T) throws -> T {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var result: Result<T, Error>?
        var coordinationError: Error?
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { readableURL in
            do {
                result = .success(try operation(readableURL))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw LocalModelStorageError.copyFailed("File Provider returned no readable file URL.")
        }
        return try result.get()
        #else
        // NSFileCoordinator is Apple-platform API. Package tests run on
        // non-Apple hosts, where direct file access is the correct equivalent.
        return try operation(sourceURL)
        #endif
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

        let fileURL = modelsDirectoryURL.appendingPathComponent(descriptor.filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        index.descriptors.removeValue(forKey: id.rawValue)

        if index.activeModelID == id.rawValue {
            index.activeModelID = nil
        }

        try persistIndex()
    }

    public func setActiveModel(id: ModelID?) async throws {
        if let id {
            guard index.descriptors[id.rawValue] != nil else {
                throw LocalModelStorageError.modelNotFound(id)
            }
            index.activeModelID = id.rawValue
        } else {
            index.activeModelID = nil
        }
        try persistIndex()
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
            index.activeModelID = nil
            try? persistIndex()
            return nil
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
