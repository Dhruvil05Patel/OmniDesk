//
//  ActionHandler.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import Combine

/// Central coordinator that routes user intents and agent tool dispatches to registered connectors.
public final class ActionHandler: @unchecked Sendable {
    
    public static let shared = ActionHandler()
    
    public let policyGate: SafetyPolicyGate
    public let auditLogger: AuditLogger
    private var connectors: [String: any Connector] = [:]
    private let queue = DispatchQueue(label: "com.omnidesk.actionhandler", attributes: .concurrent)
    
    public init(
        policyGate: SafetyPolicyGate = .shared,
        auditLogger: AuditLogger = .shared
    ) {
        self.policyGate = policyGate
        self.auditLogger = auditLogger
        registerDefaultConnectors()
    }
    
    private func registerDefaultConnectors() {
        let calendar = CalendarConnector()
        register(connector: calendar)
        
        let obsidian = ObsidianConnector()
        register(connector: obsidian)
        
        let mail = MailConnector()
        register(connector: mail)
        
        let apps = AppControlConnector()
        register(connector: apps)
    }
    
    public func register(connector: any Connector) {
        queue.async(flags: .barrier) {
            self.connectors[connector.id] = connector
        }
    }
    
    public func connector(for id: String) -> (any Connector)? {
        queue.sync {
            self.connectors[id]
        }
    }
    
    public var allConnectors: [any Connector] {
        queue.sync {
            Array(self.connectors.values)
        }
    }
    
    /// Executes a tool on a specific connector by ID.
    public func executeTool(connectorId: String, toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        guard let connector = connector(for: connectorId) else {
            throw ConnectorError.targetNotFound(identifier: "Connector '\(connectorId)' is not registered.")
        }
        guard let toolDef = connector.tools.first(where: { $0.name == toolName }) else {
            throw ConnectorError.targetNotFound(identifier: "Tool '\(toolName)' not found in connector '\(connectorId)'.")
        }
        return try await executeWithPolicy(connector: connector, tool: toolDef, arguments: arguments)
    }
    
    /// Dispatches a tool by its global name across all registered connectors.
    public func dispatchTool(named toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        let active = allConnectors
        for connector in active {
            if let toolDef = connector.tools.first(where: { $0.name == toolName }) {
                return try await executeWithPolicy(connector: connector, tool: toolDef, arguments: arguments)
            }
        }
        throw ConnectorError.targetNotFound(identifier: "No connector provides tool '\(toolName)'")
    }
    
    private func executeWithPolicy(
        connector: any Connector,
        tool: ToolDefinition,
        arguments: [String: Any]
    ) async throws -> ToolResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let approval = await policyGate.evaluatePolicy(
            connector: connector,
            tool: tool,
            arguments: arguments
        )
        
        guard approval == .autoApproved || approval == .userApproved else {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            auditLogger.record(
                connectorId: connector.id,
                toolName: tool.name,
                arguments: arguments,
                riskLevel: tool.riskLevel,
                approvalStatus: .userRejected,
                durationMs: duration,
                success: false,
                errorMessage: "Action rejected by user."
            )
            throw ConnectorError.destructiveActionRejectedByUser
        }
        
        do {
            let result = try await connector.execute(toolName: tool.name, arguments: arguments)
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            auditLogger.record(
                connectorId: connector.id,
                toolName: tool.name,
                arguments: arguments,
                riskLevel: tool.riskLevel,
                approvalStatus: approval,
                durationMs: duration,
                success: result.success,
                errorMessage: result.error
            )
            return result
        } catch {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            auditLogger.record(
                connectorId: connector.id,
                toolName: tool.name,
                arguments: arguments,
                riskLevel: tool.riskLevel,
                approvalStatus: approval,
                durationMs: duration,
                success: false,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }
    
    // MARK: - Voice & AI Intent Dispatch Bridge
    
    @discardableResult
    public static func handle(response: AIResponse, handler: ActionHandler = .shared) async throws -> ToolResult? {
        switch response.intent {
        case "send_email":
            let recipient = response.recipient ?? "user@example.com"
            let subject = response.subject ?? response.title ?? "Message from OmniDesk"
            let body = response.body ?? response.title ?? ""
            return try await handler.dispatchTool(
                named: "mail_send_message",
                arguments: [
                    "recipient": recipient,
                    "subject": subject,
                    "body": body
                ]
            )
            
        case "create_email_draft":
            let recipient = response.recipient ?? "user@example.com"
            let subject = response.subject ?? response.title ?? "Draft"
            let body = response.body ?? ""
            return try await handler.dispatchTool(
                named: "mail_create_draft",
                arguments: [
                    "recipient": recipient,
                    "subject": subject,
                    "body": body
                ]
            )
            
        case "close_app", "terminate_app":
            let app = response.appName ?? response.title ?? ""
            return try await handler.dispatchTool(
                named: "apps_terminate",
                arguments: ["app_name": app]
            )
            
        case "launch_app":
            let app = response.appName ?? response.title ?? ""
            return try await handler.dispatchTool(
                named: "apps_launch_or_focus",
                arguments: ["app_name": app]
            )
            
        case "create_calendar_event":
            let title = response.title ?? "New Event"
            var args: [String: Any] = ["title": title]
            if let date = response.date {
                let time = response.time ?? "09:00"
                args["start_time"] = "\(date)T\(time):00"
            }
            return try await handler.dispatchTool(
                named: "calendar_create_event",
                arguments: args
            )
            
        case "create_note":
            let title = response.title ?? "Note"
            let body = response.body ?? response.title ?? ""
            return try await handler.dispatchTool(
                named: "obsidian_create_note",
                arguments: [
                    "path": "\(title).md",
                    "content": body
                ]
            )
            
        case "create_task":
            return ToolResult.success(message: "Stored as task: \(response.title ?? "")")
            
        default:
            print("Unhandled intent:", response.intent)
            return nil
        }
    }
}
