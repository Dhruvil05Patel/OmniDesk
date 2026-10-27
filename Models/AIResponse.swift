//
//  AIResponse.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import Combine

struct AIResponse: Decodable {
    let intent: String
    let title: String?
    let date: String?
    let time: String?
}
