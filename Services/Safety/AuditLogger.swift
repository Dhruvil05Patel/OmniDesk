//
//  AuditLogger.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation
import CryptoKit

/// Status of user authorization for an audited tool action.
public enum ActionApprovalStatus: String, Codable, Sendable {
    case autoApproved        = "auto_approved"
    case userApproved        = "user_approved"
    case userRejected        = "user_rejected"
    case editedAndApproved   = "edited_and_approved"
    case sessionWhitelisted  = "session_whitelisted"
    case timedOut            = "timed_out"
    
    public var isApproved: Bool {
        switch self {
        case .autoApproved, .userApproved, .sessionWhitelisted, .editedAndApproved:
            return true
        case .userRejected, .timedOut:
            return false
        }
    }
}

/// A structured immutable record of an executed or attempted tool action.
public struct AuditLogEntry: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let connectorId: String
    public let toolName: String
    public let parametersSummary: String
    public let payloadSha256: String
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
        payloadSha256: String = "",
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
        self.payloadSha256 = payloadSha256
        self.riskLevel = riskLevel
        self.approvalStatus = approvalStatus
        self.durationMs = durationMs
        self.success = success
        self.errorMessage = errorMessage
    }
}

/// Thread-safe local audit logging system recording every tool invocation to memory and ~/Library/Logs/OmniDesk/audit.jsonl.
public final class AuditLogger: @unchecked Sendable {
    
    public static let shared = AuditLogger()
    
    private let queue = DispatchQueue(label: "com.omnidesk.auditlogger", attributes: .concurrent)
    private var inMemoryLogs: [AuditLogEntry] = []
    private let storageKey = "OmniDeskAuditLogs"
    private let maxEntries = 200
    
    public let logFileURL: URL
    
    public init(customLogURL: URL? = nil) {
        if let custom = customLogURL {
            self.logFileURL = custom
        } else {
            let logsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("OmniDesk", isDirectory: true)
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            self.logFileURL = logsDir.appendingPathComponent("audit.jsonl")
        }
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
        let hash = Self.computeSha256(arguments)
        let entry = AuditLogEntry(
            connectorId: connectorId,
            toolName: toolName,
            parametersSummary: summary,
            payloadSha256: hash,
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
            self.appendToFile(entry: entry)
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
            try? FileManager.default.removeItem(at: self.logFileURL)
        }
    }
    
    // MARK: - Persistence & JSON Lines
    
    private func appendToFile(entry: AuditLogEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        
        if let lineData = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(lineData)
                    try? fileHandle.close()
                }
            } else {
                try? lineData.write(to: logFileURL, options: .atomic)
            }
        }
    }
    
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
    
    public static func computeSha256(_ arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) else {
            return "00000000"
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    public static func formatArgumentsSummary(_ arguments: [String: Any]) -> String {
        guard !arguments.isEmpty else { return "{}" }
        let pairs = arguments.sorted(by: { $0.key < $1.key }).map { key, value in
            let desc = String(describing: value)
            let truncated = desc.count > 60 ? String(desc.prefix(57)) + "..." : desc
            return "\(key): \(truncated)"
        }
        return pairs.joined(separator: ", ")
    }
}
