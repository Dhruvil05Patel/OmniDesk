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
    
    private var connectors: [String: any Connector] = [:]
    private let queue = DispatchQueue(label: "com.omnidesk.actionhandler", attributes: .concurrent)
    
    public init() {
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
        return try await connector.execute(toolName: toolName, arguments: arguments)
    }
    
    /// Dispatches a tool by its global name across all registered connectors.
    public func dispatchTool(named toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        let active = allConnectors
        for connector in active {
            if connector.tools.contains(where: { $0.name == toolName }) {
                return try await connector.execute(toolName: toolName, arguments: arguments)
            }
        }
        throw ConnectorError.targetNotFound(identifier: "No connector provides tool '\(toolName)'")
    }
    
    // MARK: - Legacy Intent Bridge
    
    static func handle(response: AIResponse) {
        switch response.intent {
        case "create_calendar_event":
            if let title = response.title {
                CalendarService().createEvent(title: title, date: response.date ?? "")
            }
            
        case "create_task":
            print("Store as task:", response.title ?? "")
            
        default:
            print("Unknown intent:", response.intent)
        }
    }
}
