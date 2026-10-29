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
    
    private let storageKey = "omni_saved_tasks_v1"
    
    @Published var tasks: [TodoTask] = [] {
        didSet {
            saveTasks()
        }
    }
    @Published var status: AssistantStatus = .idle
    @Published var lastRecognizedText: String = ""
    
    private let aiService = AIService()
    
    init() {
        self.tasks = Self.loadStoredTasks()
    }
    
    private static func loadStoredTasks() -> [TodoTask] {
        if let data = UserDefaults.standard.data(forKey: "omni_saved_tasks_v1"),
           let saved = try? JSONDecoder().decode([TodoTask].self, from: data) {
            return saved
        }
        return [
            TodoTask(title: "Welcome to OmniDesk! Try voice commands.", isCompleted: false)
        ]
    }
    
    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
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
                let parsedTitle = response.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = (parsedTitle?.isEmpty == false ? parsedTitle! : trimmed)
                
                let task = TodoTask(
                    title: finalTitle,
                    date: response.date,
                    time: response.time
                )
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    tasks.insert(task, at: 0)
                }
                
                if response.intent == "create_calendar_event" {
                    showTemporaryStatus(.actionSuccess("Scheduled: \"\(task.title)\""))
                } else {
                    showTemporaryStatus(.actionSuccess("Added: \"\(task.title)\""))
                }
                
                ActionHandler.handle(response: response)
            } else {
                // Resilient fallback: If AI network or parsing fails, always save user's voice dictation as a task
                let fallbackTask = TodoTask(title: trimmed)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    tasks.insert(fallbackTask, at: 0)
                }
                showTemporaryStatus(.actionSuccess("Added: \"\(fallbackTask.title)\""))
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
