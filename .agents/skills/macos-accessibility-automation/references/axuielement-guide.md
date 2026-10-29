# macOS Accessibility API (AXUIElement) Primary Reference

## Official Documentation Sources
- [Apple Developer: Accessibility for macOS](https://developer.apple.com/documentation/applicationservices/hiservices/accessibility_for_macos)
- [Apple Developer: AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462125-axuielementcopyattributevalue)
- [Apple Developer: AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462104-axuielementperformaction)
- [Apple Developer: AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

---

## 1. Common Accessibility Attributes

| Attribute Name | Constant | Expected Type | Description |
| :--- | :--- | :--- | :--- |
| `AXRole` | `kAXRoleAttribute` | `CFString` | Element type (`AXButton`, `AXWindow`, `AXTextField`, `AXStaticText`). |
| `AXTitle` | `kAXTitleAttribute` | `CFString` | The visible text label or title of the control. |
| `AXDescription` | `kAXDescriptionAttribute` | `CFString` | Descriptive accessibility label for screen readers. |
| `AXValue` | `kAXValueAttribute` | `CFTypeRef` | Current value (e.g. text field string or checkbox state). |
| `AXChildren` | `kAXChildrenAttribute` | `CFArray` of `AXUIElement` | Direct descendants in the visual hierarchy. |
| `AXFocusedWindow` | `kAXFocusedWindowAttribute` | `AXUIElement` | The active window of the target application. |
| `AXWindows` | `kAXWindowsAttribute` | `CFArray` of `AXUIElement` | All windows belonging to the target application. |

---

## 2. Common Accessibility Actions

| Action Name | Constant | Target Elements |
| :--- | :--- | :--- |
| `AXPress` | `kAXPressAction` | Buttons, checkboxes, radio buttons, tabs. |
| `AXIncrement` / `AXDecrement` | `kAXIncrementAction` | Sliders, steppers. |
| `AXConfirm` | `kAXConfirmAction` | Dialog confirm buttons, text entry submission. |
| `AXCancel` | `kAXCancelAction` | Modal dismiss / cancel buttons. |
| `AXRaise` | `kAXRaiseAction` | Windows (brings window to front). |

---

## 3. Known Pitfalls & Edge Cases

1. **Memory Leaks**: `AXUIElementCopyAttributeValue` follows the Core Foundation **Create Rule** (you own the returned `CFTypeRef`). Swift’s ARC automatically bridges `AnyObject?` returned into autoreleased objects, but ensure you do not hold onto stale `AXUIElement` references across window closures.
2. **Electron Apps**: Apps built with Electron (e.g. Slack, VS Code, Discord) may report empty or incomplete accessibility trees until the app is activated and focused.
3. **Occluded Windows**: Synthetic `kAXPressAction` works even if a button is obscured by another window, whereas mouse coordinate simulation (`CGEventPost`) will click whatever window is on top. Always prefer `AXUIElementPerformAction` over synthetic coordinate clicks.
