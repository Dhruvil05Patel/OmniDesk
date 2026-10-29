//
//  SafetyPolicyGate.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation
import Combine
import SwiftUI

/// Holds state for an action awaiting user approval.
public struct PendingConfirmationRequest: Identifiable {
    public let id: UUID
    public let connectorId: String
    public let toolName: String
    public let arguments: [String: Any]
    public let riskLevel: ActionRiskLevel
    public let descriptionText: String
    public let timestamp: Date
    fileprivate let continuation: CheckedContinuation<Bool, Never>
    
    public init(
        id: UUID = UUID(),
        connectorId: String,
        toolName: String,
        arguments: [String: Any],
        riskLevel: ActionRiskLevel,
        descriptionText: String,
        timestamp: Date = Date(),
        continuation: CheckedContinuation<Bool, Never>
    ) {
        self.id = id
        self.connectorId = connectorId
        self.toolName = toolName
        self.arguments = arguments
        self.riskLevel = riskLevel
        self.descriptionText = descriptionText
        self.timestamp = timestamp
        self.continuation = continuation
    }
}

/// Central Zero-Trust Policy Gate that halts execution and prompts the user
/// before any destructive, outbound, or high-risk tool action is performed.
@MainActor
public final class SafetyPolicyGate: ObservableObject {
    
    public static let shared = SafetyPolicyGate()
    
    @Published public var activeRequest: PendingConfirmationRequest? = nil
    
    public var autoApproveReversibleActions: Bool = true
    
    public init() {}
    
    /// Evaluates action risk and prompts the user if required.
    public func evaluatePolicy(
        connector: any Connector,
        tool: ToolDefinition,
        arguments: [String: Any]
    ) async -> ActionApprovalStatus {
        switch tool.riskLevel {
        case .safeReadOnly:
            return .autoApproved
            
        case .reversibleWrite:
            return autoApproveReversibleActions ? .autoApproved : await promptUserConfirmation(connector: connector, tool: tool, arguments: arguments)
            
        case .destructiveOrOutbound:
            // Mandatory confirmation gate
            return await promptUserConfirmation(connector: connector, tool: tool, arguments: arguments)
        }
    }
    
    /// Presents a modal confirmation dialog to the user and awaits their decision.
    private func promptUserConfirmation(
        connector: any Connector,
        tool: ToolDefinition,
        arguments: [String: Any]
    ) async -> ActionApprovalStatus {
        let description = Self.formatActionDescription(tool: tool, arguments: arguments)
        
        // Cancel any existing pending confirmation to guarantee continuations never hang
        if let existing = self.activeRequest {
            self.activeRequest = nil
            existing.continuation.resume(returning: false)
        }
        
        let approved = await withCheckedContinuation { continuation in
            let request = PendingConfirmationRequest(
                connectorId: connector.id,
                toolName: tool.name,
                arguments: arguments,
                riskLevel: tool.riskLevel,
                descriptionText: description,
                continuation: continuation
            )
            self.activeRequest = request
        }
        
        self.activeRequest = nil
        return approved ? .userApproved : .userRejected
    }
    
    /// Called when the user clicks 'Authorize Action' in the confirmation modal.
    public func approveActiveRequest() {
        guard let req = activeRequest else { return }
        activeRequest = nil
        req.continuation.resume(returning: true)
    }
    
    /// Called when the user clicks 'Cancel' in the confirmation modal.
    public func rejectActiveRequest() {
        guard let req = activeRequest else { return }
        activeRequest = nil
        req.continuation.resume(returning: false)
    }
    
    public static func formatActionDescription(tool: ToolDefinition, arguments: [String: Any]) -> String {
        switch tool.name {
        case "mail_send_message":
            let to = arguments["recipient"] as? String ?? "unknown"
            let subject = arguments["subject"] as? String ?? ""
            return "Send outbound email to '\(to)' with subject '\(subject)'."
            
        case "apps_terminate":
            let app = arguments["app_name"] as? String ?? "target application"
            return "Terminate and close '\(app)'."
            
        case "apps_perform_ui_action":
            let app = arguments["app_name"] as? String ?? "target application"
            let control = arguments["element_title"] as? String ?? "control"
            return "Perform synthetic click on '\(control)' inside '\(app)'."
            
        default:
            return "Execute \(tool.name): \(tool.description)"
        }
    }
}
