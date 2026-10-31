//
//  ConnectorProtocol.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation

/// Represents the classification level of a tool action for safety policy evaluation.
public enum ActionRiskLevel: String, Codable, Sendable {
    case safeReadOnly           // No state changes (e.g. search, read, check availability)
    case reversibleWrite        // Low impact state changes (e.g. create draft, append note)
    case destructiveOrOutbound  // High impact (e.g. send email, delete event, UI click, quit app)
}

/// Typed representation of a parameter schema following JSON Schema standards.
public struct ToolParameterSchema: Codable, Sendable {
    public let type: String
    public let description: String
    public let properties: [String: ToolProperty]?
    public let required: [String]?
    
    public init(type: String = "object", description: String, properties: [String: ToolProperty]?, required: [String]?) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
    }
}

public struct ToolProperty: Codable, Sendable {
    public let type: String
    public let description: String
    public let items: [String: String]? // For array types
    
    public init(type: String, description: String, items: [String: String]? = nil) {
        self.type = type
        self.description = description
        self.items = items
    }
}

/// Metadata describing a specific tool exposed by a connector.
public struct ToolDefinition: Identifiable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let riskLevel: ActionRiskLevel
    public let parameters: ToolParameterSchema
    
    public init(name: String, description: String, riskLevel: ActionRiskLevel, parameters: ToolParameterSchema) {
        self.name = name
        self.description = description
        self.riskLevel = riskLevel
        self.parameters = parameters
    }
}

/// Type-erased JSON-compatible value representation for structured responses.
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null
    
    public init(_ value: Any?) {
        guard let value = value else {
            self = .null
            return
        }
        
        switch value {
        case let str as String:
            self = .string(str)
        case let int as Int:
            self = .int(int)
        case let dbl as Double:
            self = .double(dbl)
        case let bool as Bool:
            self = .bool(bool)
        case let arr as [Any]:
            self = .array(arr.map { AnyCodableValue($0) })
        case let dict as [String: Any]:
            self = .dictionary(dict.mapValues { AnyCodableValue($0) })
        default:
            self = .string(String(describing: value))
        }
    }
    
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: AnyCodableValue] = [:]
            for key in container.allKeys {
                dict[key.stringValue] = try container.decode(AnyCodableValue.self, forKey: key)
            }
            self = .dictionary(dict)
            return
        }
        
        if var container = try? decoder.unkeyedContainer() {
            var array: [AnyCodableValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(AnyCodableValue.self))
            }
            self = .array(array)
            return
        }
        
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let dbl = try? container.decode(Double.self) {
            self = .double(dbl)
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported AnyCodableValue payload")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var container = encoder.singleValueContainer()
            try container.encode(s)
        case .int(let i):
            var container = encoder.singleValueContainer()
            try container.encode(i)
        case .double(let d):
            var container = encoder.singleValueContainer()
            try container.encode(d)
        case .bool(let b):
            var container = encoder.singleValueContainer()
            try container.encode(b)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .array(let arr):
            var container = encoder.unkeyedContainer()
            for item in arr {
                try container.encode(item)
            }
        case .dictionary(let dict):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, val) in dict {
                guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
                try container.encode(val, forKey: codingKey)
            }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Execution outcome returned by a connector tool.
public struct ToolResult: Codable, Sendable {
    public let success: Bool
    public let data: [String: AnyCodableValue]?
    public let message: String?
    public let error: String?
    
    public init(success: Bool, data: [String: AnyCodableValue]? = nil, message: String? = nil, error: String? = nil) {
        self.success = success
        self.data = data
        self.message = message
        self.error = error
    }
    
    public static func success(data: [String: AnyCodableValue]? = nil, message: String? = nil) -> ToolResult {
        ToolResult(success: true, data: data, message: message, error: nil)
    }
    
    public static func failure(error: String) -> ToolResult {
        ToolResult(success: false, data: nil, message: nil, error: error)
    }
}

public enum ConnectorPermissionStatus: String, Codable, Sendable {
    case authorized
    case denied
    case notDetermined
    case restricted
    case requiresFullDiskAccess
}

public enum ConnectorError: LocalizedError, Sendable {
    case permissionDenied(reason: String)
    case targetNotFound(identifier: String)
    case executionTimeout(toolName: String, seconds: Double)
    case invalidArguments(details: String)
    case destructiveActionRejectedByUser
    case systemFailure(underlyingMessage: String)
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let reason):
            return "Permission Denied: \(reason)"
        case .targetNotFound(let id):
            return "Target Not Found: \(id)"
        case .executionTimeout(let tool, let s):
            return "Tool '\(tool)' timed out after \(s)s"
        case .invalidArguments(let details):
            return "Invalid Arguments: \(details)"
        case .destructiveActionRejectedByUser:
            return "Action was cancelled by user confirmation policy."
        case .systemFailure(let msg):
            return "System Error: \(msg)"
        }
    }
}

/// The unified protocol that every native connector must implement.
public protocol Connector: AnyObject, Sendable {
    /// Unique identifier for the connector (e.g. "com.omnidesk.calendar")
    var id: String { get }
    
    /// User-friendly display name
    var displayName: String { get }
    
    /// Description of capabilities
    var connectorDescription: String { get }
    
    /// List of tools provided by this connector
    var tools: [ToolDefinition] { get }
    
    /// Verifies whether the required TCC and system permissions are active
    func checkPermissionState() async -> ConnectorPermissionStatus
    
    /// Requests necessary system permissions from the OS
    func requestPermissions() async -> Bool
    
    /// Executes a tool provided by this connector
    func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult
}
