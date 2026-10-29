//
//  OmniDeskTests.swift
//  OmniDeskTests
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Testing
import Foundation
@testable import OmniDesk

struct OmniDeskTests {

    @Test func testEmptyVoiceInputSkipsAPI() async throws {
        let aiService = AIService()
        
        // Zero-length input
        let resultEmpty = await aiService.parseIntent(from: "")
        #expect(resultEmpty == nil)
        
        // Whitespace only
        let resultWhitespace = await aiService.parseIntent(from: "   \n\t  ")
        #expect(resultWhitespace == nil)
        
        // Very short noise (< 3 characters)
        let resultShort = await aiService.parseIntent(from: "ah")
        #expect(resultShort == nil)
    }

    @Test func testAIResponseJSONDecoding() throws {
        let jsonPayload = """
        {
            "intent": "create_task",
            "title": "Submit application to Google",
            "date": "2026-11-15",
            "time": "17:00"
        }
        """
        let data = try #require(jsonPayload.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AIResponse.self, from: data)
        
        #expect(decoded.intent == "create_task")
        #expect(decoded.title == "Submit application to Google")
        #expect(decoded.date == "2026-11-15")
        #expect(decoded.time == "17:00")
    }

    @Test func testTaskModelCreationAndToggle() async throws {
        var task = TodoTask(title: "Finish Portfolio Project", date: "2026-11-01", time: "10:00")
        #expect(task.isCompleted == false)
        #expect(task.title == "Finish Portfolio Project")
        
        // Toggle completion
        task.isCompleted.toggle()
        #expect(task.isCompleted == true)
    }

    @Test @MainActor func testViewModelFastPathClearAll() async throws {
        let viewModel = MainViewModel()
        viewModel.tasks = [
            TodoTask(title: "Task 1"),
            TodoTask(title: "Task 2")
        ]
        #expect(viewModel.tasks.count == 2)
        
        // Process clear command
        viewModel.processVoiceInput("clear all tasks")
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.status == .actionSuccess("All tasks cleared."))
    }
    
    @Test @MainActor func testViewModelManualTaskAddition() async throws {
        let viewModel = MainViewModel()
        let initialCount = viewModel.tasks.count
        
        viewModel.addManualTask(title: "Prepare for System Design Interview")
        #expect(viewModel.tasks.count == initialCount + 1)
        #expect(viewModel.tasks.first?.title == "Prepare for System Design Interview")
    }
    
    @Test func testTaskCodableSerialization() throws {
        let original = TodoTask(title: "Persistent Task", date: "2026-11-01", time: "14:30")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TodoTask.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.title == "Persistent Task")
        #expect(decoded.date == "2026-11-01")
        #expect(decoded.time == "14:30")
        #expect(decoded.isCompleted == false)
    }
    
    @Test @MainActor func testViewModelTaskPersistenceAcrossInstances() async throws {
        let vm1 = MainViewModel()
        vm1.tasks.removeAll()
        vm1.addManualTask(title: "Persisted across instances")
        #expect(vm1.tasks.contains(where: { $0.title == "Persisted across instances" }))
        
        // A new instance should load the saved task from UserDefaults
        let vm2 = MainViewModel()
        #expect(vm2.tasks.contains(where: { $0.title == "Persisted across instances" }))
    }
}
