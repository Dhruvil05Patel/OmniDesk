---
name: macos-applescript-bridge
description: Compiles, executes, and sanitizes AppleScript / JXA scripts via NSAppleScript in Swift. Use when automating scriptable macOS applications (Apple Mail, Finder, Safari, Music), constructing Apple Events, handling error -1743, or defending against prompt injection.
---

# macOS AppleScript Bridge Skill

Provides hardened patterns for executing compiled AppleScript and JXA from native Swift via `NSAppleScript`, with timeout prevention and strict prompt-injection defense.

## 1. When to Use This Skill
- Controlling scriptable macOS applications (`tell application "Mail"`, `tell application "Finder"`).
- Drafting, composing, and sending emails via Apple Mail.
- Inspecting AppleScript error dictionaries and error codes.
- Sanitizing untrusted inputs before string interpolation into AppleScript commands.

## 2. Hardened Script Execution Pattern

```swift
public protocol AppleScriptRunnerProtocol: Sendable {
    func execute(script: String) throws -> String
}

public final class SystemAppleScriptRunner: AppleScriptRunnerProtocol, @unchecked Sendable {
    public init() {}
    
    public func execute(script: String) throws -> String {
        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw NSError(domain: "AppleScriptError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to initialize NSAppleScript."
            ])
        }
        
        let descriptor = appleScript.executeAndReturnError(&errorDict)
        if let error = errorDict {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            let number = error[NSAppleScript.errorNumber] as? Int ?? -1
            
            // Error -1743: Automation denied
            if number == -1743 {
                throw NSError(domain: "AppleScriptError", code: -1743, userInfo: [
                    NSLocalizedDescriptionKey: "Permission denied to automate target application."
                ])
            }
            throw NSError(domain: "AppleScriptError", code: number, userInfo: [
                NSLocalizedDescriptionKey: "AppleScript Error (\(number)): \(message)"
            ])
        }
        
        return descriptor.stringValue ?? ""
    }
}
```

## 3. String Escaping & Injection Prevention
Never directly interpolate unescaped user text into an AppleScript string literal. Always escape backslashes and double quotes:

```swift
public static func escapeAppleScriptString(_ str: String) -> String {
    return str
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
}
```

## 4. Prompt Injection Defense (Email Sanitizer)
Wrap untrusted retrieved data in explicit boundary markers:
```swift
public static func sanitizeEmailContent(_ content: String, messageId: String) -> String {
    var sanitized = content
    let dangerousPhrases = [
        "ignore previous instructions",
        "system prompt override",
        "you are now in developer mode"
    ]
    for phrase in dangerousPhrases {
        sanitized = sanitized.replacingOccurrences(of: phrase, with: "[REDACTED]", options: .caseInsensitive)
    }
    return "<untrusted_content id=\"\(messageId)\">\n\(sanitized)\n</untrusted_content>"
}
```

For Mail.app scripting dictionaries and recipes, see [AppleScript Reference](references/applescript-reference.md).
