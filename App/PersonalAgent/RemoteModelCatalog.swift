import Foundation
import CryptoKit
import PAProviders

struct RemoteModelCatalog: Codable, Sendable {
    let schemaVersion: Int
    let models: [RemoteModel]
}

struct RemoteModel: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let filename: String
    let architecture: String
    let parameterCount: String
    let quantization: String
    let contextWindow: Int
    let sizeBytes: Int64
    let sha256: String
    let downloadURL: URL
    let testPack: Bool
}

enum RemoteModelCatalogError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unsupportedSchema(Int)
    case invalidModel(String)
    case httpStatus(Int)
    case invalidSize(expected: Int64, actual: Int64)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Model catalog URL is invalid."
        case .invalidResponse: return "Model catalog response is invalid."
        case .unsupportedSchema(let version): return "Unsupported model catalog schema: \(version)."
        case .invalidModel(let id): return "Model catalog entry is invalid: \(id)."
        case .httpStatus(let status): return "Model download failed with HTTP \(status)."
        case .invalidSize(let expected, let actual):
            return "Model size mismatch. Expected \(expected), got \(actual)."
        case .checksumMismatch(let expected, let actual):
            return "Model SHA-256 mismatch. Expected \(expected), got \(actual)."
        }
    }
}

enum RemoteModelCatalogClient {
    static let catalogURL = URL(string: "https://raw.githubusercontent.com/hgblue09124-code/PersonalAgent-iOS/main/RemoteCatalog/models.json")!

    static func fetch() async throws -> RemoteModelCatalog {
        let (data, response) = try await URLSession.shared.data(from: catalogURL)
        guard let http = response as? HTTPURLResponse else {
            throw RemoteModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteModelCatalogError.httpStatus(http.statusCode)
        }

        let catalog = try JSONDecoder().decode(RemoteModelCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else {
            throw RemoteModelCatalogError.unsupportedSchema(catalog.schemaVersion)
        }
        guard !catalog.models.isEmpty else {
            throw RemoteModelCatalogError.invalidResponse
        }
        for model in catalog.models {
            guard !model.id.isEmpty, !model.filename.isEmpty,
                  !model.sha256.isEmpty, model.sizeBytes > 0 else {
                throw RemoteModelCatalogError.invalidModel(model.id)
            }
        }
        return catalog
    }

    static func download(_ model: RemoteModel) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: model.downloadURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RemoteModelCatalogError.httpStatus(http.statusCode)
        }

        let actualSize = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size] as? Int64 ?? 0
        guard actualSize == model.sizeBytes else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw RemoteModelCatalogError.invalidSize(expected: model.sizeBytes, actual: actualSize)
        }

        let actualHash = try sha256(of: temporaryURL)
        guard actualHash.caseInsensitiveCompare(model.sha256) == .orderedSame else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw RemoteModelCatalogError.checksumMismatch(expected: model.sha256, actual: actualHash)
        }

        return temporaryURL
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
