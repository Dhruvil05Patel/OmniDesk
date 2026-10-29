//
//  CalendarService.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import EventKit
import Combine

/// Native macOS Calendar and Reminders Connector utilizing Apple's EventKit framework.
public final class CalendarConnector: Connector, @unchecked Sendable {
    
    public let id: String = "com.omnidesk.calendar"
    public let displayName: String = "Apple Calendar & Reminders"
    public let connectorDescription: String = "Query events, detect free/busy availability, schedule appointments, and create reminders locally via EventKit."
    
    public let store: EKEventStore
    
    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }
    
    public var tools: [ToolDefinition] {
        [
            ToolDefinition(
                name: "calendar_list_events",
                description: "Lists calendar events between a start date and an end date.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Date boundaries for querying events",
                    properties: [
                        "start_date": ToolProperty(type: "string", description: "ISO 8601 or YYYY-MM-DD start date (default: start of today)"),
                        "end_date": ToolProperty(type: "string", description: "ISO 8601 or YYYY-MM-DD end date (default: end of today)"),
                        "calendar_name": ToolProperty(type: "string", description: "Optional calendar name to filter by")
                    ],
                    required: []
                )
            ),
            ToolDefinition(
                name: "calendar_create_event",
                description: "Creates and schedules a new calendar event on the user's calendar.",
                riskLevel: .reversibleWrite,
                parameters: ToolParameterSchema(
                    description: "Event details",
                    properties: [
                        "title": ToolProperty(type: "string", description: "Title or subject of the meeting/event"),
                        "start_time": ToolProperty(type: "string", description: "ISO 8601 start datetime string"),
                        "end_time": ToolProperty(type: "string", description: "ISO 8601 end datetime string (or duration fallback)"),
                        "location": ToolProperty(type: "string", description: "Optional location or virtual link"),
                        "notes": ToolProperty(type: "string", description: "Optional description or meeting agenda"),
                        "calendar_name": ToolProperty(type: "string", description: "Optional specific calendar name")
                    ],
                    required: ["title", "start_time"]
                )
            ),
            ToolDefinition(
                name: "calendar_find_free_time",
                description: "Finds available free time blocks of a specified duration for a given day.",
                riskLevel: .safeReadOnly,
                parameters: ToolParameterSchema(
                    description: "Free/busy search criteria",
                    properties: [
                        "date": ToolProperty(type: "string", description: "Target date in YYYY-MM-DD format (default: today)"),
                        "duration_minutes": ToolProperty(type: "integer", description: "Required duration in minutes (e.g. 30, 45, 60)"),
                        "start_hour": ToolProperty(type: "integer", description: "Start of search window in 24h format (default: 9 for 9 AM)"),
                        "end_hour": ToolProperty(type: "integer", description: "End of search window in 24h format (default: 18 for 6 PM)"),
                        "calendar_name": ToolProperty(type: "string", description: "Optional calendar name to filter by")
                    ],
                    required: ["duration_minutes"]
                )
            ),
            ToolDefinition(
                name: "calendar_create_reminder",
                description: "Creates a new to-do reminder in Apple Reminders.",
                riskLevel: .reversibleWrite,
                parameters: ToolParameterSchema(
                    description: "Reminder details",
                    properties: [
                        "title": ToolProperty(type: "string", description: "Title of the reminder"),
                        "due_date": ToolProperty(type: "string", description: "Optional ISO 8601 due date string"),
                        "priority": ToolProperty(type: "integer", description: "Priority level: 0 (none), 1 (high), 5 (medium), 9 (low)"),
                        "notes": ToolProperty(type: "string", description: "Optional notes for the reminder")
                    ],
                    required: ["title"]
                )
            )
        ]
    }
    
    // MARK: - Permission Checking & Requesting
    
    public func checkPermissionState() async -> ConnectorPermissionStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .authorized
        case .writeOnly:
            return .restricted
        @unknown default:
            return .notDetermined
        }
    }
    
    public func requestPermissions() async -> Bool {
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                store.requestFullAccessToEvents { granted, _ in
                    if granted {
                        self.store.requestFullAccessToReminders { _, _ in
                            continuation.resume(returning: true)
                        }
                    } else {
                        continuation.resume(returning: false)
                    }
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    if granted {
                        self.store.requestAccess(to: .reminder) { _, _ in
                            continuation.resume(returning: true)
                        }
                    } else {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
    
    // MARK: - Tool Dispatcher
    
    public func execute(toolName: String, arguments: [String: Any]) async throws -> ToolResult {
        switch toolName {
        case "calendar_list_events":
            return try await listEvents(arguments: arguments)
            
        case "calendar_create_event":
            return try await createEvent(arguments: arguments)
            
        case "calendar_find_free_time":
            return try await findFreeTime(arguments: arguments)
            
        case "calendar_create_reminder":
            return try await createReminder(arguments: arguments)
            
        default:
            throw ConnectorError.targetNotFound(identifier: "Tool '\(toolName)' not found on \(displayName)")
        }
    }
    
    // MARK: - Implementations
    
    private func listEvents(arguments: [String: Any]) async throws -> ToolResult {
        let startStr = arguments["start_date"] as? String
        let endStr = arguments["end_date"] as? String
        let calName = arguments["calendar_name"] as? String
        
        let now = Date()
        let calendar = Calendar.current
        let startDate = startStr.flatMap { Self.parseDateString($0) } ?? calendar.startOfDay(for: now)
        let endDate = endStr.flatMap { Self.parseDateString($0) } ?? (calendar.date(byAdding: .day, value: 1, to: startDate) ?? now.addingTimeInterval(86400))
        
        var targetCalendars: [EKCalendar]? = nil
        if let calName = calName, !calName.isEmpty {
            targetCalendars = store.calendars(for: .event).filter { $0.title.localizedCaseInsensitiveContains(calName) }
        }
        
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
        let events = store.events(matching: predicate)
        
        let eventSummaries: [AnyCodableValue] = events.map { event in
            .dictionary([
                "title": .string(event.title ?? "Untitled"),
                "start_time": .string(Self.isoFormatter.string(from: event.startDate)),
                "end_time": .string(Self.isoFormatter.string(from: event.endDate)),
                "is_all_day": .bool(event.isAllDay),
                "location": .string(event.location ?? ""),
                "calendar": .string(event.calendar?.title ?? "Default"),
                "notes": .string(event.notes ?? "")
            ])
        }
        
        return .success(
            data: [
                "count": .int(events.count),
                "events": .array(eventSummaries)
            ],
            message: "Found \(events.count) calendar event(s)."
        )
    }
    
    private func createEvent(arguments: [String: Any]) async throws -> ToolResult {
        guard let title = arguments["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConnectorError.invalidArguments(details: "Title is required for calendar_create_event")
        }
        
        guard let startStr = arguments["start_time"] as? String, let startDate = Self.parseDateString(startStr) else {
            throw ConnectorError.invalidArguments(details: "A valid start_time (ISO 8601 or YYYY-MM-DD HH:mm) is required")
        }
        
        let endDate: Date
        if let endStr = arguments["end_time"] as? String, let parsedEnd = Self.parseDateString(endStr), parsedEnd > startDate {
            endDate = parsedEnd
        } else {
            // Default 1 hour duration
            endDate = startDate.addingTimeInterval(3600)
        }
        
        let location = arguments["location"] as? String
        let notes = arguments["notes"] as? String
        let calName = arguments["calendar_name"] as? String
        
        var targetCalendar = store.defaultCalendarForNewEvents
        if let calName = calName, !calName.isEmpty {
            if let matched = store.calendars(for: .event).first(where: { $0.title.localizedCaseInsensitiveContains(calName) && $0.allowsContentModifications }) {
                targetCalendar = matched
            }
        }
        
        guard let finalCalendar = targetCalendar else {
            throw ConnectorError.systemFailure(underlyingMessage: "No writable calendar found on device.")
        }
        
        let newEvent = EKEvent(eventStore: store)
        newEvent.title = title
        newEvent.startDate = startDate
        newEvent.endDate = endDate
        newEvent.calendar = finalCalendar
        if let loc = location, !loc.isEmpty { newEvent.location = loc }
        if let n = notes, !n.isEmpty { newEvent.notes = n }
        
        do {
            try store.save(newEvent, span: .thisEvent, commit: true)
            return .success(
                data: [
                    "event_id": .string(newEvent.eventIdentifier ?? ""),
                    "title": .string(newEvent.title),
                    "start_time": .string(Self.isoFormatter.string(from: newEvent.startDate)),
                    "end_time": .string(Self.isoFormatter.string(from: newEvent.endDate)),
                    "calendar": .string(finalCalendar.title)
                ],
                message: "Event '\(title)' scheduled successfully on '\(finalCalendar.title)'."
            )
        } catch {
            throw ConnectorError.systemFailure(underlyingMessage: "Failed to save event: \(error.localizedDescription)")
        }
    }
    
    private func findFreeTime(arguments: [String: Any]) async throws -> ToolResult {
        guard let durationMinutes = arguments["duration_minutes"] as? Int, durationMinutes > 0 else {
            throw ConnectorError.invalidArguments(details: "duration_minutes must be a positive integer")
        }
        
        let dateStr = arguments["date"] as? String
        let startHour = arguments["start_hour"] as? Int ?? 9
        let endHour = arguments["end_hour"] as? Int ?? 18
        let calName = arguments["calendar_name"] as? String
        
        let targetDay = dateStr.flatMap { Self.parseDateString($0) } ?? Date()
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: targetDay) ?? targetDay
        let dayEnd = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: targetDay) ?? targetDay.addingTimeInterval(3600 * 9)
        
        var targetCalendars: [EKCalendar]? = nil
        if let calName = calName, !calName.isEmpty {
            targetCalendars = store.calendars(for: .event).filter { $0.title.localizedCaseInsensitiveContains(calName) }
        }
        
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: targetCalendars)
        let existingEvents = store.events(matching: predicate).filter { !$0.isAllDay }
        
        let busyIntervals = existingEvents.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        let durationSec = TimeInterval(durationMinutes * 60)
        let freeSlots = Self.calculateFreeSlots(busyIntervals: busyIntervals, dayStart: dayStart, dayEnd: dayEnd, slotDuration: durationSec)
        
        let slotData: [AnyCodableValue] = freeSlots.map { slot in
            .dictionary([
                "start": .string(Self.isoFormatter.string(from: slot.start)),
                "end": .string(Self.isoFormatter.string(from: slot.end)),
                "duration_minutes": .int(Int(slot.duration / 60))
            ])
        }
        
        return .success(
            data: [
                "requested_duration": .int(durationMinutes),
                "slots_found": .int(freeSlots.count),
                "available_slots": .array(slotData)
            ],
            message: "Found \(freeSlots.count) available time slot(s)."
        )
    }
    
    private func createReminder(arguments: [String: Any]) async throws -> ToolResult {
        guard let title = arguments["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConnectorError.invalidArguments(details: "Title is required for calendar_create_reminder")
        }
        
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first
        
        if let priority = arguments["priority"] as? Int {
            reminder.priority = priority
        }
        
        if let notes = arguments["notes"] as? String {
            reminder.notes = notes
        }
        
        if let dueStr = arguments["due_date"] as? String, let dueDate = Self.parseDateString(dueStr) {
            let cal = Calendar.current
            reminder.dueDateComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        
        guard let calendar = reminder.calendar else {
            throw ConnectorError.systemFailure(underlyingMessage: "No reminder calendar available.")
        }
        
        do {
            try store.save(reminder, commit: true)
            return .success(
                data: [
                    "title": .string(title),
                    "calendar": .string(calendar.title)
                ],
                message: "Reminder '\(title)' added to Reminders."
            )
        } catch {
            throw ConnectorError.systemFailure(underlyingMessage: "Failed to save reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Pure Helper & Math Functions (Unit Testable)
    
    public static func calculateFreeSlots(
        busyIntervals: [DateInterval],
        dayStart: Date,
        dayEnd: Date,
        slotDuration: TimeInterval
    ) -> [DateInterval] {
        guard dayEnd > dayStart, slotDuration > 0 else { return [] }
        
        // 1. Clamp and normalize busy intervals inside [dayStart, dayEnd]
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
        
        // 3. Invert busy intervals to find free intervals
        var freeIntervals: [DateInterval] = []
        var cursor = dayStart
        
        for busy in mergedBusy {
            if busy.start > cursor {
                let freeGap = DateInterval(start: cursor, end: busy.start)
                if freeGap.duration >= slotDuration {
                    freeIntervals.append(freeGap)
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
    
    public static func parseDateString(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy"
        ].map { format -> DateFormatter in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = format
            return df
        }
        
        for df in formatters {
            if let date = df.date(from: trimmed) {
                return date
            }
        }
        
        return nil
    }
    
    public static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Backward Compatibility Wrapper
/// Legacy service wrapper delegating directly to `CalendarConnector`.
public class CalendarService {
    public let connector: CalendarConnector
    
    public init(connector: CalendarConnector = CalendarConnector()) {
        self.connector = connector
    }
    
    public func createEvent(title: String, date: String) {
        Task {
            _ = await connector.requestPermissions()
            var args: [String: Any] = ["title": title]
            if let parsed = CalendarConnector.parseDateString(date) {
                args["start_time"] = CalendarConnector.isoFormatter.string(from: parsed)
                args["end_time"] = CalendarConnector.isoFormatter.string(from: parsed.addingTimeInterval(3600))
            } else {
                let now = Date()
                args["start_time"] = CalendarConnector.isoFormatter.string(from: now)
                args["end_time"] = CalendarConnector.isoFormatter.string(from: now.addingTimeInterval(3600))
            }
            _ = try? await connector.execute(toolName: "calendar_create_event", arguments: args)
        }
    }
}
