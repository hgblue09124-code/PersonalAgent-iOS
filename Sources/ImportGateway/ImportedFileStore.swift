import Foundation

public struct ImportedFile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let originalName: String
    public let storedFilename: String
    public let contentTypeIdentifier: String?
    public let fileExtension: String
    public let sizeBytes: Int64
    public let importedAt: Date

    public init(
        id: UUID,
        originalName: String,
        storedFilename: String,
        contentTypeIdentifier: String?,
        fileExtension: String,
        sizeBytes: Int64,
        importedAt: Date
    ) {
        self.id = id
        self.originalName = originalName
        self.storedFilename = storedFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.fileExtension = fileExtension
        self.sizeBytes = sizeBytes
        self.importedAt = importedAt
    }
}

public enum ImportGatewayError: Error, Sendable, Equatable {
    case sourceIsNotAFile
    case fileTooLarge(limitBytes: Int64)
    case insufficientStorage
    case sourceChangedDuringImport
    case invalidStoredPath
    case corruptManifest
}

/// Durable, format-agnostic intake. Specialized parsers should consume ImportedFile
/// records later; importing a file never implies that its contents are trusted.
public actor ImportedFileStore {
    public static let defaultMaximumFileSize: Int64 = 10 * 1024 * 1024 * 1024

    private let root: URL
    private let filesDirectory: URL
    private let manifestURL: URL
    private let fileManager: FileManager
    private let maximumFileSize: Int64
    private var records: [ImportedFile]

    public init(
        directoryURL: URL,
        maximumFileSize: Int64 = ImportedFileStore.defaultMaximumFileSize,
        fileManager: FileManager = .default
    ) throws {
        self.root = directoryURL
        self.filesDirectory = directoryURL.appendingPathComponent("Files", isDirectory: true)
        self.manifestURL = directoryURL.appendingPathComponent("imports.json", isDirectory: false)
        self.fileManager = fileManager
        self.maximumFileSize = max(0, maximumFileSize)

        try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: manifestURL.path) {
            do {
                let data = try Data(contentsOf: manifestURL)
                self.records = try JSONDecoder().decode([ImportedFile].self, from: data)
                for record in self.records {
                    guard Self.isSafeStoredFilename(record.storedFilename) else {
                        throw ImportGatewayError.invalidStoredPath
                    }
                }
            } catch let error as ImportGatewayError {
                throw error
            } catch {
                throw ImportGatewayError.corruptManifest
            }
        } else {
            self.records = []
        }
    }

    @discardableResult
    public func importFile(
        from sourceURL: URL,
        contentTypeIdentifier: String? = nil
    ) async throws -> ImportedFile {
        #if canImport(Darwin)
        let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        #endif

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        } catch {
            throw CocoaError(.fileNoSuchFile)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size >= 0 else {
            throw ImportGatewayError.sourceIsNotAFile
        }
        guard size <= maximumFileSize else {
            throw ImportGatewayError.fileTooLarge(limitBytes: maximumFileSize)
        }
        try Self.checkAvailableSpace(requiredBytes: size, at: root, fileManager: fileManager)
        try Task.checkCancellation()

        let id = UUID()
        let ext = sourceURL.pathExtension.lowercased()
        let safeExtension = ext.range(of: #"^[a-z0-9_-]{1,32}$"#, options: .regularExpression) != nil ? ext : ""
        let storedFilename = id.uuidString.lowercased() + (safeExtension.isEmpty ? "" : ".\(safeExtension)")
        let destination = filesDirectory.appendingPathComponent(storedFilename, isDirectory: false)
        let temporary = filesDirectory.appendingPathComponent(".\(id.uuidString).partial", isDirectory: false)

        do {
            let input = try FileHandle(forReadingFrom: sourceURL)
            defer { try? input.close() }
            guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }

            var copiedBytes: Int64 = 0
            while true {
                try Task.checkCancellation()
                guard let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
                copiedBytes += Int64(chunk.count)
                guard copiedBytes <= maximumFileSize else {
                    throw ImportGatewayError.fileTooLarge(limitBytes: maximumFileSize)
                }
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
            guard copiedBytes == size else {
                throw ImportGatewayError.sourceChangedDuringImport
            }
            try fileManager.moveItem(at: temporary, to: destination)

            let record = ImportedFile(
                id: id,
                originalName: sourceURL.lastPathComponent,
                storedFilename: storedFilename,
                contentTypeIdentifier: contentTypeIdentifier,
                fileExtension: safeExtension,
                sizeBytes: copiedBytes,
                importedAt: Date()
            )
            records.insert(record, at: 0)
            do {
                try persistManifest()
            } catch {
                records.removeAll { $0.id == id }
                try? fileManager.removeItem(at: destination)
                throw error
            }
            return record
        } catch {
            try? fileManager.removeItem(at: temporary)
            if fileManager.fileExists(atPath: destination.path),
               !records.contains(where: { $0.storedFilename == storedFilename }) {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    public func listImports() -> [ImportedFile] {
        records.sorted { $0.importedAt > $1.importedAt }
    }

    public func fileURL(for id: UUID) -> URL? {
        guard let record = records.first(where: { $0.id == id }),
              Self.isSafeStoredFilename(record.storedFilename) else { return nil }
        let url = filesDirectory.appendingPathComponent(record.storedFilename, isDirectory: false)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func removeImport(id: UUID) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        guard Self.isSafeStoredFilename(record.storedFilename) else {
            throw ImportGatewayError.invalidStoredPath
        }
        records.remove(at: index)
        do {
            try persistManifest()
        } catch {
            records.insert(record, at: index)
            throw error
        }
        let url = filesDirectory.appendingPathComponent(record.storedFilename, isDirectory: false)
        try? fileManager.removeItem(at: url)
    }

    private func persistManifest() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func isSafeStoredFilename(_ filename: String) -> Bool {
        !filename.isEmpty &&
        filename != "." && filename != ".." &&
        !filename.contains("/") && !filename.contains("\\") &&
        !filename.hasPrefix(".")
    }

    private static func checkAvailableSpace(
        requiredBytes: Int64,
        at directory: URL,
        fileManager: FileManager
    ) throws {
        let attributes = try fileManager.attributesOfFileSystem(forPath: directory.path)
        guard let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else { return }
        // Leave 16 MiB for metadata, app activity and filesystem overhead.
        let (requiredWithReserve, overflow) = requiredBytes.addingReportingOverflow(16 * 1024 * 1024)
        guard !overflow, free >= requiredWithReserve else {
            throw ImportGatewayError.insufficientStorage
        }
    }
}
