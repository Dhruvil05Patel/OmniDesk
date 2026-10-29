# Security-Scoped Bookmarks Primary Reference

## Official Documentation Sources
- [Apple Developer: bookmarkData(options:includingResourceValuesForKeys:relativeTo:)](https://developer.apple.com/documentation/foundation/nsurl/1417795-bookmarkdata)
- [Apple Developer: init(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)](https://developer.apple.com/documentation/foundation/nsurl/1408034-init)
- [Apple Developer: startAccessingSecurityScopedResource()](https://developer.apple.com/documentation/foundation/nsurl/1417056-startaccessingsecurityscopedreso)

---

## 1. Lifecycle Rules

1. **Balance Calls**: Every call to `url.startAccessingSecurityScopedResource()` must be paired with `url.stopAccessingSecurityScopedResource()`.
2. **App-Scoped vs Document-Scoped**:
   - For folders/directories (like an Obsidian Vault): Always use `.withSecurityScope` (App-scoped).
   - Document-scoped bookmarks are only for documents that carry their own embedded permissions.
3. **Handling Stale Bookmarks**:
   - If the user moves or renames the folder, `resolvingBookmarkData` sets `bookmarkDataIsStale = true`.
   - The OS usually tracks the inode and successfully resolves the new path. You **must immediately regenerate and save** the new bookmark data to disk.

---

## 2. Path Traversal Guard (Jailing)
Even with security-scoped access to a directory, always guard against malicious or errant relative paths escaping the sandbox:

```swift
public static func safeResolve(rootURL: URL, relativePath: String) throws -> URL {
    let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let target = rootURL.appendingPathComponent(clean).standardized
    
    let canonicalRoot = rootURL.resolvingSymlinksInPath().standardized.path
    let canonicalTarget = target.resolvingSymlinksInPath().standardized.path
    
    guard canonicalTarget.hasPrefix(canonicalRoot) else {
        throw NSError(domain: "SecurityError", code: 403, userInfo: [
            NSLocalizedDescriptionKey: "Path traversal detected: \(relativePath)"
        ])
    }
    return target
}
```
