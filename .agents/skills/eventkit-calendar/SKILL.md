---
name: eventkit-calendar
description: Interacts with macOS Calendar and Reminders via Apple's EventKit framework. Use when building or debugging calendar event querying, natural language scheduling, conflict detection, recurrence handling, or free/busy availability algorithms in Swift.
---

# EventKit Calendar & Reminders Skill

Provides production-ready patterns, permission requirements, and algorithms for interfacing with macOS `EventKit` (`EKEventStore`) in native Swift applications.

## 1. When to Use This Skill
- Querying, filtering, or creating Calendar events (`EKEvent`).
- Creating and scheduling Reminders (`EKReminder`).
- Calculating free/busy schedule availability and finding open meeting slots.
- Managing macOS 14+ / Sonoma+ / Sequoia+ TCC calendar permissions.

## 2. Permissions & Entitlements (macOS 14+)

> [!IMPORTANT]
> `store.requestAccess(to: .event)` is **deprecated** starting in macOS 14.0. You must use `requestFullAccessToEvents` or `requestWriteOnlyAccessToEvents`.

### Info.plist Keys
```xml
<key>NSCalendarsFullAccessUsageDescription</key>
<string>OmniDesk needs full calendar access to query your schedule and detect conflicts.</string>
<key>NSRemindersFullAccessUsageDescription</key>
<string>OmniDesk needs reminders access to track tasks and follow-ups.</string>
```

### App Sandbox Entitlements
```xml
<key>com.apple.security.personal-information.calendars</key>
<true/>
<key>com.apple.security.personal-information.reminders</key>
<true/>
```

## 3. Core Implementation Patterns

### Asynchronous Permission Request
```swift
func requestCalendarAccess(store: EKEventStore) async -> Bool {
    if #available(macOS 14.0, *) {
        return await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    } else {
        return await withCheckedContinuation { continuation in
            store.requestAccess(to: .event) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}
```

### Date-Bounded Event Querying
```swift
func fetchEvents(store: EKEventStore, start: Date, end: Date, calendarName: String? = nil) -> [EKEvent] {
    var calendars: [EKCalendar]? = nil
    if let name = calendarName {
        calendars = store.calendars(for: .event).filter { $0.title.localizedCaseInsensitiveContains(name) }
    }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    return store.events(matching: predicate)
}
```

### Free/Busy Availability Slot Finder Algorithm
When calculating open time slots of duration $T$ between $H_{start}$ and $H_{end}$:
1. Filter out all-day events.
2. Clamp and sort busy intervals within the target day window.
3. Merge overlapping or contiguous busy intervals.
4. Scan gaps between merged busy intervals; collect all gaps where `duration >= slotDuration`.

For full implementation details, see [EventKit API Guide](references/eventkit-guide.md).
