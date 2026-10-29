//
//  MailConnector.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation
import AppKit

/// Protocol abstracting AppleScript execution for testability and isolation.
public protocol AppleScriptRunnerProtocol: Sendable {
    func execute(script: String) throws -> String
}

/// Default implementation executing compiled AppleScript via NSAppleScript.
public final class SystemAppleScriptRunner: AppleScriptRunnerProtocol, @unchecked Sendable {
    public init() {}
    
    public func execute(script: String) throws -> String {
        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw ConnectorError.systemFailure(underlyingMessage: "Failed to initialize NSAppleScript instance.")
        }
        
        let descriptor = appleScript.executeAndReturnError(&errorDict)
        if let error = errorDict {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1
            
            // Error -1743: User denied automation permission
            if errorNumber == -1743 {
                throw ConnectorError.permissionDenied(reason: "User denied permission to automate Apple Mail.")
            }
            throw ConnectorError.systemFailure(underlyingMessage: "AppleScript Error (\(errorNumber)): \(message)")
        }
        
        return descriptor.stringValue ?? ""
    }
}

/// Native Apple Mail Connector.
/// Automates drafting, message searches, and outbound communications with strict prompt injection defense.
public final class MailConnector: Connector, @unchecked Sendable {
    
    public let id: String = "com.omnidesk.mail"
    public let displayName: String = "Apple Mail"
    public let connectorDescription: String = "Search communications, read messages, prepare drafts, and send emails via Apple Mail."
    
    public let runner: AppleScriptRunnerProtocol
    
    public init(runner: AppleScriptRunnerProtocol = SystemAppleScriptRunner()) {
        self.runner = runner
    }
    
