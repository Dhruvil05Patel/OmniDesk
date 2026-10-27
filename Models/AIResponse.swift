//
//  AIResponse.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation

struct AIResponse: Codable, Equatable {
    let intent: String
    let title: String?
    let date: String?
    let time: String?
    
    init(intent: String, title: String? = nil, date: String? = nil, time: String? = nil) {
        self.intent = intent
        self.title = title
        self.date = date
        self.time = time
    }
}
