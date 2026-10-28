import Foundation

/// A versioned, untrusted proposal received from the Python planning runtime.
///
/// This contract deliberately has no execute/authorize API. Swift must still route
/// accepted proposals through the existing Skill scope, Settings policy, Module
/// runtime, approval, and read-back verification boundaries.
public struct PythonAgentPlanEnvelope: Decodable, Sendable, Equatable {
    public struct Intent: Decodable, Sendable, Equatable {
        public enum Kind: String, Decodable, Sendable {
            case chat
            case createFile = "create_file"
            case unknown
        }

        public let kind: Kind
        public let normalizedText: String

        enum CodingKeys: String, CodingKey {
            case kind
            case normalizedText = "normalized_text"
        }
    }

    public enum Kind: String, Decodable, Sendable {
        case respond
        case clarify
        case proposeSkill = "propose_skill"
        case unsupported
    }

    /// JSON values accepted in proposal arguments. This is data only, never executable code.
    public enum JSONValue: Decodable, Sendable, Equatable {
        case string(String)
        case integer(Int)
        case number(Double)
        case boolean(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .boolean(value)
            } else if let value = try? container.decode(Int.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
            }
        }
    }

    public let schemaVersion: Int
    public let kind: Kind
    public let intent: Intent
    public let message: String
    public let missingFields: [String]
    public let skillID: String?
    public let arguments: [String: JSONValue]
    public let isExecutable: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case kind
        case intent
        case message
        case missingFields = "missing_fields"
        case skillID = "skill_id"
        case arguments
        case isExecutable = "is_executable"
    }

    public static let supportedSchemaVersion = 1
    private static let maximumTextLength = 16_384
    private static let maximumMessageLength = 4_096
    private static let maximumFileContentLength = 1_048_576

    public static func decode(_ data: Data) throws -> Self {
        let envelope: Self
        do {
            envelope = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw PythonAgentBridgeError.malformedPayload
        }
        try envelope.validate()
        return envelope
    }

    public func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw PythonAgentBridgeError.unsupportedSchemaVersion(schemaVersion)
        }
        // Python is a planner, never an authority. Reject even a well-formed
        // envelope that tries to label itself executable.
        guard !isExecutable else {
            throw PythonAgentBridgeError.executablePlanRejected
        }
        guard intent.normalizedText.count <= Self.maximumTextLength,
              message.count <= Self.maximumMessageLength,
              missingFields.count <= 8,
              Set(missingFields).count == missingFields.count,
              missingFields.allSatisfy({ !$0.isEmpty && $0.count <= 64 }) else {
            throw PythonAgentBridgeError.invalidPlan
        }

        if kind == .proposeSkill {
            guard intent.kind == .createFile,
                  skillID == "workspace.create-file",
                  Set(arguments.keys) == Set(["path", "content"]),
                  missingFields.isEmpty,
                  case .string(let path)? = arguments["path"],
                  case .string(let content)? = arguments["content"],
                  Self.isAllowedWorkspacePath(path),
                  content.count <= Self.maximumFileContentLength else {
                throw PythonAgentBridgeError.invalidPlan
            }
        } else {
            // Clarification, chat, and unsupported plans must not smuggle tool data.
            guard skillID == nil, arguments.isEmpty else {
                throw PythonAgentBridgeError.invalidPlan
            }
        }
    }

    private static func isAllowedWorkspacePath(_ path: String) -> Bool {
        guard path.count <= 512,
              path.hasPrefix("workspace/"),
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count >= 2
            && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

public enum PythonAgentBridgeError: Error, Sendable, Equatable {
    case malformedPayload
    case unsupportedSchemaVersion(Int)
    case executablePlanRejected
    case invalidPlan
}
