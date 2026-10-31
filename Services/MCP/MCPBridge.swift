//
//  MCPBridge.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation

// MARK: - JSON-RPC 2.0 Models

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: AnyCodableValue?
    public let method: String
    public let params: [String: AnyCodableValue]?
    
    public init(jsonrpc: String = "2.0", id: AnyCodableValue? = nil, method: String, params: [String: AnyCodableValue]? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: AnyCodableValue?
    public let result: AnyCodableValue?
    public let error: JSONRPCError?
    
    public init(jsonrpc: String = "2.0", id: AnyCodableValue? = nil, result: AnyCodableValue? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
    
    public static func success(id: AnyCodableValue?, result: AnyCodableValue) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: result, error: nil)
    }
    
    public static func error(id: AnyCodableValue?, code: Int, message: String, data: AnyCodableValue? = nil) -> JSONRPCResponse {
        JSONRPCResponse(jsonrpc: "2.0", id: id, result: nil, error: JSONRPCError(code: code, message: message, data: data))
    }
}

public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodableValue?
    
    public init(code: Int, message: String, data: AnyCodableValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - MCP Server Bridge Engine

/// Native Model Context Protocol (MCP) server engine.
/// Exposes OmniDesk's local connectors as standardized MCP tools via JSON-RPC 2.0.
public final class MCPServerBridge: Sendable {
    
    public let actionHandler: ActionHandler
    public let policyGate: SafetyPolicyGate
    public let auditLogger: AuditLogger
    
    @MainActor
    public init(
        actionHandler: ActionHandler = .shared,
        policyGate: SafetyPolicyGate = .shared,
        auditLogger: AuditLogger = .shared
    ) {
        self.actionHandler = actionHandler
        self.policyGate = policyGate
        self.auditLogger = auditLogger
    }
    
    /// Processes a raw JSON-RPC 2.0 string message and returns the serialized JSON response.
    public func processMessage(_ inputJSON: String) async -> String {
        guard let data = inputJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return serializeResponse(.error(id: nil, code: -32700, message: "Parse error"))
        }
        
        guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
            return serializeResponse(.error(id: nil, code: -32600, message: "Invalid Request"))
        }
        
        let response = await handleRequest(request)
        return serializeResponse(response)
    }
    
    /// Handles a decoded JSON-RPC request according to MCP protocol specifications.
    public func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(id: request.id)
            
        case "notifications/initialized":
            return .success(id: request.id, result: .bool(true))
            
        case "tools/list":
            return handleToolsList(id: request.id)
            
        case "tools/call":
            return await handleToolsCall(id: request.id, params: request.params)
            
        case "ping":
            return .success(id: request.id, result: .dictionary([:]))
            
        default:
            return .error(id: request.id, code: -32601, message: "Method not found: \(request.method)")
        }
    }
    
    // MARK: - Method Handlers
    
    private func handleInitialize(id: AnyCodableValue?) -> JSONRPCResponse {
        let serverInfo: [String: AnyCodableValue] = [
            "name": .string("omnidesk-native"),
            "version": .string("1.0.0")
        ]
        let capabilities: [String: AnyCodableValue] = [
            "tools": .dictionary([
                "listChanged": .bool(false)
            ])
        ]
        
        return .success(
            id: id,
            result: .dictionary([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .dictionary(capabilities),
                "serverInfo": .dictionary(serverInfo)
            ])
        )
    }
    
    private func handleToolsList(id: AnyCodableValue?) -> JSONRPCResponse {
        var mcpTools: [AnyCodableValue] = []
        
        for connector in actionHandler.allConnectors {
            for tool in connector.tools {
                var propsDict: [String: AnyCodableValue] = [:]
                if let props = tool.parameters.properties {
                    for (propKey, propVal) in props {
                        propsDict[propKey] = .dictionary([
                            "type": .string(propVal.type),
                            "description": .string(propVal.description)
                        ])
                    }
                }
                
                let reqList = tool.parameters.required ?? []
                let schemaDict: [String: AnyCodableValue] = [
                    "type": .string("object"),
                    "description": .string(tool.parameters.description),
                    "properties": .dictionary(propsDict),
                    "required": .array(reqList.map { .string($0) })
                ]
                
                let toolObj: [String: AnyCodableValue] = [
                    "name": .string(tool.name),
                    "description": .string("[\(connector.displayName)] \(tool.description) (Risk: \(tool.riskLevel.rawValue))"),
                    "inputSchema": .dictionary(schemaDict)
                ]
                mcpTools.append(.dictionary(toolObj))
            }
        }
        
        return .success(
            id: id,
            result: .dictionary([
                "tools": .array(mcpTools)
            ])
        )
    }
    
    private func handleToolsCall(id: AnyCodableValue?, params: [String: AnyCodableValue]?) async -> JSONRPCResponse {
        guard let params = params,
              case .string(let toolName)? = params["name"] else {
            return .error(id: id, code: -32602, message: "Missing required parameter 'name'")
        }
        
        var argumentsDict: [String: Any] = [:]
        if case .dictionary(let args)? = params["arguments"] {
            for (k, v) in args {
                argumentsDict[k] = Self.unwrapAnyCodable(v)
            }
        }
        
        // Find connector providing this tool
        guard let connector = actionHandler.allConnectors.first(where: { $0.tools.contains(where: { $0.name == toolName }) }),
              let toolDef = connector.tools.first(where: { $0.name == toolName }) else {
            return .error(id: id, code: -32602, message: "Tool '\(toolName)' not found.")
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Policy Gate Evaluation
        let approval = await policyGate.evaluatePolicy(connector: connector, tool: toolDef, arguments: argumentsDict)
        guard approval == .autoApproved || approval == .userApproved else {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            auditLogger.record(
                connectorId: connector.id,
                toolName: toolName,
                arguments: argumentsDict,
                riskLevel: toolDef.riskLevel,
                approvalStatus: .userRejected,
                durationMs: duration,
                success: false,
                errorMessage: "Action rejected by user."
            )
            return .error(id: id, code: -32001, message: "Execution cancelled by user confirmation policy.")
        }
        
        // Execute Tool
        do {
            let toolResult = try await connector.execute(toolName: toolName, arguments: argumentsDict)
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            auditLogger.record(
                connectorId: connector.id,
                toolName: toolName,
                arguments: argumentsDict,
                riskLevel: toolDef.riskLevel,
                approvalStatus: approval,
                durationMs: duration,
                success: toolResult.success,
                errorMessage: toolResult.error
            )
            
            let messageText = toolResult.message ?? (toolResult.success ? "Success" : (toolResult.error ?? "Failed"))
            let contentList: [AnyCodableValue] = [
                .dictionary([
                    "type": .string("text"),
                    "text": .string(messageText)
                ])
            ]
            
            var resultDict: [String: AnyCodableValue] = [
                "content": .array(contentList),
                "isError": .bool(!toolResult.success)
            ]
            if let data = toolResult.data {
                resultDict["data"] = .dictionary(data)
            }
            
            return .success(id: id, result: .dictionary(resultDict))
        } catch {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            auditLogger.record(
                connectorId: connector.id,
                toolName: toolName,
                arguments: argumentsDict,
                riskLevel: toolDef.riskLevel,
                approvalStatus: approval,
                durationMs: duration,
                success: false,
                errorMessage: error.localizedDescription
            )
            return .error(id: id, code: -32000, message: "Tool execution failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    private func serializeResponse(_ response: JSONRPCResponse) -> String {
        guard let data = try? JSONEncoder().encode(response),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}"
        }
        return str
    }
    
    public static func unwrapAnyCodable(_ val: AnyCodableValue) -> Any {
        switch val {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map { unwrapAnyCodable($0) }
        case .dictionary(let d): return d.mapValues { unwrapAnyCodable($0) }
        case .null: return NSNull()
        }
    }
}
