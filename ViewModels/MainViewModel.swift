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
        
        let lowercased = trimmed.lowercased()
        
        // 1. Hands-Free Voice Confirmation Gate Resolver
        if SafetyPolicyGate.shared.activeRequest != nil {
            let affirmativeWords = ["yes", "confirm", "approve", "send it", "do it", "proceed", "send", "okay", "ok", "yes please"]
            let negativeWords = ["no", "cancel", "abort", "reject", "don't send", "stop", "nope"]
            
            if affirmativeWords.contains(where: { lowercased.contains($0) }) {
                SafetyPolicyGate.shared.resolveActiveRequest(approved: true)
                showTemporaryStatus(.actionSuccess("Action approved by voice."))
                return
            } else if negativeWords.contains(where: { lowercased.contains($0) }) {
                SafetyPolicyGate.shared.resolveActiveRequest(approved: false)
                showTemporaryStatus(.error("Action cancelled by voice."))
                return
            }
        }
        
        // 2. Local Fast-Path (Zero cost, instant execution)
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
                
                // If intent is create_task, add to tasks list
                if response.intent == "create_task" {
                    let task = TodoTask(
                        title: finalTitle,
                        date: response.date,
                        time: response.time
                    )
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        tasks.insert(task, at: 0)
                    }
                    showTemporaryStatus(.actionSuccess("Added: \"\(task.title)\""))
                }
                
                // Dispatch live connector tool
                do {
                    if let result = try await ActionHandler.handle(response: response) {
                        let feedback = result.message ?? "Action completed"
                        showTemporaryStatus(.actionSuccess(feedback))
                    } else if response.intent != "create_task" {
                        let fallback = TodoTask(title: finalTitle)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tasks.insert(fallback, at: 0)
                        }
                        showTemporaryStatus(.actionSuccess("Added: \"\(fallback.title)\""))
                    }
                } catch {
                    if case ConnectorError.destructiveActionRejectedByUser = error {
                        showTemporaryStatus(.error("Action cancelled by user"))
                    } else {
                        showTemporaryStatus(.error(error.localizedDescription))
                    }
                }
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
