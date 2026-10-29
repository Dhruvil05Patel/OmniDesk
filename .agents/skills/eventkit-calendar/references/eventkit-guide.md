# EventKit Architecture & Primary API Reference

## Official Documentation Sources
- [Apple Developer: EventKit Framework](https://developer.apple.com/documentation/eventkit)
- [Apple Developer: EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore)
- [Apple Developer: requestFullAccessToEvents](https://developer.apple.com/documentation/eventkit/ekeventstore/4162273-requestfullaccesstoevents)

---

## 1. Authorization States (`EKAuthorizationStatus`)

| Status | Value | Meaning |
| :--- | :--- | :--- |
| `.notDetermined` | 0 | The user has not yet been prompted. Call `requestFullAccessToEvents`. |
| `.restricted` | 1 | The app is not authorized due to system policies/parental controls. |
| `.denied` | 2 | The user explicitly denied calendar access. Must redirect to System Settings. |
| `.authorized` | 3 | Legacy full access (macOS 13 and below). |
| `.fullAccess` | 4 | Complete read and write access on macOS 14+. |
| `.writeOnly` | 5 | App can add events without reading existing schedule. |

---

## 2. Robust Free/Busy Slot Computation Algorithm

```swift
public static func calculateFreeSlots(
    busyIntervals: [DateInterval],
    dayStart: Date,
    dayEnd: Date,
    slotDuration: TimeInterval
) -> [DateInterval] {
    guard dayEnd > dayStart, slotDuration > 0 else { return [] }
    
    // 1. Clamp busy intervals to window
    let clampedBusy = busyIntervals.compactMap { interval -> DateInterval? in
        let start = max(interval.start, dayStart)
        let end = min(interval.end, dayEnd)
        return end > start ? DateInterval(start: start, end: end) : nil
    }.sorted { $0.start < $1.start }
    
    // 2. Merge overlapping busy intervals
    var mergedBusy: [DateInterval] = []
    for interval in clampedBusy {
        if let last = mergedBusy.last {
            if interval.start <= last.end {
                let combinedEnd = max(last.end, interval.end)
                mergedBusy.removeLast()
                mergedBusy.append(DateInterval(start: last.start, end: combinedEnd))
            } else {
                mergedBusy.append(interval)
            }
        } else {
            mergedBusy.append(interval)
        }
    }
    
    // 3. Find gaps
    var freeIntervals: [DateInterval] = []
    var cursor = dayStart
    
    for busy in mergedBusy {
        if busy.start > cursor {
            let gap = DateInterval(start: cursor, end: busy.start)
            if gap.duration >= slotDuration {
                freeIntervals.append(gap)
            }
        }
        cursor = max(cursor, busy.end)
    }
    
    if cursor < dayEnd {
        let trailingGap = DateInterval(start: cursor, end: dayEnd)
        if trailingGap.duration >= slotDuration {
            freeIntervals.append(trailingGap)
        }
    }
    
    return freeIntervals
}
```

---

## 3. Recurring Events & Alarms
- **Single Instance Modification**: When editing a recurring event occurrence, pass `span: .thisEvent` to `store.save(event, span:commit:)`.
- **Modifying Entire Series**: Pass `span: .futureEvents`.
- **Alarms**: Attach `EKAlarm(relativeOffset: -900)` (triggers 15 minutes before event).
- **Subscribed / Read-Only Calendars**: Always check `calendar.allowsContentModifications == true` before attempting to write or delete events.
