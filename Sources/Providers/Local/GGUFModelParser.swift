import Foundation

/// GGUF value type representation.
public enum GGUFValueType: UInt32, Sendable {
    case uint8 = 0
    case int8 = 1
    case uint16 = 2
    case int16 = 3
    case uint32 = 4
    case int32 = 5
    case float32 = 6
    case bool = 7
    case string = 8
    case array = 9
    case uint64 = 10
    case int64 = 11
    case float64 = 12
}

/// GGUF metadata value.
public enum GGUFValue: Sendable, Equatable {
    case uint8(UInt8)
    case int8(Int8)
    case uint16(UInt16)
    case int16(Int16)
    case uint32(UInt32)
    case int32(Int32)
    case float32(Float)
    case bool(Bool)
    case string(String)
    case array([GGUFValue])
    case uint64(UInt64)
    case int64(Int64)
    case float64(Double)
}

/// Parsed GGUF metadata summary extracted from a model file.
public struct GGUFMetadataSummary: Sendable, Equatable {
    public let version: UInt32
    public let tensorCount: UInt64
    public let metadataKVCount: UInt64
    public let architecture: String?
    public let modelName: String?
    public let contextLength: Int?
    public let vocabulary: [String]

    public init(
        version: UInt32,
        tensorCount: UInt64,
        metadataKVCount: UInt64,
        architecture: String? = nil,
        modelName: String? = nil,
        contextLength: Int? = nil,
        vocabulary: [String] = []
    ) {
        self.version = version
        self.tensorCount = tensorCount
        self.metadataKVCount = metadataKVCount
        self.architecture = architecture
        self.modelName = modelName
        self.contextLength = contextLength
        self.vocabulary = vocabulary
    }
}

/// Binary GGUF parser for extracting metadata, vocabulary, and tensor specs from GGUF model files.
public struct GGUFModelParser: Sendable {
    public init() {}

