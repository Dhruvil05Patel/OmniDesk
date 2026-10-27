//
//  AIService.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation

class AIService {
    
    /// Parses user speech text into structured intent and parameters via Groq API.
    /// Returns nil if input is empty, too short, or if parsing fails.
    func parseIntent(from text: String) async -> AIResponse? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Zero-cost pre-flight guard: Skip network call for empty or noise utterances
        guard trimmed.count >= 3 else {
            print("ℹ️ Voice input too short (\(trimmed.count) chars). Skipping API call.")
            return nil
        }
        
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GROQ_API_KEY") as? String, !apiKey.isEmpty else {
            print("❌ GROQ_API_KEY is missing. Please set it in Secrets.xcconfig.")
            return nil
        }
        
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Compact System Prompt with schema definition
        let systemPrompt = """
        You are an intent classifier. Output ONLY valid JSON matching this schema:
        {"intent":"create_task"|"create_calendar_event"|"unknown","title":"string","date":"YYYY-MM-DD"|null,"time":"HH:mm"|null}
        Rules:
        - If user mentions specific date or time -> "create_calendar_event".
        - Otherwise -> "create_task".
        - Title must be a concise, cleaned summary without filler words.
        - Output strictly JSON without explanations or markdown formatting.
        """
        
        let body: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmed]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "max_tokens": 150,
            "temperature": 0.1
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("❌ Groq API error status: \(http.statusCode)")
                return nil
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            
            // Extract pure JSON substring in case of unexpected wrappers
            let cleanJSON = extractJSONString(from: content)
            guard let jsonData = cleanJSON.data(using: .utf8) else {
                return nil
            }
            
            return try JSONDecoder().decode(AIResponse.self, from: jsonData)
            
        } catch {
            print("❌ AIService error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Legacy completion-handler bridge for backward compatibility
    func parseIntent(from text: String, completion: @escaping (AIResponse?) -> Void) {
        Task {
            let result = await parseIntent(from: text)
            await MainActor.run {
                completion(result)
            }
        }
    }
    
    private func extractJSONString(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }
}
