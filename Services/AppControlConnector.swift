//
//  AppControlConnector.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import Foundation
import AppKit
import ApplicationServices
import Darwin

/// Represents metadata of an installed macOS application.
public struct InstalledAppInfo: Codable, Sendable, Equatable {
    public let name: String
    public let bundleIdentifier: String?
    public let path: String
    
    public init(name: String, bundleIdentifier: String?, path: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
    }
}

/// Represents state of an active running process.
public struct ActiveProcessInfo: Codable, Sendable, Equatable {
    public let name: String
    public let bundleIdentifier: String?
    public let pid: Int32
    public let isActive: Bool
    public let isHidden: Bool
    
    public init(name: String, bundleIdentifier: String?, pid: Int32, isActive: Bool, isHidden: Bool) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.isActive = isActive
        self.isHidden = isHidden
    }
}

/// Native macOS Installed Applications and UI Automation Connector.
/// Discovers installed software, controls application lifecycle via NSWorkspace,
/// and drives user interfaces using the macOS Accessibility API (AXUIElement).
public final class AppControlConnector: Connector, @unchecked Sendable {
    
    public let id: String = "com.omnidesk.apps"
    public let displayName: String = "Installed macOS Apps & Automation"
    public let connectorDescription: String = "Discover installed applications, launch and focus software, inspect window UI trees, and drive macOS apps."
    