    public func parseHeaderAndMetadata(at url: URL) throws -> GGUFMetadataSummary {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        // 1. Magic
        guard let magicData = try fileHandle.read(upToCount: 4), magicData.count == 4 else {
            throw LlamaCPPEngineError.invalidGGUFHeader("File too short for GGUF magic header")
        }

        guard let magicStr = String(data: magicData, encoding: .ascii), magicStr == "GGUF" else {
            let hexStr = magicData.map { String(format: "%02X", $0) }.joined()
            throw LlamaCPPEngineError.invalidGGUFHeader("Header magic '0x\(hexStr)' does not match GGUF magic 'GGUF'")
        }

        // 2. Version
        guard let versionData = try fileHandle.read(upToCount: 4), versionData.count == 4 else {
            throw LlamaCPPEngineError.invalidGGUFHeader("Missing GGUF version bytes")
        }
        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self) }

        // 3. Tensor count
        guard let tensorCountData = try fileHandle.read(upToCount: 8), tensorCountData.count == 8 else {
            throw LlamaCPPEngineError.invalidGGUFHeader("Missing GGUF tensor count")
        }
        let tensorCount = tensorCountData.withUnsafeBytes { $0.load(as: UInt64.self) }

        // 4. Metadata KV count
        guard let kvCountData = try fileHandle.read(upToCount: 8), kvCountData.count == 8 else {
            throw LlamaCPPEngineError.invalidGGUFHeader("Missing GGUF KV metadata count")
        }
        let kvCount = kvCountData.withUnsafeBytes { $0.load(as: UInt64.self) }

        var architecture: String?
        var modelName: String?
        var contextLength: Int?
        var vocabulary: [String] = []

        let safeKVCount = min(kvCount, 256)
        for _ in 0..<safeKVCount {
            guard let (key, value) = try? readKVPair(fileHandle: fileHandle) else {
                break
            }

            if key == "general.architecture", case .string(let val) = value {
                architecture = val
            } else if key == "general.name", case .string(let val) = value {
                modelName = val
            } else if (key == "llama.context_length" || key.hasSuffix(".context_length")), case .uint32(let val) = value {
                contextLength = Int(val)
            } else if (key == "llama.context_length" || key.hasSuffix(".context_length")), case .uint64(let val) = value {
                contextLength = Int(val)
            } else if key == "tokenizer.ggml.tokens", case .array(let arr) = value {
                vocabulary = arr.compactMap { item -> String? in
                    if case .string(let s) = item { return s }
                    return nil
                }
            }
        }

        return GGUFMetadataSummary(
            version: version,
            tensorCount: tensorCount,
            metadataKVCount: kvCount,
            architecture: architecture,
            modelName: modelName,
            contextLength: contextLength,
            vocabulary: vocabulary
        )
    }

    private func readKVPair(fileHandle: FileHandle) throws -> (String, GGUFValue)? {
        guard let key = try readString(fileHandle: fileHandle) else { return nil }
        guard let typeData = try fileHandle.read(upToCount: 4), typeData.count == 4 else { return nil }
        let rawType = typeData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard let valueType = GGUFValueType(rawValue: rawType) else { return nil }

        guard let value = try readValue(fileHandle: fileHandle, type: valueType) else { return nil }
        return (key, value)
    }

    private func readString(fileHandle: FileHandle) throws -> String? {
        guard let lenData = try fileHandle.read(upToCount: 8), lenData.count == 8 else { return nil }
        let len = lenData.withUnsafeBytes { $0.load(as: UInt64.self) }
        guard len < 10_000 else { return nil }
        guard let strData = try fileHandle.read(upToCount: Int(len)), strData.count == Int(len) else { return nil }
        return String(data: strData, encoding: .utf8)
    }

    private func readValue(fileHandle: FileHandle, type: GGUFValueType) throws -> GGUFValue? {
        switch type {
        case .uint8:
            guard let d = try fileHandle.read(upToCount: 1), d.count == 1 else { return nil }
            return .uint8(d[0])
        case .int8:
            guard let d = try fileHandle.read(upToCount: 1), d.count == 1 else { return nil }
            return .int8(Int8(bitPattern: d[0]))
        case .uint16:
            guard let d = try fileHandle.read(upToCount: 2), d.count == 2 else { return nil }
            return .uint16(d.withUnsafeBytes { $0.load(as: UInt16.self) })
        case .int16:
            guard let d = try fileHandle.read(upToCount: 2), d.count == 2 else { return nil }
            return .int16(d.withUnsafeBytes { $0.load(as: Int16.self) })
        case .uint32:
            guard let d = try fileHandle.read(upToCount: 4), d.count == 4 else { return nil }
            return .uint32(d.withUnsafeBytes { $0.load(as: UInt32.self) })
        case .int32:
            guard let d = try fileHandle.read(upToCount: 4), d.count == 4 else { return nil }
            return .int32(d.withUnsafeBytes { $0.load(as: Int32.self) })
        case .float32:
            guard let d = try fileHandle.read(upToCount: 4), d.count == 4 else { return nil }
            return .float32(d.withUnsafeBytes { $0.load(as: Float.self) })
        case .bool:
            guard let d = try fileHandle.read(upToCount: 1), d.count == 1 else { return nil }
            return .bool(d[0] != 0)
        case .string:
            guard let s = try readString(fileHandle: fileHandle) else { return nil }
            return .string(s)
        case .array:
            guard let itemTypeData = try fileHandle.read(upToCount: 4), itemTypeData.count == 4 else { return nil }
            let itemRawType = itemTypeData.withUnsafeBytes { $0.load(as: UInt32.self) }
            guard let itemType = GGUFValueType(rawValue: itemRawType) else { return nil }
            guard let lenData = try fileHandle.read(upToCount: 8), lenData.count == 8 else { return nil }
            let count = lenData.withUnsafeBytes { $0.load(as: UInt64.self) }

            var items: [GGUFValue] = []
            let safeCount = min(count, 32000)
            for _ in 0..<safeCount {
                guard let item = try readValue(fileHandle: fileHandle, type: itemType) else { break }
                items.append(item)
            }
            return .array(items)
        case .uint64:
            guard let d = try fileHandle.read(upToCount: 8), d.count == 8 else { return nil }
            return .uint64(d.withUnsafeBytes { $0.load(as: UInt64.self) })
        case .int64:
            guard let d = try fileHandle.read(upToCount: 8), d.count == 8 else { return nil }
            return .int64(d.withUnsafeBytes { $0.load(as: Int64.self) })
        case .float64:
            guard let d = try fileHandle.read(upToCount: 8), d.count == 8 else { return nil }
            return .float64(d.withUnsafeBytes { $0.load(as: Double.self) })
        }
    }
}
