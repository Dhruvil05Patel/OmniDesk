//
//  AIService 2.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//


import Foundation

class AIService {
    
    func parseTask(from text: String, completion: @escaping (TodoTask?) -> Void) {
        
        let apiKey = "YOUR_API_KEY"
        
        let prompt = """
        Extract task details from this sentence:
        "\(text)"
        
        Return JSON with:
        title, date, time
        """
        
        // You’ll later call OpenAI API here
        print("Prompt:", prompt)
        
        // TEMP: fallback (no AI yet)
        let task = TodoTask(title: text, date: nil, time: nil)
        completion(task)
    }
}