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
    public var arguments: [String: Any]
    public let riskLevel: ActionRiskLevel
    public let descriptionText: String
    public let timestamp: Date
    public let allowsSessionWhitelist: Bool
    public var timeoutRemaining: Int
    public let timeoutTotal: Int
    fileprivate let continuation: CheckedContinuation<ApprovalDecisionResult, Never>
    
    public init(
        id: UUID = UUID(),
        connectorId: String,
        toolName: String,
        arguments: [String: Any],
        riskLevel: ActionRiskLevel,
        descriptionText: String,
        timestamp: Date = Date(),
        allowsSessionWhitelist: Bool = false,
        timeoutTotal: Int = 60,
        continuation: CheckedContinuation<ApprovalDecisionResult, Never>
    ) {
        self.id = id
        self.connectorId = connectorId
        self.toolName = toolName
        self.arguments = arguments
        self.riskLevel = riskLevel
        self.descriptionText = descriptionText
        self.timestamp = timestamp
        self.allowsSessionWhitelist = allowsSessionWhitelist
        self.timeoutTotal = timeoutTotal
        self.timeoutRemaining = timeoutTotal
        self.continuation = continuation
    }
}

/// The result returned from the SafetyPolicyGate approval decision.
public struct ApprovalDecisionResult: Sendable {
    public let status: ActionApprovalStatus
    public let modifiedArguments: [String: Any]?
    
    public init(status: ActionApprovalStatus, modifiedArguments: [String: Any]? = nil) {
        self.status = status
        self.modifiedArguments = modifiedArguments
    }
}

/// Central Zero-Trust Policy Gate that halts execution and prompts the user
/// before any destructive, outbound, or high-risk tool action is performed.
@MainActor
public final class SafetyPolicyGate: ObservableObject {
    
    public static let shared = SafetyPolicyGate()
    
    @Published public var activeRequest: PendingConfirmationRequest? = nil
    @Published public private(set) var sessionWhitelist: Set<String> = []
    
    public var autoApproveReversibleActions: Bool = false
    public var defaultTimeoutSeconds: Int = 60
    
    private var countdownTimer: Timer?
    private var requestQueue: [() -> Void] = []
    
    public init() {}
    
    /// Evaluates action risk and prompts the user if required.
    public func evaluatePolicy(
        connector: any Connector,
        tool: ToolDefinition,
        arguments: [String: Any]
    ) async -> ActionApprovalStatus {
        let key = "\(connector.id):\(tool.name)"
        
        switch tool.riskLevel {
        case .safeReadOnly:
            return .autoApproved
            
        case .reversibleWrite:
            if autoApproveReversibleActions || sessionWhitelist.contains(key) {
                return .sessionWhitelisted
            }
            let result = await promptUserConfirmation(connector: connector, tool: tool, arguments: arguments)
            return result.status
            
        case .destructiveOrOutbound:
            // Mandatory confirmation gate (session whitelist strictly forbidden)
            let result = await promptUserConfirmation(connector: connector, tool: tool, arguments: arguments)
            return result.status
        }
    }
    
    /// Presents a modal confirmation dialog to the user and awaits their decision.
    private func promptUserConfirmation(
        connector: any Connector,
        tool: ToolDefinition,
        arguments: [String: Any]
    ) async -> ApprovalDecisionResult {
        let description = Self.formatActionDescription(tool: tool, arguments: arguments)
        let allowsSession = (tool.riskLevel == .reversibleWrite)
        
        // Cancel any existing pending confirmation to guarantee continuations never hang
        if let existing = self.activeRequest {
            stopTimer()
            self.activeRequest = nil
            existing.continuation.resume(returning: ApprovalDecisionResult(status: .userRejected))
        }
        
        let result = await withCheckedContinuation { continuation in
            let request = PendingConfirmationRequest(
                connectorId: connector.id,
                toolName: tool.name,
                arguments: arguments,
                riskLevel: tool.riskLevel,
                descriptionText: description,
                allowsSessionWhitelist: allowsSession,
                timeoutTotal: defaultTimeoutSeconds,
                continuation: continuation
            )
            self.activeRequest = request
            self.startTimer()
        }
        
        stopTimer()
        self.activeRequest = nil
        return result
    }
    
    // MARK: - Timer & Timeout
    
    private func startTimer() {
        stopTimer()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard var req = self.activeRequest else {
                    self.stopTimer()
                    return
                }
                if req.timeoutRemaining > 1 {
                    req.timeoutRemaining -= 1
                    self.activeRequest = req
                } else {
                    self.rejectActiveRequest(timedOut: true)
                }
            }
        }
    }
    
    private func stopTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    // MARK: - Decision Handlers
    
    /// Resolves the active request with either approval or rejection.
    public func resolveActiveRequest(approved: Bool) {
        if approved {
            approveActiveRequest()
        } else {
            rejectActiveRequest(timedOut: false)
        }
    }
    
    /// Resolves the active request with modified arguments.
    public func resolveActiveRequestWithEdit(newArguments: [String: Any]) {
        guard let req = activeRequest else { return }
        stopTimer()
        activeRequest = nil
        req.continuation.resume(returning: ApprovalDecisionResult(status: .editedAndApproved, modifiedArguments: newArguments))
    }
    
    /// Called when the user clicks 'Authorize Action' in the confirmation modal.
    public func approveActiveRequest() {
        guard let req = activeRequest else { return }
        stopTimer()
        activeRequest = nil
        req.continuation.resume(returning: ApprovalDecisionResult(status: .userApproved))
    }
    
    /// Authorizes the action and caches approval for this tool for the remainder of the session.
    public func allowForSession() {
        guard let req = activeRequest else { return }
        if req.allowsSessionWhitelist {
            sessionWhitelist.insert("\(req.connectorId):\(req.toolName)")
            stopTimer()
            activeRequest = nil
            req.continuation.resume(returning: ApprovalDecisionResult(status: .sessionWhitelisted))
        } else {
            // Outbound or destructive actions cannot be session-whitelisted; standard approval only
            approveActiveRequest()
        }
    }
    
    /// Clears the ephemeral session approval cache.
    public func clearSessionWhitelist() {
        sessionWhitelist.removeAll()
    }
    
    /// Called when the user clicks 'Cancel' or the countdown timer expires.
    public func rejectActiveRequest(timedOut: Bool = false) {
        guard let req = activeRequest else { return }
        stopTimer()
        activeRequest = nil
        let status: ActionApprovalStatus = timedOut ? .timedOut : .userRejected
        req.continuation.resume(returning: ApprovalDecisionResult(status: status))
    }
    
    /// Aborts all active requests on application shutdown.
    public func abortAllPendingRequests() {
        stopTimer()
        if let req = activeRequest {
            activeRequest = nil
            req.continuation.resume(returning: ApprovalDecisionResult(status: .userRejected))
        }
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
