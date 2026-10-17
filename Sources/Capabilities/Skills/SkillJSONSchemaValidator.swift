import Foundation
import CoreFoundation
import PAKernel

/// Strict, dependency-free validator for the JSON Schema subset accepted by Skill manifests.
/// Unsupported validation keywords fail closed rather than silently weakening a contract.
enum SkillJSONSchemaValidator {
    private static let supportedKeywords: Set<String> = [
        "$schema", "$id", "title", "description", "default", "examples",
        "type", "enum", "const", "required", "properties", "additionalProperties",
        "items", "minLength", "maxLength", "minimum", "maximum", "minItems", "maxItems"
    ]

    static func validate(inputJSON: String, schema: SchemaDocument) throws {
        guard
            let schemaData = schema.rawJSON.data(using: .utf8),
            let rawSchema = try? JSONSerialization.jsonObject(with: schemaData, options: [.fragmentsAllowed]),
            let schemaObject = rawSchema as? [String: Any],
            let inputData = inputJSON.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: inputData, options: [.fragmentsAllowed])
        else {
            throw SkillExecutionError.malformedSkill
        }
        try validate(value: value, against: schemaObject)
    }

    private static func validate(value: Any, against schema: [String: Any]) throws {
        guard schema.keys.allSatisfy(supportedKeywords.contains) else {
            throw SkillExecutionError.malformedSkill
        }

        if let rawType = schema["type"] {
            guard let type = rawType as? String, matches(value, type: type) else {
                throw SkillExecutionError.malformedSkill
            }
        }

        if let rawEnum = schema["enum"] {
            guard let values = rawEnum as? [Any], !values.isEmpty,
                  try values.contains(where: { try canonicalJSON($0) == canonicalJSON(value) }) else {
                throw SkillExecutionError.malformedSkill
            }
        }
        if let constant = schema["const"], try canonicalJSON(constant) != canonicalJSON(value) {
            throw SkillExecutionError.malformedSkill
        }

        if let rawRequired = schema["required"] {
            guard let required = rawRequired as? [String], let object = value as? [String: Any],
                  required.allSatisfy({ object[$0] != nil }) else {
                throw SkillExecutionError.malformedSkill
            }
        }

        if schema["properties"] != nil || schema["additionalProperties"] != nil {
            guard let object = value as? [String: Any] else {
                throw SkillExecutionError.malformedSkill
            }
            let properties: [String: Any]
            if let rawProperties = schema["properties"] {
                guard let decoded = rawProperties as? [String: Any] else {
                    throw SkillExecutionError.malformedSkill
                }
                properties = decoded
            } else {
                properties = [:]
            }
            for (key, rawPropertySchema) in properties where object[key] != nil {
                guard let propertySchema = rawPropertySchema as? [String: Any] else {
                    throw SkillExecutionError.malformedSkill
                }
                try validate(value: object[key]!, against: propertySchema)
            }
            if let additional = schema["additionalProperties"] {
                if let allowsAdditional = boolean(additional), !allowsAdditional {
                    guard object.keys.allSatisfy({ properties[$0] != nil }) else {
                        throw SkillExecutionError.malformedSkill
                    }
                } else if let additionalSchema = additional as? [String: Any] {
                    for (key, extraValue) in object where properties[key] == nil {
                        try validate(value: extraValue, against: additionalSchema)
                    }
                } else if boolean(additional) == nil {
                    throw SkillExecutionError.malformedSkill
                }
            }
        }

        if let rawItems = schema["items"] {
            guard let itemSchema = rawItems as? [String: Any], let array = value as? [Any] else {
                throw SkillExecutionError.malformedSkill
            }
            for item in array {
                try validate(value: item, against: itemSchema)
            }
        }

        if let rawMinLength = schema["minLength"] {
            guard let minLength = integer(rawMinLength), minLength >= 0, let string = value as? String,
                  string.unicodeScalars.count >= minLength else {
                throw SkillExecutionError.malformedSkill
            }
        }
        if let rawMaxLength = schema["maxLength"] {
            guard let maxLength = integer(rawMaxLength), maxLength >= 0, let string = value as? String,
                  string.unicodeScalars.count <= maxLength else {
                throw SkillExecutionError.malformedSkill
            }
        }
        if let rawMinItems = schema["minItems"] {
            guard let minItems = integer(rawMinItems), minItems >= 0, let array = value as? [Any],
                  array.count >= minItems else {
                throw SkillExecutionError.malformedSkill
            }
        }
        if let rawMaxItems = schema["maxItems"] {
            guard let maxItems = integer(rawMaxItems), maxItems >= 0, let array = value as? [Any],
                  array.count <= maxItems else {
                throw SkillExecutionError.malformedSkill
            }
        }
        if let rawMinimum = schema["minimum"] {
            guard let minimum = number(rawMinimum), let valueNumber = number(value),
                  valueNumber.doubleValue >= minimum.doubleValue else {
                throw SkillExecutionError.malformedSkill
            }
        }
        if let rawMaximum = schema["maximum"] {
            guard let maximum = number(rawMaximum), let valueNumber = number(value),
                  valueNumber.doubleValue <= maximum.doubleValue else {
                throw SkillExecutionError.malformedSkill
            }
        }
    }

    private static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return boolean(value) != nil
        case "null": return value is NSNull
        case "number": return number(value) != nil
        case "integer":
            guard let value = number(value) else { return false }
            return value.doubleValue.isFinite && value.doubleValue.rounded(.towardZero) == value.doubleValue
        default: return false
        }
    }

    private static func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func number(_ value: Any) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }

    private static func integer(_ value: Any) -> Int? {
        guard let number = number(value), number.doubleValue.isFinite,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else {
            return nil
        }
        return number.intValue
    }

    private static func canonicalJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}
