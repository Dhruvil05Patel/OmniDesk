//
//  AIService.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import Combine

class AIService {
    
    func parseIntent(from text: String, completion: @escaping (AIResponse?) -> Void) {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GROQ_API_KEY") as? String, !apiKey.isEmpty else {
            print("❌ GROQ_API_KEY is missing. Please set it in Secrets.xcconfig.")
            completion(nil)
            return
        }
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            completion(nil)
            return
        }
        print("🚀 Sending POST request...")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let prompt = """
        You are a function that outputs only JSON. Do not include any explanation, markdown, or code fences. Output a single JSON object that matches exactly this schema:
        
        Format:
        {
          "intent": "create_task | create_calendar_event | unknown",
          "title": "...",
          "date": "YYYY-MM-DD or null",
          "time": "HH:mm or null"
        }

        Allowed intents:
        - create_task
        - create_calendar_event
        - unknown

        Rules:
        - Output only JSON. No extra text.
        - Use null for unknown date or time.
        - Title must be a short human-readable summary.
        - If user mentions time/date → use create_calendar_event
        - Extract meaningful title (remove filler words)
        - Convert natural language dates (tomorrow, today)

        Input: "\(text)"
        """
        
        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "response_format": [
                "type": "json_object"
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let error = error {
                print("API error:", error)
                completion(nil)
                return
            }
            
            if let http = response as? HTTPURLResponse {
                print("HTTP status:", http.statusCode)
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                // Step 1: Parse outer response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    print("AI RAW:", content)
                    
                    // Try to extract a JSON object from the content (in case the model added prose)
                    func extractJSONObject(from text: String) -> String? {
                        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
                            return nil
                        }
                        let jsonSubstring = text[start...end]
                        return String(jsonSubstring)
                    }
                    
                    let jsonString = extractJSONObject(from: content) ?? content
                    
                    // Step 2: Convert string JSON → Data and decode on the main actor
                    if let jsonData = jsonString.data(using: .utf8) {
                        Task { @MainActor in
                            do {
                                let decoded = try JSONDecoder().decode(AIResponse.self, from: jsonData)
                                completion(decoded)
                            } catch {
                                print("Decoding error:", error)
                                print("Raw returned content:\n\(content)")
                                completion(nil)
                            }
                        }
                        return
                    }
                }
                
                completion(nil)
                
            } catch {
                print("Parsing error:", error)
                completion(nil)
            }
            
        }.resume()
    }
}