    public var tools: [ToolDefinition] {
        [
            ToolDefinition(
                name: "mail_search_messages",
                description: "Searches messages in Apple Mail within a bounded date window (e.g. past 7 days) to find matching emails.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Search parameters",
                    properties: [
                        "query": ToolProperty(type: "string", description: "Keyword to search in subject or sender (e.g. 'Google', 'Interview', 'Offer')"),
                        "days_back": ToolProperty(type: "integer", description: "How many days in the past to search (default: 7, max: 30 to prevent timeout)"),
                        "limit": ToolProperty(type: "integer", description: "Maximum messages to return (default: 10)")
                    ],
                    required: ["query"]
                )
            ),
            ToolDefinition(
                name: "mail_read_message",
                description: "Retrieves the full content of an email message with prompt-injection sanitization.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Message identification",
                    properties: [
                        "message_id": ToolProperty(type: "string", description: "The Apple Mail message ID or subject/sender identifier")
                    ],
                    required: ["message_id"]
                )
            ),
            ToolDefinition(
                name: "mail_create_draft",
                description: "Prepares an email draft in Apple Mail without sending it, allowing user inspection.",
                riskLevel: .reversibleWrite,
                parameters: ToolParameterSchema(
                    description: "Draft composition details",
                    properties: [
                        "recipient": ToolProperty(type: "string", description: "Destination email address (e.g. 'recruiter@company.com')"),
                        "subject": ToolProperty(type: "string", description: "Email subject line"),
                        "body": ToolProperty(type: "string", description: "Plain text or formatted email body"),
                        "open_in_mail": ToolProperty(type: "boolean", description: "Whether to activate Mail and display the draft window (default: true)")
                    ],
                    required: ["recipient", "subject", "body"]
                )
            ),
            ToolDefinition(
                name: "mail_send_message",
                description: "Directly sends an email via Apple Mail. HIGH-RISK OUTBOUND ACTION: Requires interactive human approval.",
                riskLevel: .destructiveOrOutbound,
                parameters: ToolParameterSchema(
                    description: "Email dispatch details",
                    properties: [
                        "recipient": ToolProperty(type: "string", description: "Destination email address"),
                        "subject": ToolProperty(type: "string", description: "Email subject line"),
                        "body": ToolProperty(type: "string", description: "Email body text")
                    ],
                    required: ["recipient", "subject", "body"]
                )
            )
        ]
    }
    
    // MARK: - Permission Checking & Requesting
    
    public func checkPermissionState() async -> ConnectorPermissionStatus {
        // Quick probe script targeting Mail without UI disruption
        let probeScript = """
        tell application "Mail"
            return name
        end tell
        """
        do {
            _ = try runner.execute(script: probeScript)
            return .authorized
        } catch let ConnectorError.permissionDenied(reason) {
            _ = reason
            return .denied
        } catch {
            return .notDetermined
        }
    }
    
    public func requestPermissions() async -> Bool {
        let status = await checkPermissionState()
        return status == .authorized
    }
    
    // MARK: - Tool Dispatcher
    
    public func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        switch toolName {
        case "mail_search_messages":
            return try searchMessages(arguments: arguments)
            
        case "mail_read_message":
            return try readMessage(arguments: arguments)
            
        case "mail_create_draft":
            return try createDraft(arguments: arguments)
            
        case "mail_send_message":
            return try sendMessage(arguments: arguments)
            
        default:
            throw ConnectorError.targetNotFound(identifier: "Tool '\(toolName)' not found on \(displayName)")
        }
    }
    
    // MARK: - Tool Implementations
    
    private func searchMessages(arguments: [String: Any]) throws -> ToolResult {
        guard let query = arguments["query"] as? String, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConnectorError.invalidArguments(details: "query is required for mail_search_messages")
        }
        let daysBack = min(max(arguments["days_back"] as? Int ?? 7, 1), 30)
        let limit = min(max(arguments["limit"] as? Int ?? 10, 1), 50)
        
        let sanitizedQuery = Self.escapeAppleScriptString(query)
        let script = """
        set output to ""
        set queryText to "\(sanitizedQuery)"
        set cutOffDate to (current date) - (\(daysBack) * days)
        set matchCount to 0
        
        tell application "Mail"
            set targetMessages to (messages of inbox whose date received > cutOffDate)
            repeat with msg in targetMessages
                set msgSubject to (subject of msg as string)
                set msgSender to (sender of msg as string)
                set msgDate to (date received of msg as string)
                set msgId to (id of msg as string)
                
                if (msgSubject contains queryText) or (msgSender contains queryText) then
                    set output to output & msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "///"
                    set matchCount to matchCount + 1
                    if matchCount ≥ \(limit) then exit repeat
                end if
            end repeat
        end tell
        return output
        """
        
        let rawOutput = try runner.execute(script: script)
        let matches = Self.parseSearchOutput(rawOutput)
        
        let messageSummaries: [AnyCodableValue] = matches.map { match in
            .dictionary([
                "id": .string(match.id),
                "subject": .string(match.subject),
                "sender": .string(match.sender),
                "date": .string(match.date)
            ])
        }
        
        return .success(
            data: [
                "query": .string(query),
                "count": .int(matches.count),
                "messages": .array(messageSummaries)
            ],
            message: "Found \(matches.count) email(s) in the past \(daysBack) day(s)."
        )
    }
    
    private func readMessage(arguments: [String: Any]) throws -> ToolResult {
        guard let messageId = arguments["message_id"] as? String, !messageId.isEmpty else {
            throw ConnectorError.invalidArguments(details: "message_id is required for mail_read_message")
        }
        
        let cleanId = Self.escapeAppleScriptString(messageId)
        let script = """
        tell application "Mail"
            try
                set targetMsg to (first message of inbox whose id is "\(cleanId)")
                set msgSubject to (subject of targetMsg as string)
                set msgSender to (sender of targetMsg as string)
                set msgDate to (date received of targetMsg as string)
                set msgContent to (content of targetMsg as string)
                return msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & msgContent
            on error
                return "NOT_FOUND"
            end try
        end tell
        """
        
        let raw = try runner.execute(script: script)
        if raw == "NOT_FOUND" || raw.isEmpty {
            throw ConnectorError.targetNotFound(identifier: "Message with ID '\(messageId)' not found in Inbox.")
        }
        
        let parts = raw.components(separatedBy: "|||")
        let subject = parts.indices.contains(0) ? parts[0] : "Untitled"
        let sender = parts.indices.contains(1) ? parts[1] : ""
        let date = parts.indices.contains(2) ? parts[2] : ""
        let rawBody = parts.indices.contains(3) ? parts[3] : ""
        
        // Critical: Sanitize and encapsulate content against prompt injection
        let sanitizedBody = Self.sanitizeEmailContent(rawBody, messageId: messageId)
        
        return .success(
            data: [
                "message_id": .string(messageId),
                "subject": .string(subject),
                "sender": .string(sender),
                "date": .string(date),
                "body": .string(sanitizedBody)
            ],
            message: "Retrieved message '\(subject)'."
        )
    }
    
    private func createDraft(arguments: [String: Any]) throws -> ToolResult {
        guard let recipient = arguments["recipient"] as? String, Self.isValidEmail(recipient) else {
            throw ConnectorError.invalidArguments(details: "A valid recipient email address is required")
        }
        guard let subject = arguments["subject"] as? String, !subject.isEmpty else {
            throw ConnectorError.invalidArguments(details: "subject is required")
        }
        guard let body = arguments["body"] as? String else {
            throw ConnectorError.invalidArguments(details: "body is required")
        }
        let openInMail = arguments["open_in_mail"] as? Bool ?? true
        
        let cleanRecipient = Self.escapeAppleScriptString(recipient)
        let cleanSubject = Self.escapeAppleScriptString(subject)
        let cleanBody = Self.escapeAppleScriptString(body)
        
        let script = """
        tell application "Mail"
            set newMsg to make new outgoing message with properties {subject:"\(cleanSubject)", content:"\(cleanBody)", visible:\(openInMail)}
            tell newMsg
                make new to recipient at end of to recipients with properties {address:"\(cleanRecipient)"}
            end tell
            save newMsg
            \(openInMail ? "activate" : "")
            return "DRAFT_CREATED"
        end tell
        """
        
        _ = try runner.execute(script: script)
        return .success(
            data: [
                "recipient": .string(recipient),
                "subject": .string(subject)
            ],
            message: "Draft email to '\(recipient)' created successfully in Apple Mail."
        )
    }
    
    private func sendMessage(arguments: [String: Any]) throws -> ToolResult {
        guard let recipient = arguments["recipient"] as? String, Self.isValidEmail(recipient) else {
            throw ConnectorError.invalidArguments(details: "A valid recipient email address is required")
        }
        guard let subject = arguments["subject"] as? String, !subject.isEmpty else {
            throw ConnectorError.invalidArguments(details: "subject is required")
        }
        guard let body = arguments["body"] as? String else {
            throw ConnectorError.invalidArguments(details: "body is required")
        }
        
        let cleanRecipient = Self.escapeAppleScriptString(recipient)
        let cleanSubject = Self.escapeAppleScriptString(subject)
        let cleanBody = Self.escapeAppleScriptString(body)
        
        let script = """
        tell application "Mail"
            set newMsg to make new outgoing message with properties {subject:"\(cleanSubject)", content:"\(cleanBody)", visible:false}
            tell newMsg
                make new to recipient at end of to recipients with properties {address:"\(cleanRecipient)"}
            end tell
            send newMsg
            return "SENT"
        end tell
        """
        
        _ = try runner.execute(script: script)
        return .success(
            data: [
                "recipient": .string(recipient),
                "subject": .string(subject),
                "status": .string("sent")
            ],
            message: "Email sent to '\(recipient)' via Apple Mail."
        )
    }
    
    // MARK: - Prompt Injection Defense & Sanitization
    
    /// Encapsulates raw, untrusted email content in strict XML-style boundary markers
    /// and neutralizes prompt-injection attack patterns.
    public static func sanitizeEmailContent(_ content: String, messageId: String) -> String {
        var sanitized = content
        
        // Neutralize common adversarial prompt injection delimiters
        let dangerousPhrases = [
            "ignore previous instructions",
            "ignore all previous commands",
            "you are now in developer mode",
            "system prompt override",
            "new system instructions",
            "reveal system prompt"
        ]
        
        for phrase in dangerousPhrases {
            sanitized = sanitized.replacingOccurrences(
                of: phrase,
                with: "[REDACTED_ADVERSARIAL_INSTRUCTION]",
                options: .caseInsensitive
            )
        }
        
        // Wrap in untrusted boundary tags
        return """
        <untrusted_content source="apple_mail" id="\(messageId)">
        \(sanitized.trimmingCharacters(in: .whitespacesAndNewlines))
        </untrusted_content>
        """
    }
    
    // MARK: - Helpers & Parsers (Unit Testable)
    
    public struct EmailSummary: Equatable {
        public let id: String
        public let subject: String
        public let sender: String
        public let date: String
        
        public init(id: String, subject: String, sender: String, date: String) {
            self.id = id
            self.subject = subject
            self.sender = sender
            self.date = date
        }
    }
    
    public static func parseSearchOutput(_ raw: String) -> [EmailSummary] {
        guard !raw.isEmpty else { return [] }
        let records = raw.components(separatedBy: "///")
        var results: [EmailSummary] = []
        
        for record in records {
            let fields = record.components(separatedBy: "|||")
            if fields.count >= 4 {
                results.append(EmailSummary(
                    id: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    subject: fields[1].trimmingCharacters(in: .whitespacesAndNewlines),
                    sender: fields[2].trimmingCharacters(in: .whitespacesAndNewlines),
                    date: fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
        return results
    }
    
    public static func escapeAppleScriptString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
    
    public static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
