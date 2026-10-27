//
//  MainViewModel.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import Combine

class MainViewModel: ObservableObject {
    
    @Published var tasks: [TodoTask] = []
    private let aiService = AIService()
    
    func addTask(from text: String) {
        
        aiService.parseIntent(from: text) { response in
            
            guard let response = response else { return }
            
            DispatchQueue.main.async {
                
                if response.intent == "create_task" {
                    let task = TodoTask(
                        title: response.title ?? text,
                        date: response.date,
                        time: response.time
                    )
                    self.tasks.append(task)
                }
                
                ActionHandler.handle(response: response)
            }
        }
    }
}
