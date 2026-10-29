---
name: macos-security-tcc
description: Manages macOS Transparency, Consent, and Control (TCC), App Sandbox entitlements, Hardened Runtime, and Info.plist privacy permissions. Use when diagnosing permission denied errors, configuring entitlements, requesting system capabilities, or architectural sandboxing decisions.
---

# macOS Security & TCC Skill

Provides authoritative guidelines, entitlement schemas, and resolution workflows for macOS security boundaries, TCC privacy prompts, and sandbox limitations.

## 1. When to Use This Skill
- Adding or troubleshooting `Info.plist` usage description strings.
- Configuring entitlements in `.entitlements` files.
- Diagnosing TCC permission rejections (e.g. Accessibility error -1743, Apple Events denial).
- Navigating the architectural tradeoff between Mac App Store App Sandbox vs. Developer ID Notarization.

## 2. The Core Architectural Boundary: Sandbox vs. System Control

> [!CAUTION]
> **Hard Limit of macOS App Sandbox**:
> An app running under `com.apple.security.app-sandbox = true` **CANNOT**:
> 1. Inspect other running applications' UI hierarchies via the Accessibility API (`AXUIElement`).
> 2. Post synthetic keystrokes or mouse clicks to other applications (`CGEventPost`).
> 3. Send arbitrary Apple Events to apps not explicitly declared in `com.apple.security.scripting-targets`.
>
> If an assistant app needs full system control, UI automation, or deep cross-app driving, it **must** be distributed via **Developer ID Notarization (Non-Sandboxed Main App)**.

## 3. Standard TCC Permission Table

| Permission | Info.plist Key | App Sandbox Entitlement | Prompt Trigger API |
| :--- | :--- | :--- | :--- |
| **Calendars (Full)** | `NSCalendarsFullAccessUsageDescription` | `com.apple.security.personal-information.calendars` | `EKEventStore.requestFullAccessToEvents()` |
| **Reminders** | `NSRemindersFullAccessUsageDescription` | `com.apple.security.personal-information.reminders` | `EKEventStore.requestFullAccessToReminders()` |
| **Microphone** | `NSMicrophoneUsageDescription` | `com.apple.security.device.audio-input` | `AVCaptureDevice.requestAccess(for: .audio)` |
| **Speech Recognition** | `NSSpeechRecognitionUsageDescription` | N/A | `SFSpeechRecognizer.requestAuthorization()` |
| **Apple Events (Mail)**| `NSAppleEventsUsageDescription` | `com.apple.security.automation.apple-events` | First Apple Event dispatch via `NSAppleScript` |
| **Accessibility (UI)** | N/A (System Setting) | **Incompatible with Sandbox** | `AXIsProcessTrustedWithOptions(...)` |
| **User Files (Vault)** | N/A | `com.apple.security.files.user-selected.read-write` | `NSOpenPanel` + Security-Scoped Bookmark |

For complete XML definitions and troubleshooting workflows, see [Entitlements Reference](references/entitlements-reference.md).
