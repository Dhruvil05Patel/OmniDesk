---
name: macos-accessibility-automation
description: Traverses macOS window element trees, queries UI attributes, and executes synthetic actions via the C Accessibility API (AXUIElement). Use when inspecting non-scriptable macOS application UIs, finding buttons, clicking controls, or verifying Accessibility TCC authorization in Swift.
---

# macOS Accessibility Automation Skill

Provides patterns for inspecting and driving macOS applications using the low-level `ApplicationServices.HIServices` `AXUIElement` C APIs in native Swift.

## 1. When to Use This Skill
- Driving applications that lack AppleScript support (e.g. Slack, Notion, System Settings, developer tools).
- Inspecting focused window hierarchies, button titles, and input fields.
- Clicking UI buttons by role (`kAXButtonRole`) or title.
- Verifying whether the host process has Accessibility permission (`AXIsProcessTrusted`).

## 2. Accessibility Permissions Verification

```swift
import ApplicationServices

public static func checkAccessibilityTrusted() -> Bool {
    return AXIsProcessTrusted()
}

public static func promptAccessibilityPermission() -> Bool {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    return AXIsProcessTrustedWithOptions(options)
}
```

## 3. UI Hierarchy Traversal Pattern

```swift
import ApplicationServices

public static func copyAttribute<T>(_ element: AXUIElement, attribute: CFString) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard result == .success else { return nil }
    return value as? T
}

public static func inspectFocusedWindow(for pid: pid_t) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(pid)
    return copyAttribute(appElement, attribute: kAXFocusedWindowAttribute as CFString)
}

public static func findButton(in element: AXUIElement, matchingTitle title: String, depth: Int = 0, maxDepth: Int = 4) -> AXUIElement? {
    let elementTitle: String? = copyAttribute(element, attribute: kAXTitleAttribute as CFString)
    if let t = elementTitle, t.localizedCaseInsensitiveCompare(title) == .orderedSame {
        return element
    }
    
    guard depth < maxDepth else { return nil }
    let children: [AXUIElement]? = copyAttribute(element, attribute: kAXChildrenAttribute as CFString)
    for child in children ?? [] {
        if let match = findButton(in: child, matchingTitle: title, depth: depth + 1, maxDepth: maxDepth) {
            return match
        }
    }
    return nil
}
```

## 4. Performing Synthetic Actions
```swift
public static func clickElement(_ element: AXUIElement) -> Bool {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    return result == .success
}
```

For complete attribute lists and failure recovery strategies, see [AXUIElement Guide](references/axuielement-guide.md).
