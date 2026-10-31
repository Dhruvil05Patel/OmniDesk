# AppleScript & Mail.app Automation Primary Reference

## Official Documentation Sources
- [Apple Developer: NSAppleScript Class Reference](https://developer.apple.com/documentation/foundation/nsapplescript)
- [Apple Developer: Open Scripting Architecture (OSA)](https://developer.apple.com/documentation/applescript)

---

## 1. Apple Mail Scripting Recipes

### A. Date-Bounded Search (Timeout Defense)
Querying `every message of inbox` on large inboxes causes Apple Events timeouts (error -1712). Always filter by `date received`:

```applescript
set output to ""
set cutOffDate to (current date) - (7 * days)
tell application "Mail"
    set targetMessages to (messages of inbox whose date received > cutOffDate)
    repeat with msg in targetMessages
        set msgSubject to (subject of msg as string)
        if msgSubject contains "Interview" then
            set output to output & (id of msg as string) & "|||" & msgSubject & "///"
        end if
    end repeat
end tell
return output
```

### B. Interactive Draft Creation
```applescript
tell application "Mail"
    set newMsg to make new outgoing message with properties {subject:"Follow Up", content:"Hi there,\n\nChecking in on status.", visible:true}
    tell newMsg
        make new to recipient at end of to recipients with properties {address:"recruiter@apple.com"}
    end tell
    save newMsg
    activate
end tell
```

### C. Direct Outbound Dispatch
```applescript
tell application "Mail"
    set newMsg to make new outgoing message with properties {subject:"Confirmed", content:"Meeting confirmed.", visible:false}
    tell newMsg
        make new to recipient at end of to recipients with properties {address:"recruiter@apple.com"}
    end tell
    send newMsg
end tell
```

---

## 2. Standard Apple Event Error Codes

| Code | Symbol | Meaning |
| :--- | :--- | :--- |
| **-1743** | `errAEEventNotPermitted` | User denied TCC Automation permission for target app. |
| **-1712** | `errAETimeout` | The target app failed to respond within the default 30s timeout. |
| **-1708** | `errAEEventNotHandled` | Target application does not support the requested command. |
| **-600** | `procNotFound` | Target application is not running or crashed. |
| **-609** | `connectionInvalid` | Target application terminated while processing event. |