    public let workspace: NSWorkspace
    
    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }
    
    public var tools: [ToolDefinition] {
        [
            ToolDefinition(
                name: "apps_list_installed",
                description: "Lists installed macOS applications across system and user application directories.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Filter criteria",
                    properties: [
                        "query": ToolProperty(type: "string", description: "Optional name search filter (e.g. 'Safari', 'Slack', 'Xcode')"),
                        "limit": ToolProperty(type: "integer", description: "Maximum applications to return (default: 30)")
                    ],
                    required: []
                )
            ),
            ToolDefinition(
                name: "apps_list_running",
                description: "Lists currently running GUI applications and detects the active foreground window.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Process query criteria",
                    properties: [
                        "only_regular_apps": ToolProperty(type: "boolean", description: "Filter only standard GUI apps with Dock/menu icons (default: true)")
                    ],
                    required: []
                )
            ),
            ToolDefinition(
                name: "apps_launch_or_focus",
                description: "Launches an installed macOS application or brings it to the front if already running.",
                riskLevel: .reversibleWrite,
                parameters: ToolParameterSchema(
                    description: "Application launch details",
                    properties: [
                        "app_name": ToolProperty(type: "string", description: "Name of the application to launch or focus (e.g. 'Slack', 'Safari', 'Notes')"),
                        "bring_to_front": ToolProperty(type: "boolean", description: "Whether to activate and bring the app to the front (default: true)")
                    ],
                    required: ["app_name"]
                )
            ),
            ToolDefinition(
                name: "apps_terminate",
                description: "Quits or terminates a running application. DESTRUCTIVE ACTION: Requires user confirmation.",
                riskLevel: .destructiveOrOutbound,
                parameters: ToolParameterSchema(
                    description: "Termination details",
                    properties: [
                        "app_name": ToolProperty(type: "string", description: "Name or bundle ID of the application to terminate"),
                        "force": ToolProperty(type: "boolean", description: "Whether to force-kill without saving state (default: false)")
                    ],
                    required: ["app_name"]
                )
            ),
            ToolDefinition(
                name: "apps_inspect_ui",
                description: "Inspects the accessibility UI element tree of a running application's focused window.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "UI tree inspection criteria",
                    properties: [
                        "app_name": ToolProperty(type: "string", description: "Name of the target running application"),
                        "max_depth": ToolProperty(type: "integer", description: "Maximum hierarchy traversal depth (default: 3, max: 5)")
                    ],
                    required: ["app_name"]
                )
            ),
            ToolDefinition(
                name: "apps_perform_ui_action",
                description: "Synthesizes an action (such as clicking a button or menu) on a specific UI element in a target app.",
                riskLevel: .destructiveOrOutbound,
                parameters: ToolParameterSchema(
                    description: "UI action details",
                    properties: [
                        "app_name": ToolProperty(type: "string", description: "Name of the target running application"),
                        "element_title": ToolProperty(type: "string", description: "Title or label of the button/control to click"),
                        "action_name": ToolProperty(type: "string", description: "Action to perform (default: 'AXPress')")
                    ],
                    required: ["app_name", "element_title"]
                )
            )
        ]
    }
    
    // MARK: - Permission Checking & Requesting
    
    public func checkPermissionState() async -> ConnectorPermissionStatus {
        let isTrusted = AXIsProcessTrusted()
        return isTrusted ? .authorized : .denied
    }
    
    public func requestPermissions() async -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        return isTrusted
    }
    
    // MARK: - Tool Dispatcher
    
    public func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        switch toolName {
        case "apps_list_installed":
            return try listInstalledApps(arguments: arguments)
            
        case "apps_list_running":
            return try listRunningApps(arguments: arguments)
            
        case "apps_launch_or_focus":
            return try await launchOrFocusApp(arguments: arguments)
            
        case "apps_terminate":
            return try terminateApp(arguments: arguments)
            
        case "apps_inspect_ui":
            return try inspectUI(arguments: arguments)
            
        case "apps_perform_ui_action":
            return try performUIAction(arguments: arguments)
            
        default:
            throw ConnectorError.targetNotFound(identifier: "Tool '\(toolName)' not found on \(displayName)")
        }
    }
    
    // MARK: - Implementations
    
    private func listInstalledApps(arguments: [String: Any]) throws -> ToolResult {
        let query = (arguments["query"] as? String)?.lowercased()
        let limit = min(max(arguments["limit"] as? Int ?? 30, 1), 100)
        
        let apps = Self.discoverInstalledApplications()
        let filtered = apps.filter { app in
            guard let q = query, !q.isEmpty else { return true }
            return app.name.lowercased().contains(q) || (app.bundleIdentifier?.lowercased().contains(q) ?? false)
        }
        
        let outputList = Array(filtered.prefix(limit))
        let appData: [AnyCodableValue] = outputList.map { app in
            .dictionary([
                "name": .string(app.name),
                "bundle_id": .string(app.bundleIdentifier ?? ""),
                "path": .string(app.path)
            ])
        }
        
        return .success(
            data: [
                "total_found": .int(filtered.count),
                "returned": .int(outputList.count),
                "apps": .array(appData)
            ],
            message: "Discovered \(filtered.count) matching application(s)."
        )
    }
    
    private func listRunningApps(arguments: [String: Any]) throws -> ToolResult {
        let onlyRegular = arguments["only_regular_apps"] as? Bool ?? true
        
        let running = workspace.runningApplications.compactMap { app -> ActiveProcessInfo? in
            if onlyRegular && app.activationPolicy != .regular { return nil }
            return ActiveProcessInfo(
                name: app.localizedName ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                pid: app.processIdentifier,
                isActive: app.isActive,
                isHidden: app.isHidden
            )
        }
        
        let processData: [AnyCodableValue] = running.map { proc in
            .dictionary([
                "name": .string(proc.name),
                "bundle_id": .string(proc.bundleIdentifier ?? ""),
                "pid": .int(Int(proc.pid)),
                "is_active": .bool(proc.isActive),
                "is_hidden": .bool(proc.isHidden)
            ])
        }
        
        return .success(
            data: [
                "count": .int(running.count),
                "running_apps": .array(processData)
            ],
            message: "\(running.count) applications currently running."
        )
    }
    
    private func launchOrFocusApp(arguments: [String: Any]) async throws -> ToolResult {
        guard let appName = arguments["app_name"] as? String, !appName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConnectorError.invalidArguments(details: "app_name is required for apps_launch_or_focus")
        }
        let bringToFront = arguments["bring_to_front"] as? Bool ?? true
        
        // Check if already running
        if let existing = workspace.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true ||
            $0.bundleIdentifier?.localizedCaseInsensitiveContains(appName) == true
        }) {
            if bringToFront {
                existing.activate(options: [.activateIgnoringOtherApps])
            }
            return .success(
                data: [
                    "app_name": .string(existing.localizedName ?? appName),
                    "pid": .int(Int(existing.processIdentifier)),
                    "state": .string("focused")
                ],
                message: "Brought '\(existing.localizedName ?? appName)' to the front."
            )
        }
        
        // Find installed application URL
        guard let appURL = Self.findApplicationURL(named: appName) else {
            throw ConnectorError.targetNotFound(identifier: "Application matching '\(appName)' not found in application directories.")
        }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = bringToFront
        
        do {
            let app = try await workspace.openApplication(at: appURL, configuration: config)
            return .success(
                data: [
                    "app_name": .string(app.localizedName ?? appName),
                    "bundle_id": .string(app.bundleIdentifier ?? ""),
                    "pid": .int(Int(app.processIdentifier)),
                    "state": .string("launched")
                ],
                message: "Launched '\(app.localizedName ?? appName)' successfully."
            )
        } catch {
            throw ConnectorError.systemFailure(underlyingMessage: "Failed to open application: \(error.localizedDescription)")
        }
    }
    
    private func terminateApp(arguments: [String: Any]) throws -> ToolResult {
        guard let appName = arguments["app_name"] as? String, !appName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConnectorError.invalidArguments(details: "app_name is required for apps_terminate")
        }
        
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmedName.lowercased()
        if lower == "an app" || lower == "app" || lower == "the app" || lower == "quit an app" {
            throw ConnectorError.invalidArguments(details: "Please specify which application to quit (e.g. 'Quit Safari' or 'Close Slack').")
        }
        
        let force = arguments["force"] as? Bool ?? false
        
        // Match priority: 1) Exact match, 2) Prefix match, 3) Substring match
        let runningApps = workspace.runningApplications
        guard let target = runningApps.first(where: {
            $0.localizedName?.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame ||
            $0.bundleIdentifier?.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) ?? runningApps.first(where: {
            $0.localizedName?.lowercased().hasPrefix(lower) == true
        }) ?? runningApps.first(where: {
            $0.localizedName?.localizedCaseInsensitiveContains(trimmedName) == true ||
            $0.bundleIdentifier?.localizedCaseInsensitiveContains(trimmedName) == true
        }) else {
            throw ConnectorError.targetNotFound(identifier: "Running process '\(trimmedName)' not found.")
        }
        
        let finalName = target.localizedName ?? trimmedName
        
        // Multi-tier progressive termination strategy
        // Tier 1: NSRunningApplication graceful or forced termination
        var success = force ? target.forceTerminate() : target.terminate()
        
        // Tier 2: AppleScript graceful quit if target.terminate() failed with kernel port error
        if !success && !force {
            let script = "tell application \"\(finalName)\" to quit"
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
                if err == nil {
                    success = true
                }
            }
        }
        
        // Tier 3: POSIX SIGTERM signal fallback
        if !success {
            let pid = target.processIdentifier
            if pid > 0 {
                let sig = force ? SIGKILL : SIGTERM
                if kill(pid, sig) == 0 {
                    success = true
                }
            }
        }
        
        // Tier 4: Force termination fallback
        if !success && force {
            success = target.forceTerminate()
        }
        
        if success {
            return .success(
                data: [
                    "app_name": .string(finalName),
                    "forced": .bool(force)
                ],
                message: "Terminated '\(finalName)'."
            )
        } else {
            throw ConnectorError.systemFailure(underlyingMessage: "Termination signal failed for '\(finalName)'.")
        }
    }
    
    private func inspectUI(arguments: [String: Any]) throws -> ToolResult {
        guard let appName = arguments["app_name"] as? String, !appName.isEmpty else {
            throw ConnectorError.invalidArguments(details: "app_name is required for apps_inspect_ui")
        }
        let maxDepth = min(max(arguments["max_depth"] as? Int ?? 3, 1), 5)
        
        guard let runningApp = workspace.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }) else {
            throw ConnectorError.targetNotFound(identifier: "Running application '\(appName)' not found. Make sure the app is open.")
        }
        
        let pid = runningApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowValue: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        
        guard axResult == .success, let focusedWindow = windowValue else {
            return .success(
                data: [
                    "app_name": .string(runningApp.localizedName ?? appName),
                    "pid": .int(Int(pid)),
                    "ui_tree": .dictionary([
                        "role": .string("AXApplication"),
                        "title": .string(runningApp.localizedName ?? appName),
                        "notice": .string("No active or focused window found.")
                    ])
                ],
                message: "Application is running, but has no focused window."
            )
        }
        
        let windowElement = focusedWindow as! AXUIElement
        let treeDict = Self.buildUINodeTree(element: windowElement, currentDepth: 0, maxDepth: maxDepth)
        
        return .success(
            data: [
                "app_name": .string(runningApp.localizedName ?? appName),
                "pid": .int(Int(pid)),
                "ui_tree": .dictionary(treeDict)
            ],
            message: "Retrieved accessibility hierarchy for '\(runningApp.localizedName ?? appName)'."
        )
    }
    
    private func performUIAction(arguments: [String: Any]) throws -> ToolResult {
        guard let appName = arguments["app_name"] as? String, !appName.isEmpty else {
            throw ConnectorError.invalidArguments(details: "app_name is required")
        }
        guard let elementTitle = arguments["element_title"] as? String, !elementTitle.isEmpty else {
            throw ConnectorError.invalidArguments(details: "element_title is required")
        }
        let actionName = arguments["action_name"] as? String ?? (kAXPressAction as String)
        
        guard let runningApp = workspace.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }) else {
            throw ConnectorError.targetNotFound(identifier: "Target app '\(appName)' is not running.")
        }
        
        let pid = runningApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowValue: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard axResult == .success, let focusedWindow = windowValue else {
            throw ConnectorError.systemFailure(underlyingMessage: "Could not locate focused window for '\(appName)'")
        }
        
        let windowElement = focusedWindow as! AXUIElement
        guard let targetElement = Self.findUIElement(in: windowElement, matchingTitle: elementTitle, depth: 0, maxDepth: 5) else {
            throw ConnectorError.targetNotFound(identifier: "Control with title '\(elementTitle)' not found in '\(appName)' UI.")
        }
        
        let actionResult = AXUIElementPerformAction(targetElement, actionName as CFString)
        if actionResult == .success {
            return .success(
                data: [
                    "app_name": .string(runningApp.localizedName ?? appName),
                    "element": .string(elementTitle),
                    "action": .string(actionName)
                ],
                message: "Performed '\(actionName)' on '\(elementTitle)' successfully."
            )
        } else {
            throw ConnectorError.systemFailure(underlyingMessage: "Accessibility action '\(actionName)' failed with code \(actionResult.rawValue).")
        }
    }
    
    // MARK: - Discovery & Accessibility Tree Traversal (Unit Testable)
    
    public static func discoverInstalledApplications() -> [InstalledAppInfo] {
        let directories: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        
        var results: [InstalledAppInfo] = []
        var visitedPaths = Set<String>()
        
        for dir in directories {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            
            for item in contents where item.pathExtension == "app" {
                let canonical = item.resolvingSymlinksInPath().path
                if visitedPaths.contains(canonical) { continue }
                visitedPaths.insert(canonical)
                
                let displayName = item.deletingPathExtension().lastPathComponent
                let bundle = Bundle(url: item)
                let bundleId = bundle?.bundleIdentifier
                
                results.append(InstalledAppInfo(
                    name: displayName,
                    bundleIdentifier: bundleId,
                    path: item.path
                ))
            }
        }
        
        return results.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    public static func findApplicationURL(named name: String) -> URL? {
        let all = discoverInstalledApplications()
        if let exact = all.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return URL(fileURLWithPath: exact.path)
        }
        if let prefix = all.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            return URL(fileURLWithPath: prefix.path)
        }
        return nil
    }
    
    public static func buildUINodeTree(element: AXUIElement, currentDepth: Int, maxDepth: Int) -> [String: AnyCodableValue] {
        var node: [String: AnyCodableValue] = [:]
        
        var roleVal: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal) == .success, let r = roleVal as? String {
            node["role"] = .string(r)
        }
        
        var titleVal: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleVal) == .success, let t = titleVal as? String, !t.isEmpty {
            node["title"] = .string(t)
        }
        
        var descVal: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descVal) == .success, let d = descVal as? String, !d.isEmpty {
            node["description"] = .string(d)
        }
        
        if currentDepth < maxDepth {
            var childrenVal: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
               let children = childrenVal as? [AXUIElement] {
                let childrenTrees = children.prefix(15).map { child in
                    AnyCodableValue.dictionary(buildUINodeTree(element: child, currentDepth: currentDepth + 1, maxDepth: maxDepth))
                }
                node["children"] = .array(Array(childrenTrees))
            }
        }
        
        return node
    }
    
    public static func findUIElement(in root: AXUIElement, matchingTitle query: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        var titleVal: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXTitleAttribute as CFString, &titleVal) == .success,
           let t = titleVal as? String,
           t.localizedCaseInsensitiveCompare(query) == .orderedSame || t.localizedCaseInsensitiveContains(query) {
            return root
        }
        
        guard depth < maxDepth else { return nil }
        
        var childrenVal: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for child in children {
                if let found = findUIElement(in: child, matchingTitle: query, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }
        return nil
    }
}
