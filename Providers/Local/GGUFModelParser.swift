import Foundation

public struct GGUFMetadataSummary: Sendable, Equatable {
    public let version: UInt32
    public let tensorCount: UInt64
    public let metadataCount: UInt64
    public let architecture: String?
    public let contextLength: UInt64?

    public init(
        version: UInt32,
        tensorCount: UInt64,
        metadataCount: UInt64,
        architecture: String? = nil,
        contextLength: UInt64? = nil
    ) {
        self.version = version
        self.tensorCount = tensorCount
        self.metadataCount = metadataCount
        self.architecture = architecture
        self.contextLength = contextLength
    }
}

public enum GGUFParseError: Error, Sendable, Equatable {
    case invalidMagic(UInt32)
    case unsupportedVersion(UInt32)
    case truncatedFile
    case stringDecodingFailed
}

public final class GGUFModelParser: @unchecked Sendable {
    private static let ggufMagic: UInt32 = 0x46554747 // "GGUF" in little endian

    public init() {}

    public func parseHeaderAndMetadata(at url: URL) throws -> GGUFMetadataSummary {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        guard let headerData = try fileHandle.read(upToCount: 24), headerData.count >= 24 else {
            throw GGUFParseError.truncatedFile
        }

        let magic = headerData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard magic == Self.ggufMagic else {
            throw GGUFParseError.invalidMagic(magic)
        }

        let version = headerData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        guard version >= 2 && version <= 3 else {
            throw GGUFParseError.unsupportedVersion(version)
        }

        let tensorCount = headerData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        let metadataCount = headerData.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }

        var architecture: String?
        var contextLength: UInt64?

        for _ in 0..<min(metadataCount, 128) {
            guard let keyLengthData = try fileHandle.read(upToCount: 8), keyLengthData.count == 8 else { break }
            let keyLen = keyLengthData.withUnsafeBytes { $0.load(as: UInt64.self) }
            guard keyLen < 1024 else { break }

            guard let keyData = try fileHandle.read(upToCount: Int(keyLen)), keyData.count == Int(keyLen) else { break }
            guard let key = String(data: keyData, encoding: .utf8) else { break }

            guard let valTypeData = try fileHandle.read(upToCount: 4), valTypeData.count == 4 else { break }
            let valType = valTypeData.withUnsafeBytes { $0.load(as: UInt32.self) }

            switch valType {
            case 8: // String type
                guard let strLenData = try fileHandle.read(upToCount: 8), strLenData.count == 8 else { break }
                let strLen = strLenData.withUnsafeBytes { $0.load(as: UInt64.self) }
                guard strLen < 4096 else { break }
                guard let strData = try fileHandle.read(upToCount: Int(strLen)), strData.count == Int(strLen) else { break }
                if key == "general.architecture" {
                    architecture = String(data: strData, encoding: .utf8)
                }
            case 4, 5: // UInt32, Int32
                guard let intData = try fileHandle.read(upToCount: 4), intData.count == 4 else { break }
                let val = intData.withUnsafeBytes { $0.load(as: UInt32.self) }
                if key.contains("context_length") {
                    contextLength = UInt64(val)
                }
            case 6, 7: // UInt64, Int64
                guard let intData = try fileHandle.read(upToCount: 8), intData.count == 8 else { break }
                let val = intData.withUnsafeBytes { $0.load(as: UInt64.self) }
                if key.contains("context_length") {
                    contextLength = val
                }
            default:
                break
            }

            if architecture != nil && contextLength != nil {
                break
            }
        }

        return GGUFMetadataSummary(
            version: version,
            tensorCount: tensorCount,
            metadataCount: metadataCount,
            architecture: architecture,
            contextLength: contextLength
        )
    }
}
