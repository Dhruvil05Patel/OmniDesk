//
//  Task.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation

struct TodoTask: Identifiable, Equatable {
    let id: UUID
    var title: String
    var date: String?
    var time: String?
    var isCompleted: Bool
    let createdAt: Date
    
    init(id: UUID = UUID(), title: String, date: String? = nil, time: String? = nil, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.date = date
        self.time = time
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
