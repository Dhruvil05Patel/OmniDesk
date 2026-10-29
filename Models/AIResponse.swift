//
//  AIResponse.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation

public struct AIResponse: Codable, Equatable, Sendable {
    public let intent: String
    public let title: String?
    public let date: String?
    public let time: String?
    public let recipient: String?
    public let subject: String?
    public let body: String?
    public let appName: String?
    public let notePath: String?
    
    public init(
        intent: String,
        title: String? = nil,
        date: String? = nil,
        time: String? = nil,
        recipient: String? = nil,
        subject: String? = nil,
        body: String? = nil,
        appName: String? = nil,
        notePath: String? = nil
    ) {
        self.intent = intent
        self.title = title
        self.date = date
        self.time = time
        self.recipient = recipient
        self.subject = subject
        self.body = body
        self.appName = appName
        self.notePath = notePath
    }
}
