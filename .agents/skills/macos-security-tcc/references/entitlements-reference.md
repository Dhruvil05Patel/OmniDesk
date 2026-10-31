# macOS Entitlements & TCC Primary Reference

## Official Documentation Sources
- [Apple Developer: App Sandbox Entitlements](https://developer.apple.com/documentation/security/app_sandbox_entitlements)
- [Apple Developer: Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [Apple Developer: Privacy and User Data](https://developer.apple.com/documentation/security/privacy_and_user_data)

---

## 1. Complete OmniDesk Production Entitlements Template

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Sandbox (Set to false if building full Jarvis system automation helper) -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <!-- Hardware Audio Capture -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
    
    <!-- Outbound Cloud LLM Networking -->
    <key>com.apple.security.network.client</key>
    <true/>
    
    <!-- Calendar & Reminders Personal Data -->
    <key>com.apple.security.personal-information.calendars</key>
    <true/>
    <key>com.apple.security.personal-information.reminders</key>
    <true/>
    
    <!-- User-Selected Files (Obsidian Vault Access) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    
    <!-- AppleScript Automation of Target Apps -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    
    <!-- Low-latency audio processing -->
    <key>inter-app-audio</key>
    <true/>
</dict>
</plist>
```

---

## 2. Diagnosing TCC & Permission Failures

### Error -1743: `errAEEventNotPermitted`
- **Cause**: The user denied permission when macOS prompted `"OmniDesk wants access to control Mail"`, or the app is missing `NSAppleEventsUsageDescription`.
- **Resolution**:
  1. Verify `NSAppleEventsUsageDescription` is present in `Info.plist`.
  2. Direct user to **System Settings > Privacy & Security > Automation > OmniDesk** and toggle target application ON.
  3. Reset permissions via CLI for debugging:
     ```bash
     tccutil reset AppleEvents <bundle_identifier>
     ```

### Error: Accessibility Not Trusted
- **Cause**: The app is trying to inspect windows or click buttons via `AXUIElement` without Accessibility approval.
- **Resolution**:
  1. Query `AXIsProcessTrusted()`.
  2. If false, prompt system dialog:
     ```swift
     let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
     _ = AXIsProcessTrustedWithOptions(options)
     ```
  3. Guide user to **System Settings > Privacy & Security > Accessibility**.
