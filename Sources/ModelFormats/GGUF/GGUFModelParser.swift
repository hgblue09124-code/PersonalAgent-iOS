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
    case invalidContextLength
}

public final class GGUFModelParser: @unchecked Sendable {
    private static let ggufMagic: UInt32 = 0x46554747 // "GGUF" in little endian
    private static let maximumKeyLength: UInt64 = 1_024
    private static let maximumArrayElements: UInt64 = 2_000_000
    private static let maximumArrayDepth = 8
    private static let maximumContextLength: UInt64 = 1_048_576

    public init() {}

    public func parseHeaderAndMetadata(at url: URL) throws -> GGUFMetadataSummary {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.uint64Value >= 24 else {
            throw GGUFParseError.truncatedFile
        }
        let fileSize = size.uint64Value
        let headerData = try Self.readExactly(fileHandle, count: 24)

        let magic = Self.integer(in: headerData, at: 0, as: UInt32.self)
        guard magic == Self.ggufMagic else {
            throw GGUFParseError.invalidMagic(magic)
        }

        let version = Self.integer(in: headerData, at: 4, as: UInt32.self)
        guard (2...3).contains(version) else {
            throw GGUFParseError.unsupportedVersion(version)
        }

        let tensorCount = Self.integer(in: headerData, at: 8, as: UInt64.self)
        let metadataCount = Self.integer(in: headerData, at: 16, as: UInt64.self)
        // Every key/value pair needs at least a length, a key byte, and a type.
        guard metadataCount <= fileSize / 13 else {
            throw GGUFParseError.truncatedFile
        }

        var architecture: String?
        var contextLength: UInt64?

        for _ in 0..<metadataCount {
            let keyLength = try Self.readInteger(fileHandle, as: UInt64.self)
            guard keyLength <= Self.maximumKeyLength else {
                throw GGUFParseError.truncatedFile
            }
            let keyData = try Self.readExactly(fileHandle, count: Int(keyLength))
            guard let key = String(data: keyData, encoding: .utf8) else {
                throw GGUFParseError.stringDecodingFailed
            }
            let valueType = try Self.readInteger(fileHandle, as: UInt32.self)

            switch valueType {
            case 8: // GGUF string
                let value = try Self.readString(fileHandle, fileSize: fileSize)
                if key == "general.architecture" {
                    architecture = value
                }
            case 4, 5: // UINT32 / INT32
                let value = try Self.readInteger(fileHandle, as: UInt32.self)
                if key.contains("context_length") {
                    let resolved: UInt64
                    if valueType == 5 {
                        let signed = Int32(bitPattern: value)
                        guard signed > 0 else { throw GGUFParseError.invalidContextLength }
                        resolved = UInt64(signed)
                    } else {
                        resolved = UInt64(value)
                    }
                    guard resolved > 0, resolved <= Self.maximumContextLength else { throw GGUFParseError.invalidContextLength }
                    contextLength = resolved
                }
            case 10, 11: // UINT64 / INT64
                let value = try Self.readInteger(fileHandle, as: UInt64.self)
                if key.contains("context_length") {
                    let resolved: UInt64
                    if valueType == 11 {
                        let signed = Int64(bitPattern: value)
                        guard signed > 0 else { throw GGUFParseError.invalidContextLength }
                        resolved = UInt64(signed)
                    } else {
                        resolved = value
                    }
                    guard resolved > 0, resolved <= UInt64(Int.max) else {
                        throw GGUFParseError.invalidContextLength
                    }
                    contextLength = resolved
                }
            default:
                try Self.skipValue(
                    type: valueType,
                    fileHandle: fileHandle,
                    fileSize: fileSize,
                    depth: 0
                )
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

    private static func readString(_ handle: FileHandle, fileSize: UInt64) throws -> String {
        let length = try readInteger(handle, as: UInt64.self)
        guard length <= fileSize, length <= UInt64(Int.max) else {
            throw GGUFParseError.truncatedFile
        }
        let data = try readExactly(handle, count: Int(length))
        guard let value = String(data: data, encoding: .utf8) else {
            throw GGUFParseError.stringDecodingFailed
        }
        return value
    }

    /// Skips a metadata value according to the GGUF scalar/array type table.
    /// In particular, arrays must be consumed so later metadata keys remain aligned.
    private static func skipValue(
        type: UInt32,
        fileHandle: FileHandle,
        fileSize: UInt64,
        depth: Int
    ) throws {
        switch type {
        case 0, 1, 7: // UINT8 / INT8 / BOOL
            try skipBytes(1, fileHandle: fileHandle, fileSize: fileSize)
        case 2, 3: // UINT16 / INT16
            try skipBytes(2, fileHandle: fileHandle, fileSize: fileSize)
        case 4, 5, 6: // UINT32 / INT32 / FLOAT32
            try skipBytes(4, fileHandle: fileHandle, fileSize: fileSize)
        case 8: // STRING
            let length = try readInteger(fileHandle, as: UInt64.self)
            try skipBytes(length, fileHandle: fileHandle, fileSize: fileSize)
        case 9: // ARRAY: element type, element count, then serialized values
            guard depth < maximumArrayDepth else {
                throw GGUFParseError.truncatedFile
            }
            let elementType = try readInteger(fileHandle, as: UInt32.self)
            let count = try readInteger(fileHandle, as: UInt64.self)
            guard count <= maximumArrayElements, count <= fileSize else {
                throw GGUFParseError.truncatedFile
            }
            for _ in 0..<count {
                try skipValue(
                    type: elementType,
                    fileHandle: fileHandle,
                    fileSize: fileSize,
                    depth: depth + 1
                )
            }
        case 10, 11, 12: // UINT64 / INT64 / FLOAT64
            try skipBytes(8, fileHandle: fileHandle, fileSize: fileSize)
        default:
            throw GGUFParseError.truncatedFile
        }
    }

    private static func skipBytes(
        _ count: UInt64,
        fileHandle: FileHandle,
        fileSize: UInt64
    ) throws {
        let offset = try fileHandle.offset()
        guard count <= fileSize, offset <= fileSize, count <= fileSize - offset else {
            throw GGUFParseError.truncatedFile
        }
        try fileHandle.seek(toOffset: offset + count)
    }

    private static func readInteger<T: FixedWidthInteger>(
        _ handle: FileHandle,
        as type: T.Type
    ) throws -> T {
        let data = try readExactly(handle, count: MemoryLayout<T>.size)
        return integer(in: data, at: 0, as: type)
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        guard count >= 0,
              let data = try handle.read(upToCount: count),
              data.count == count else {
            throw GGUFParseError.truncatedFile
        }
        return data
    }

    private static func integer<T: FixedWidthInteger>(
        in data: Data,
        at offset: Int,
        as type: T.Type
    ) -> T {
        data.withUnsafeBytes { bytes in
            T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
        }
    }
}
