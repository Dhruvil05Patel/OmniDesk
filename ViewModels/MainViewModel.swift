//
//  MainViewModel.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import Combine
import SwiftUI

enum AssistantStatus: Equatable {
    case idle
    case listening
    case processing
    case actionSuccess(String)
    case error(String)
}

@MainActor
class MainViewModel: ObservableObject {
    
    @Published var tasks: [TodoTask] = []
    @Published var status: AssistantStatus = .idle
    @Published var lastRecognizedText: String = ""
    
    private let aiService = AIService()
    
    init() {
        // Sample welcome task for demonstration
        self.tasks = [
            TodoTask(title: "Welcome to OmniDesk! Try voice commands.", isCompleted: false)
        ]
    }
    
    func processVoiceInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastRecognizedText = trimmed
        
        guard trimmed.count >= 3 else {
            status = .idle
            return
        }
        
        // Local Fast-Path (Zero cost, instant execution)
        let lowercased = trimmed.lowercased()
        if lowercased == "clear all tasks" || lowercased == "delete all tasks" || lowercased == "clear tasks" {
            tasks.removeAll()
            showTemporaryStatus(.actionSuccess("All tasks cleared."))
            return
        }
        
        status = .processing
        
        Task {
            if let response = await aiService.parseIntent(from: trimmed) {
                if response.intent == "create_task" {
                    let task = TodoTask(
                        title: response.title ?? trimmed,
                        date: response.date,
                        time: response.time
                    )
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        tasks.insert(task, at: 0)
                    }
                    showTemporaryStatus(.actionSuccess("Added: \"\(task.title)\""))
                } else if response.intent == "create_calendar_event" {
                    showTemporaryStatus(.actionSuccess("Event scheduled: \"\(response.title ?? trimmed)\""))
                } else {
                    showTemporaryStatus(.actionSuccess("Processed command"))
                }
                
                ActionHandler.handle(response: response)
            } else {
                showTemporaryStatus(.error("Could not parse command. Try again."))
            }
        }
    }
    
    func toggleTask(id: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                tasks[index].isCompleted.toggle()
            }
        }
    }
    
    func deleteTask(id: UUID) {
        withAnimation(.easeInOut(duration: 0.25)) {
            tasks.removeAll { $0.id == id }
        }
    }
    
    func addManualTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = TodoTask(title: trimmed)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tasks.insert(task, at: 0)
        }
    }
    
    private func showTemporaryStatus(_ newStatus: AssistantStatus) {
        self.status = newStatus
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 seconds
            if self.status == newStatus {
                withAnimation {
                    self.status = .idle
                }
            }
        }
    }
}
