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
        setupVoiceActivationEngine()
    }
    
    private func setupVoiceActivationEngine() {
        VoiceActivationEngine.shared.onCommandCaptured = { [weak self] command in
            self?.processVoiceInput(command)
        }
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
    
    @discardableResult
    public func handleActiveVoiceApprovalInput(_ text: String) -> Bool {
        guard SafetyPolicyGate.shared.activeRequest != nil else { return false }
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let affirmativeWords = ["yes", "confirm", "approve", "send it", "do it", "proceed", "send", "okay", "ok", "yes please"]
        let negativeWords = ["no", "cancel", "abort", "reject", "don't send", "stop", "nope"]
        
        if affirmativeWords.contains(where: { lowercased.contains($0) }) {
            SafetyPolicyGate.shared.resolveActiveRequest(approved: true)
            showTemporaryStatus(.actionSuccess("Action approved by voice."))
            return true
        } else if negativeWords.contains(where: { lowercased.contains($0) }) {
            SafetyPolicyGate.shared.resolveActiveRequest(approved: false)
            showTemporaryStatus(.error("Action cancelled by voice."))
            return true
        }
        return false
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
        if handleActiveVoiceApprovalInput(lowercased) {
            return
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
                    WakeAcknowledgementPlayer.shared.speakText("Added task: \(task.title)")
                    VoiceActivationEngine.shared.transition(to: .listening)
                }
                
                // Dispatch live connector tool
                do {
                    if let result = try await ActionHandler.handle(response: response) {
                        let feedback = result.message ?? "Action completed"
                        showTemporaryStatus(.actionSuccess(feedback))
                        WakeAcknowledgementPlayer.shared.speakText(feedback)
                        VoiceActivationEngine.shared.transition(to: .listening)
                    } else if response.intent != "create_task" {
                        let fallback = TodoTask(title: finalTitle)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tasks.insert(fallback, at: 0)
                        }
                        showTemporaryStatus(.actionSuccess("Added: \"\(fallback.title)\""))
                        WakeAcknowledgementPlayer.shared.speakText("Added task: \(fallback.title)")
                        VoiceActivationEngine.shared.transition(to: .listening)
                    }
                } catch {
                    if case ConnectorError.destructiveActionRejectedByUser = error {
                        showTemporaryStatus(.error("Action cancelled by user"))
                        WakeAcknowledgementPlayer.shared.speakText("Action cancelled")
                    } else {
                        showTemporaryStatus(.error(error.localizedDescription))
                        WakeAcknowledgementPlayer.shared.speakText("Error: \(error.localizedDescription)")
                    }
                    VoiceActivationEngine.shared.transition(to: .listening)
                }
            } else {
                // Resilient fallback: If AI network or parsing fails, always save user's voice dictation as a task
                let fallbackTask = TodoTask(title: trimmed)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    tasks.insert(fallbackTask, at: 0)
                }
                showTemporaryStatus(.actionSuccess("Added: \"\(fallbackTask.title)\""))
                WakeAcknowledgementPlayer.shared.speakText("Added task: \(fallbackTask.title)")
                VoiceActivationEngine.shared.transition(to: .listening)
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
