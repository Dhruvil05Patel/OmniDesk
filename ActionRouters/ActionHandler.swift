//
//  ActionHandler.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//


import Foundation
import Combine

class ActionHandler {
    
    static func handle(response: AIResponse) {
        
        switch response.intent {
            
        case "create_calendar_event":
            if let title = response.title {
                CalendarService().createEvent(title: title, date: response.date ?? "")
            }
            
        case "create_task":
            print("Store as task:", response.title ?? "")
            
        default:
            print("Unknown intent")
        }
    }
}
