//
//  Task.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation

struct TodoTask: Identifiable {
    let id = UUID()
    let title: String
    let date: String?
    let time: String?
}
