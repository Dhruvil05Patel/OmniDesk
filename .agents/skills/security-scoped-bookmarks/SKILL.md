---
name: security-scoped-bookmarks
description: Creates, persists, and resolves macOS Security-Scoped Bookmarks with NSOpenPanel. Use when an App Sandboxed application needs permanent read/write access to user-selected folders (e.g. an Obsidian vault) across app launches without re-prompting the user.
---

# Security-Scoped Bookmarks Skill

Provides the official Apple pattern for maintaining persistent filesystem access to user-chosen directories across application restarts under the macOS App Sandbox.

## 1. When to Use This Skill
- Accessing external folders (e.g., Obsidian vaults, project repositories, document libraries) from a sandboxed app.
- Storing bookmark data in `UserDefaults` or Keychain.
- Resolving stale bookmarks and handling permission scope lifecycles.

## 2. Prerequisites
The app's `.entitlements` file must include:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

## 3. Workflow: Save, Persist & Resolve

### Step 1: Prompt User with `NSOpenPanel`
```swift
func selectVaultDirectory() -> URL? {
    let openPanel = NSOpenPanel()
    openPanel.title = "Select Obsidian Vault Folder"
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = false
    openPanel.canCreateDirectories = true
    
    guard openPanel.runModal() == .OK, let selectedURL = openPanel.url else {
        return nil
    }
    return selectedURL
}
```

### Step 2: Create Security-Scoped Bookmark Data
```swift
func saveSecurityScopedBookmark(for url: URL, key: String = "ObsidianVaultBookmark") throws {
    let bookmarkData = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    UserDefaults.standard.set(bookmarkData, forKey: key)
}
```

### Step 3: Resolve & Access on App Launch
```swift
func resolveAndAccessVault(key: String = "ObsidianVaultBookmark") -> URL? {
    guard let bookmarkData = UserDefaults.standard.data(forKey: key) else { return nil }
    
    var isStale = false
    guard let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    ) else {
        return nil
    }
    
    // Refresh bookmark if stale
    if isStale {
        try? saveSecurityScopedBookmark(for: url, key: key)
    }
    
    // Begin security scope access
    if url.startAccessingSecurityScopedResource() {
        return url
    }
    return nil
}
```

For advanced resource cleanup and bookmark error handling, see [Bookmarks Guide](references/bookmarks-guide.md).
