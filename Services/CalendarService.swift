//
//  CalendarService.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import EventKit
import Combine

class CalendarService {
    
    let store = EKEventStore()
    
    func createEvent(title: String, date: String) {
        
        if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
            store.requestFullAccessToEvents { granted, error in
                if granted {
                    let event = EKEvent(eventStore: self.store)
                    event.title = title
                    // TEMP date (we’ll improve later)
                    event.startDate = Date()
                    event.endDate = Date().addingTimeInterval(3600)
                    event.calendar = self.store.defaultCalendarForNewEvents
                    do {
                        try self.store.save(event, span: .thisEvent)
                        print("Event created!")
                    } catch {
                        print("Error saving event:", error)
                    }
                } else {
                    print("Calendar permission denied")
                }
            }
        } else {
            // Fallback for earlier OS versions
            store.requestAccess(to: .event) { granted, error in
                if granted {
                    let event = EKEvent(eventStore: self.store)
                    event.title = title
                    // TEMP date (we’ll improve later)
                    event.startDate = Date()
                    event.endDate = Date().addingTimeInterval(3600)
                    event.calendar = self.store.defaultCalendarForNewEvents
                    do {
                        try self.store.save(event, span: .thisEvent)
                        print("Event created!")
                    } catch {
                        print("Error saving event:", error)
                    }
                } else {
                    print("Calendar permission denied")
                }
            }
        }
    }
}

