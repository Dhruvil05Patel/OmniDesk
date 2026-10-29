//
//  ObsidianConnector.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation
import AppKit

/// Native local-first Obsidian Vault Connector.
/// Directly manipulates Markdown files within the vault and provides UI hooks via obsidian:// URI scheme.
public final class ObsidianConnector: Connector, @unchecked Sendable {
    
    public let id: String = "com.omnidesk.obsidian"
    public let displayName: String = "Obsidian Vault"
    public let connectorDescription: String = "Search, read, create notes, and append to daily notes in your local Obsidian vault."
    
    public var vaultURL: URL?
    private let bookmarkKey = "ObsidianVaultBookmark"
    
    public init(vaultURL: URL? = nil) {
        if let explicit = vaultURL {
            self.vaultURL = explicit
        } else {
            self.vaultURL = Self.resolveStoredVaultURL()
        }
    }
    
    public var tools: [ToolDefinition] {
        [
            ToolDefinition(
                name: "obsidian_search_notes",
                description: "Searches note titles, content, and tags in the Obsidian vault.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Search criteria",
                    properties: [
                        "query": ToolProperty(type: "string", description: "Search query keyword or text"),
                        "tag": ToolProperty(type: "string", description: "Optional tag filter without # (e.g. 'work' or 'interview')"),
                        "limit": ToolProperty(type: "integer", description: "Maximum number of results to return (default: 10)")
                    ],
                    required: ["query"]
                )
            ),
            ToolDefinition(
                name: "obsidian_read_note",
                description: "Reads the full Markdown content and metadata of a specific note.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Note identification",
                    properties: [
                        "path": ToolProperty(type: "string", description: "Relative note path inside vault (e.g. 'Meetings/Sync.md' or 'Ideas')")
                    ],
                    required: ["path"]
                )
            ),
            ToolDefinition(
                name: "obsidian_create_note",
                description: "Creates a new Markdown note in the vault.",
                riskLevel: .reversibleWrite,
                parameters: ToolParameterSchema(
                    description: "Note creation parameters",
                    properties: [
                        "path": ToolProperty(type: "string", description: "Relative path where the note should be saved (e.g. 'Projects/Apollo.md')"),
                        "content": ToolProperty(type: "string", description: "Markdown body content"),
                        "open_in_obsidian": ToolProperty(type: "boolean", description: "Whether to reveal and open the note in Obsidian (default: false)")
                    ],
                    required: ["path", "content"]
                )
            ),
            ToolDefinition(
                name: "obsidian_append_daily_note",
                description: "Appends timestamped notes, tasks, or summaries to today's Daily Note.",
                riskLevel: .reversibleWrite,
                parameters: ToolParameterSchema(
                    description: "Daily note parameters",
                    properties: [
                        "content": ToolProperty(type: "string", description: "Markdown content or bullet points to append"),
                        "heading": ToolProperty(type: "string", description: "Optional heading section to append under (e.g. '## Tasks' or '## Notes')"),
                        "date": ToolProperty(type: "string", description: "Optional target date in YYYY-MM-DD format (default: today)"),
                        "open_in_obsidian": ToolProperty(type: "boolean", description: "Whether to open the daily note in Obsidian (default: false)")
                    ],
                    required: ["content"]
                )
            ),
            ToolDefinition(
                name: "obsidian_open_note",
                description: "Opens an existing note directly in the Obsidian desktop application.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Open parameters",
                    properties: [
                        "path": ToolProperty(type: "string", description: "Relative path or note title to open")
                    ],
                    required: ["path"]
                )
            )
        ]
    }
    
    // MARK: - Permission Checking & Requesting
    
    public func checkPermissionState() async -> ConnectorPermissionStatus {
        guard let url = vaultURL else {
            return .notDetermined
        }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if FileManager.default.isReadableFile(atPath: url.path) {
                return .authorized
            }
        }
        return .denied
    }
    
    public func requestPermissions() async -> Bool {
        // Under macOS App Sandbox, selecting the folder via NSOpenPanel creates a Security-Scoped Bookmark
        if vaultURL != nil {
            return await checkPermissionState() == .authorized
        }
        return false
    }
    
    // MARK: - Tool Dispatcher
    
    public func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        guard let vault = vaultURL else {
            throw ConnectorError.permissionDenied(reason: "No Obsidian vault configured. Please set the vault folder in Settings.")
        }
        
        switch toolName {
        case "obsidian_search_notes":
            return try searchNotes(vaultURL: vault, arguments: arguments)
            
        case "obsidian_read_note":
            return try readNote(vaultURL: vault, arguments: arguments)
            
        case "obsidian_create_note":
            return try createNote(vaultURL: vault, arguments: arguments)
            
        case "obsidian_append_daily_note":
            return try appendDailyNote(vaultURL: vault, arguments: arguments)
            
        case "obsidian_open_note":
            return try openNoteInObsidian(vaultURL: vault, arguments: arguments)
            
        default:
            throw ConnectorError.targetNotFound(identifier: "Tool '\(toolName)' not found on \(displayName)")
        }
    }
    
    // MARK: - Tool Implementations
    
    private func searchNotes(vaultURL: URL, arguments: [String: Any]) throws -> ToolResult {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw ConnectorError.invalidArguments(details: "query is required for obsidian_search_notes")
        }
        let tagFilter = arguments["tag"] as? String
        let limit = arguments["limit"] as? Int ?? 10
        
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        var matches: [AnyCodableValue] = []
        let lowerQuery = query.lowercased()
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            
            // Avoid .obsidian configuration folder if not skipped
            if fileURL.path.contains("/.obsidian/") { continue }
            
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            
            let (frontmatter, body) = Self.parseFrontmatter(from: content)
            let tags = Self.extractTags(from: content, frontmatter: frontmatter)
            
            if let tagFilter = tagFilter, !tagFilter.isEmpty {
                let cleanTag = tagFilter.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
                if !tags.contains(where: { $0.lowercased() == cleanTag }) {
                    continue
                }
            }
            
            let titleMatches = fileName.lowercased().contains(lowerQuery)
            let contentMatches = body.lowercased().contains(lowerQuery)
            
            if titleMatches || contentMatches {
                let snippet = Self.extractSnippet(from: body, matching: query)
                matches.append(.dictionary([
                    "title": .string(fileName),
                    "path": .string(relativePath),
                    "snippet": .string(snippet),
                    "tags": .array(tags.map { .string($0) })
                ]))
                
                if matches.count >= limit {
                    break
                }
            }
        }
        
        return .success(
            data: [
                "query": .string(query),
                "count": .int(matches.count),
                "results": .array(matches)
            ],
            message: "Found \(matches.count) matching note(s) in vault."
        )
    }
    
    private func readNote(vaultURL: URL, arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            throw ConnectorError.invalidArguments(details: "path is required for obsidian_read_note")
        }
        
        let targetURL = try safeResolvePath(vaultURL: vaultURL, relativePath: path)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw ConnectorError.targetNotFound(identifier: "Note not found at '\(path)'")
        }
        
        let rawContent = try String(contentsOf: targetURL, encoding: .utf8)
        let (frontmatter, body) = Self.parseFrontmatter(from: rawContent)
        let tags = Self.extractTags(from: rawContent, frontmatter: frontmatter)
        let wordCount = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        
        let frontmatterDict: [String: AnyCodableValue] = frontmatter.mapValues { .string($0) }
        
        return .success(
            data: [
                "path": .string(path),
                "title": .string(targetURL.deletingPathExtension().lastPathComponent),
                "content": .string(body),
                "raw_content": .string(rawContent),
                "frontmatter": .dictionary(frontmatterDict),
                "tags": .array(tags.map { .string($0) }),
                "word_count": .int(wordCount)
            ],
            message: "Read note '\(targetURL.lastPathComponent)' (\(wordCount) words)."
        )
    }
    
    private func createNote(vaultURL: URL, arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            throw ConnectorError.invalidArguments(details: "path is required for obsidian_create_note")
        }
        guard let content = arguments["content"] as? String else {
            throw ConnectorError.invalidArguments(details: "content is required for obsidian_create_note")
        }
        let openInObsidian = arguments["open_in_obsidian"] as? Bool ?? false
        
        let targetURL = try safeResolvePath(vaultURL: vaultURL, relativePath: path)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            throw ConnectorError.invalidArguments(details: "Note already exists at '\(path)'. Use append or update to modify.")
        }
        
        // Create directory hierarchy if needed
        let parentDir = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Atomic write
        let data = Data(content.utf8)
        try data.write(to: targetURL, options: .atomic)
        
        if openInObsidian {
            _ = try? openNoteInObsidian(vaultURL: vaultURL, arguments: ["path": path])
        }
        
        return .success(
            data: [
                "path": .string(path),
                "title": .string(targetURL.deletingPathExtension().lastPathComponent),
                "bytes_written": .int(data.count)
            ],
            message: "Created note '\(targetURL.lastPathComponent)' successfully."
        )
    }
    
    private func appendDailyNote(vaultURL: URL, arguments: [String: Any]) throws -> ToolResult {
        guard let contentToAppend = arguments["content"] as? String, !contentToAppend.isEmpty else {
            throw ConnectorError.invalidArguments(details: "content is required for obsidian_append_daily_note")
        }
        let heading = arguments["heading"] as? String
        let dateStr = arguments["date"] as? String
        let openInObsidian = arguments["open_in_obsidian"] as? Bool ?? false
        
        let datePart: String
        if let explicit = dateStr, !explicit.isEmpty {
            datePart = explicit
        } else {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            datePart = df.string(from: Date())
        }
        
        // Check standard locations for daily notes (Daily/YYYY-MM-DD.md or YYYY-MM-DD.md)
        let candidatePaths = [
            "Daily/\(datePart).md",
            "daily/\(datePart).md",
            "Periodic/\(datePart).md",
            "\(datePart).md"
        ]
        
        var targetURL = try safeResolvePath(vaultURL: vaultURL, relativePath: "\(datePart).md")
        for candidate in candidatePaths {
            if let resolved = try? safeResolvePath(vaultURL: vaultURL, relativePath: candidate),
               FileManager.default.fileExists(atPath: resolved.path) {
                targetURL = resolved
                break
            }
        }
        
        let existingContent: String
        if FileManager.default.fileExists(atPath: targetURL.path) {
            existingContent = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
        } else {
            existingContent = "# Daily Note — \(datePart)\n\n"
        }
        
        let updatedContent = Self.appendContent(
            to: existingContent,
            contentToAppend: contentToAppend,
            underHeading: heading
        )
        
        let parentDir = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try Data(updatedContent.utf8).write(to: targetURL, options: .atomic)
        
        let relativePath = targetURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        if openInObsidian {
            _ = try? openNoteInObsidian(vaultURL: vaultURL, arguments: ["path": relativePath])
        }
        
        return .success(
            data: [
                "path": .string(relativePath),
                "date": .string(datePart)
            ],
            message: "Appended entry to daily note '\(targetURL.lastPathComponent)'."
        )
    }
    
    private func openNoteInObsidian(vaultURL: URL, arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            throw ConnectorError.invalidArguments(details: "path is required for obsidian_open_note")
        }
        
        let vaultName = vaultURL.lastPathComponent
        let cleanPath = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
        
        guard let encodedVault = vaultName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedFile = cleanPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let uri = URL(string: "obsidian://open?vault=\(encodedVault)&file=\(encodedFile)") else {
            throw ConnectorError.systemFailure(underlyingMessage: "Failed to construct obsidian:// URI")
        }
        
        NSWorkspace.shared.open(uri)
        return .success(
            data: [
                "uri": .string(uri.absoluteString),
                "vault": .string(vaultName),
                "file": .string(cleanPath)
            ],
            message: "Opened note in Obsidian."
        )
    }
    
    // MARK: - Security & Path Jailing
    
    public func safeResolvePath(vaultURL: URL, relativePath: String) throws -> URL {
        var cleanRel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanRel.hasSuffix(".md") && !cleanRel.contains(".") {
            cleanRel += ".md"
        }
        
        // Strip leading slashes
        while cleanRel.hasPrefix("/") {
            cleanRel.removeFirst()
        }
        
        let targetURL = vaultURL.appendingPathComponent(cleanRel).standardized
        let canonicalVault = vaultURL.resolvingSymlinksInPath().standardized.path
        let canonicalTarget = targetURL.resolvingSymlinksInPath().standardized.path
        
        // Path Traversal Security Gate
        guard canonicalTarget.hasPrefix(canonicalVault) else {
            throw ConnectorError.invalidArguments(details: "Security violation: Path '\(relativePath)' traverses outside the configured Obsidian vault.")
        }
        
        return targetURL
    }
    
    // MARK: - Static Parsers & Helpers (Unit Testable)
    
    public static func parseFrontmatter(from markdown: String) -> (frontmatter: [String: String], body: String) {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([:], markdown)
        }
        
        var frontmatterDict: [String: String] = [:]
        var closingIndex: Int? = nil
        
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
            let line = lines[i]
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    frontmatterDict[key] = val
                }
            }
        }
        
        guard let close = closingIndex else {
            return ([:], markdown)
        }
        
        let bodyLines = lines[(close + 1)...]
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        return (frontmatterDict, body)
    }
    
    public static func extractTags(from markdown: String, frontmatter: [String: String] = [:]) -> [String] {
        var tags = Set<String>()
        
        // Tags from frontmatter
        if let tagVal = frontmatter["tags"] ?? frontmatter["tag"] {
            let split = tagVal
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .components(separatedBy: ",")
            for t in split {
                let clean = t.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
                if !clean.isEmpty { tags.insert(clean) }
            }
        }
        
        // In-body #tags regex (e.g. #work, #project/apple)
        if let regex = try? NSRegularExpression(pattern: #"(?:^|\s)#([a-zA-Z0-9_\-\/]+)"#) {
            let nsStr = markdown as NSString
            let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsStr.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let tagString = nsStr.substring(with: match.range(at: 1))
                    tags.insert(tagString)
                }
            }
        }
        
        return Array(tags).sorted()
    }
    
    public static func extractSnippet(from text: String, matching query: String, maxLength: Int = 160) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            return String(text.prefix(maxLength))
        }
        
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex
        
        var snippet = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { snippet = "..." + snippet }
        if end < text.endIndex { snippet = snippet + "..." }
        return snippet
    }
    
    public static func appendContent(to existingMarkdown: String, contentToAppend: String, underHeading: String?) -> String {
        var base = existingMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let formattedEntry = contentToAppend.hasPrefix("-") || contentToAppend.hasPrefix("*") 
            ? contentToAppend 
            : "- [\(timestamp)] \(contentToAppend)"
        
        guard let heading = underHeading, !heading.isEmpty else {
            return base.isEmpty ? formattedEntry : "\(base)\n\n\(formattedEntry)\n"
        }
        
        if let headingRange = base.range(of: heading) {
            // Find next heading or end of text
            let restOfDoc = base[headingRange.upperBound...]
            if let nextHeadingRange = restOfDoc.range(of: "\n#") {
                let insertPoint = nextHeadingRange.lowerBound
                var updated = base
                updated.insert(contentsOf: "\n\(formattedEntry)", at: insertPoint)
                return updated
            } else {
                return "\(base)\n\(formattedEntry)\n"
            }
        } else {
            // Add heading and entry to end
            return "\(base)\n\n\(heading)\n\(formattedEntry)\n"
        }
    }
    
    public static func resolveStoredVaultURL() -> URL? {
        if let bookmarkData = UserDefaults.standard.data(forKey: "ObsidianVaultBookmark") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        
        // Environment fallback
        if let envPath = ProcessInfo.processInfo.environment["OBSIDIAN_VAULT_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        
        return nil
    }
}
