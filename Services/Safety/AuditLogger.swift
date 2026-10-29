//
//  AuditLogger.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation

/// Status of user authorization for an audited tool action.
public enum ActionApprovalStatus: String, Codable, Sendable {
    case autoApproved = "auto_approved"
    case userApproved = "user_approved"
    case userRejected = "user_rejected"
    case timedOut     = "timed_out"
}

/// A structured immutable record of an executed or attempted tool action.
public struct AuditLogEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let connectorId: String
    public let toolName: String
    public let parametersSummary: String
    public let riskLevel: ActionRiskLevel
    public let approvalStatus: ActionApprovalStatus
    public let durationMs: Double
    public let success: Bool
    public let errorMessage: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        connectorId: String,
        toolName: String,
        parametersSummary: String,
        riskLevel: ActionRiskLevel,
        approvalStatus: ActionApprovalStatus,
        durationMs: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.connectorId = connectorId
        self.toolName = toolName
        self.parametersSummary = parametersSummary
        self.riskLevel = riskLevel
        self.approvalStatus = approvalStatus
        self.durationMs = durationMs
        self.success = success
        self.errorMessage = errorMessage
    }
}

/// Thread-safe local audit logging system recording every tool invocation.
public final class AuditLogger: @unchecked Sendable {
    
    public static let shared = AuditLogger()
    
    private let queue = DispatchQueue(label: "com.omnidesk.auditlogger", attributes: .concurrent)
    private var inMemoryLogs: [AuditLogEntry] = []
    private let storageKey = "OmniDeskAuditLogs"
    private let maxEntries = 200
    
    public init() {
        loadPersistedLogs()
    }
    
    public func record(
        connectorId: String,
        toolName: String,
        arguments: [String: Any],
        riskLevel: ActionRiskLevel,
        approvalStatus: ActionApprovalStatus,
        durationMs: Double,
        success: Bool,
        errorMessage: String? = nil
    ) {
        let summary = Self.formatArgumentsSummary(arguments)
        let entry = AuditLogEntry(
            connectorId: connectorId,
            toolName: toolName,
            parametersSummary: summary,
            riskLevel: riskLevel,
            approvalStatus: approvalStatus,
            durationMs: durationMs,
            success: success,
            errorMessage: errorMessage
        )
        
        queue.async(flags: .barrier) {
            self.inMemoryLogs.insert(entry, at: 0)
            if self.inMemoryLogs.count > self.maxEntries {
                self.inMemoryLogs.removeLast(self.inMemoryLogs.count - self.maxEntries)
            }
            self.persistLogs()
        }
    }
    
    public func fetchRecentLogs(limit: Int = 50) -> [AuditLogEntry] {
        queue.sync {
            Array(self.inMemoryLogs.prefix(limit))
        }
    }
    
    public func clearAll() {
        queue.async(flags: .barrier) {
            self.inMemoryLogs.removeAll()
            UserDefaults.standard.removeObject(forKey: self.storageKey)
        }
    }
    
    // MARK: - Persistence & Formatting
    
    private func persistLogs() {
        if let encoded = try? JSONEncoder().encode(self.inMemoryLogs) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadPersistedLogs() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AuditLogEntry].self, from: data) {
            self.inMemoryLogs = decoded
        }
    }
    
    public static func formatArgumentsSummary(_ arguments: [String: Any]) -> String {
        guard !arguments.isEmpty else { return "{}" }
        let pairs = arguments.map { key, value in
            let desc = String(describing: value)
            let truncated = desc.count > 60 ? String(desc.prefix(57)) + "..." : desc
            return "\(key): \(truncated)"
        }
        return pairs.joined(separator: ", ")
    }
}
