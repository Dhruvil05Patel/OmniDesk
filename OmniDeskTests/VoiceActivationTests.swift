//
//  VoiceActivationTests.swift
//  OmniDeskTests
//
//  Created by Dhruvil Patel on 01/11/26.
//

import XCTest
@testable import OmniDesk

final class VoiceActivationTests: XCTestCase {
    
    @MainActor
    override func setUp() {
        super.setUp()
        WakeAcknowledgementPlayer.shared.stopAllPlayback()
    }
    
    @MainActor
    override func tearDown() {
        WakeAcknowledgementPlayer.shared.stopAllPlayback()
        super.tearDown()
    }
    
    // MARK: - 1. Keywords Config & Sensitivity Tests
    
    func testKeywordsConfigDefaultAndEffectiveThreshold() {
        let config = KeywordsConfig.default
        XCTAssertEqual(config.activeKeyword, "NEXUS")
        XCTAssertEqual(config.sensitivity, .balanced)
        XCTAssertEqual(config.effectiveThreshold, 0.35, accuracy: 0.01)
        
        // High sensitivity decreases required threshold
        var highConfig = config
        highConfig.sensitivity = .high
        XCTAssertLessThan(highConfig.effectiveThreshold, config.effectiveThreshold)
        
        // Low sensitivity increases required threshold
        var lowConfig = config
        lowConfig.sensitivity = .low
        XCTAssertGreaterThan(lowConfig.effectiveThreshold, config.effectiveThreshold)
        
        // Test primary keyword match
        let evaluation = config.evaluateTokenCandidate("NEXUS", score: 0.30)
        XCTAssertTrue(evaluation.isMatch)
        XCTAssertEqual(evaluation.matchedPhrase, "NEXUS")
        XCTAssertGreaterThanOrEqual(evaluation.confidence, 0.35)
        
        // Test variant match: "HEY NEXUS"
        let heyEval = config.evaluateTokenCandidate("HEY NEXUS", score: 0.25)
        XCTAssertTrue(heyEval.isMatch)
        XCTAssertEqual(heyEval.matchedPhrase, "HEY NEXUS")
    }
    
    func testKeywordsFalsePositiveBlocklist() {
        let config = KeywordsConfig.default
        let impostors = ["LEXUS", "TEXAS", "NEXT", "ACCESS", "EXCESS", "FOCUS", "JULIE", "DAILY", "DO IT"]
        
        for word in impostors {
            let result = config.evaluateTokenCandidate(word, score: 0.99)
            XCTAssertFalse(result.isMatch, "Impostor word '\(word)' must not trigger wake!")
            XCTAssertNil(result.matchedPhrase)
            XCTAssertEqual(result.confidence, 0.0)
        }
    }
    
    // MARK: - 2. Audio Ring Buffer Tests
    
    func testAudioRingBufferCircularOverwriting() {
        let buffer = AudioRingBuffer(sampleRate: 16000.0, windowDuration: 0.1) // 1600 samples
        XCTAssertEqual(buffer.currentCount, 0)
        
        // Append 1000 samples
        let chunk1 = [Float](repeating: 0.5, count: 1000)
        buffer.append(samples: chunk1)
        XCTAssertEqual(buffer.currentCount, 1000)
        
        // Append 1000 more samples (exceeds capacity of 1600)
        let chunk2 = [Float](repeating: 0.8, count: 1000)
        buffer.append(samples: chunk2)
        XCTAssertEqual(buffer.currentCount, buffer.capacity)
        
        // Verify readRecent returns newest samples (0.8)
        let recent = buffer.readRecent(count: 500)
        XCTAssertEqual(recent.count, 500)
        for sample in recent {
            XCTAssertEqual(sample, 0.8, accuracy: 0.001)
        }
        
        // Verify RMS calculation
        let rms = buffer.currentRMS(windowSamples: 500)
        XCTAssertGreaterThan(rms, 0.0)
        XCTAssertLessThanOrEqual(rms, 1.0)
        
        // Verify clear
        buffer.clear()
        XCTAssertEqual(buffer.currentCount, 0)
        XCTAssertEqual(buffer.currentRMS(), 0.0)
    }
    
    // MARK: - 3. Wake Word Detector Tests
    
    func testWakeWordDetectorProcessing() {
        let detector = ZipformerWakeWordDetector(config: .default)
        
        // 1. Low energy silence frames (< 0.015) must not trigger
        let silence = [Float](repeating: 0.005, count: 1024)
        let silenceResult = detector.process(samples: silence)
        XCTAssertNil(silenceResult)
        
        // 2. High energy frame with candidate match
        let voiceSample = [Float](repeating: 0.25, count: 1024)
        let result = detector.process(samples: voiceSample)
        XCTAssertNotNil(result)
        if let result = result {
            XCTAssertEqual(result.keyword, "NEXUS")
            XCTAssertGreaterThanOrEqual(result.confidence, 0.35)
        }
        
        // 3. Test explicit candidate evaluation with impostor
        let impostorResult = detector.evaluateCandidateString("LEXUS", rawScore: 0.8)
        XCTAssertNil(impostorResult)
        
        let validResult = detector.evaluateCandidateString("NEXUS", rawScore: 0.5)
        XCTAssertNotNil(validResult)
        XCTAssertEqual(validResult?.keyword, "NEXUS")
    }
    
    // MARK: - 4. Wake Acknowledgement Player Tests
    
    @MainActor
    func testWakeAcknowledgementPlayerPhraseSelectionAndEchoLock() {
        let player = WakeAcknowledgementPlayer.shared
        XCTAssertFalse(player.isAudioOutputPlaying)
        XCTAssertEqual(player.selectedPhrase, .yesBoss)
        
        player.selectedPhrase = .listening
        XCTAssertEqual(player.selectedPhrase, .listening)
        
        // Verify phrase cases
        let phrases = WakeAcknowledgementPlayer.AckPhrase.allCases.map { $0.rawValue }
        XCTAssertTrue(phrases.contains("Yes boss"))
        XCTAssertTrue(phrases.contains("Listening"))
        XCTAssertTrue(phrases.contains("Right here"))
        XCTAssertTrue(phrases.contains("On it"))
        
        // Verify stopAllPlayback resets lock
        player.stopAllPlayback()
        XCTAssertFalse(player.isAudioOutputPlaying)
    }
    
    // MARK: - 5. Voice Activation Engine State Transitions
    
    @MainActor
    func testVoiceActivationEngineStateTransitions() {
        let engine = VoiceActivationEngine.shared
        
        // Initial state
        XCTAssertFalse(engine.isMuted)
        
        // Test mute toggle
        engine.toggleMute()
        XCTAssertTrue(engine.isMuted)
        XCTAssertEqual(engine.state, .muted)
        
        // Unmute
        engine.toggleMute()
        XCTAssertFalse(engine.isMuted)
        
        // State transitions
        engine.transition(to: .listening)
        XCTAssertEqual(engine.state, .listening)
        
        engine.transition(to: .awake)
        XCTAssertEqual(engine.state, .awake)
        
        engine.transition(to: .recording)
        XCTAssertEqual(engine.state, .recording)
        
        engine.transition(to: .processing)
        XCTAssertEqual(engine.state, .processing)
        
        engine.transition(to: .awaitingApproval)
        XCTAssertEqual(engine.state, .awaitingApproval)
        
        // Reset to listening
        engine.transition(to: .listening)
        XCTAssertEqual(engine.state, .listening)
    }
    
    // MARK: - 6. Voice Confirmation Gate in MainViewModel
    
    @MainActor
    func testMainViewModelVoiceConfirmationGate() async {
        let vm = MainViewModel()
        let gate = SafetyPolicyGate.shared
        gate.abortAllPendingRequests()
        
        // 1. Without active gate request, voice input returns false
        let handledWithoutRequest = vm.handleActiveVoiceApprovalInput("yes")
        XCTAssertFalse(handledWithoutRequest)
        
        // 2. Setup mock pending request in SafetyPolicyGate
        let approvalTask = Task { @MainActor in
            await withCheckedContinuation { continuation in
                let req = PendingConfirmationRequest(
                    connectorId: "com.omnidesk.mail",
                    toolName: "mail_send_message",
                    arguments: ["to": "sarah@example.com"],
                    riskLevel: .destructiveOrOutbound,
                    descriptionText: "Send email to Sarah",
                    continuation: continuation
                )
                gate.activeRequest = req
            }
        }
        
        // Allow request to register
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertNotNil(gate.activeRequest)
        
        // 3. User speaks affirmative voice confirmation: "Yes please"
        let handledAffirmative = vm.handleActiveVoiceApprovalInput("yes please")
        XCTAssertTrue(handledAffirmative)
        
        let decision = await approvalTask.value
        XCTAssertEqual(decision.status, .userApproved)
        XCTAssertNil(gate.activeRequest)
        
        // 4. Test negative voice rejection: "No cancel"
        let rejectionTask = Task { @MainActor in
            await withCheckedContinuation { continuation in
                let req = PendingConfirmationRequest(
                    connectorId: "com.omnidesk.apps",
                    toolName: "apps_terminate",
                    arguments: ["app_name": "Slack"],
                    riskLevel: .destructiveOrOutbound,
                    descriptionText: "Terminate Slack",
                    continuation: continuation
                )
                gate.activeRequest = req
            }
        }
        
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertNotNil(gate.activeRequest)
        
        let handledNegative = vm.handleActiveVoiceApprovalInput("no cancel")
        XCTAssertTrue(handledNegative)
        
        let rejectDecision = await rejectionTask.value
        XCTAssertEqual(rejectDecision.status, .userRejected)
        XCTAssertNil(gate.activeRequest)
    }
    
    // MARK: - 7. Settings Window Controller Tests
    
    @MainActor
    func testSettingsWindowControllerInitializationAndShow() {
        let controller = SettingsWindowController.shared
        XCTAssertNotNil(controller.window)
        XCTAssertEqual(controller.window?.title, "OmniDesk Settings")
        
        // Ensure show() can be invoked cleanly without crash
        controller.show()
        XCTAssertTrue(controller.window?.isVisible ?? false)
    }
    
    // MARK: - 8. Hotkey Assistant Trigger Flow
    
    @MainActor
    func testHotkeyActivationFlow() {
        let engine = VoiceActivationEngine.shared
        var capturedQuery: String?
        engine.onCommandCaptured = { query in
            capturedQuery = query
        }
        
        // Trigger hotkey activation
        engine.triggerHotkeyActivation()
        XCTAssertEqual(engine.state, .awake)
        
        // Transition to recording
        engine.transition(to: .recording)
        XCTAssertEqual(engine.state, .recording)
        
        // Concluding recording transitions to processing
        engine.concludeCommandRecording()
        XCTAssertEqual(engine.state, .processing)
    }
    
    // MARK: - 9. App Control Name Sanitization & Fuzzy Matching Tests
    
    func testAppControlNameSanitization() {
        XCTAssertEqual(AppControlConnector.sanitizeAppName("the preview app"), "Preview")
        XCTAssertEqual(AppControlConnector.sanitizeAppName("the Preview app"), "Preview")
        XCTAssertEqual(AppControlConnector.sanitizeAppName("previous"), "Preview")
        XCTAssertEqual(AppControlConnector.sanitizeAppName("the previous app"), "Preview")
        XCTAssertEqual(AppControlConnector.sanitizeAppName("Slack.app"), "Slack")
        XCTAssertEqual(AppControlConnector.sanitizeAppName("Safari app"), "Safari")
        XCTAssertEqual(AppControlConnector.sanitizeAppName("an application"), "")
    }
    
    // MARK: - 10. Safety Gate Voice Confirmation Prompt Callback Tests
    
    @MainActor
    func testSafetyGateConfirmationPromptCallback() async {
        let gate = SafetyPolicyGate.shared
        let connector = AppControlConnector()
        let tool = connector.tools.first(where: { $0.name == "apps_terminate" })!
        
        var promptFired = false
        var promptedDescription: String?
        
        gate.onConfirmationPromptRequested = { req in
            promptFired = true
            promptedDescription = req.descriptionText
        }
        
        let evalTask = Task {
            await gate.evaluatePolicy(
                connector: connector,
                tool: tool,
                arguments: ["app_name": "Preview"]
            )
        }
        
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(promptFired)
        XCTAssertEqual(promptedDescription, "Terminate and close 'Preview'.")
        
        // Resolve affirmative
        gate.resolveActiveRequest(approved: true)
        let decision = await evalTask.value
        XCTAssertEqual(decision, .userApproved)
        XCTAssertNil(gate.activeRequest)
    }
    
    // MARK: - 11. Audio Runtime Warning Regression Tests
    
    @MainActor
    func testVoiceServiceIdempotentStop() {
        let voiceService = VoiceService.shared
        XCTAssertEqual(voiceService.state, .idle)
        
        // Calling stopRecording multiple times when idle must be a safe, idempotent no-op
        voiceService.stopRecording()
        voiceService.stopRecording()
        voiceService.stopRecording()
        XCTAssertEqual(voiceService.state, .idle)
        XCTAssertEqual(voiceService.audioLevel, 0.0)
    }
    
    @MainActor
    func testWakeAcknowledgementVoiceCachingAndDrainBarrier() async {
        let player = WakeAcknowledgementPlayer.shared
        XCTAssertFalse(player.isAudioOutputPlaying)
        
        // Calling stopAllPlayback resets audio lock cleanly
        player.stopAllPlayback()
        XCTAssertFalse(player.isAudioOutputPlaying)
        
        // Empty text immediately invokes completion without audio queue starvation
        var completed = false
        player.speakText("") {
            completed = true
        }
        XCTAssertTrue(completed)
    }
    
    // MARK: - 12. Wake-Word Activation & Safety Gating Tests
    
    @MainActor
    func testWakeWordEnabledSettingAndPersistence() {
        let engine = VoiceActivationEngine.shared
        let original = engine.isWakeWordEnabled
        defer { engine.isWakeWordEnabled = original }
        
        engine.isWakeWordEnabled = true
        XCTAssertTrue(engine.isWakeWordEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "omni_wake_word_enabled"))
        
        engine.isWakeWordEnabled = false
        XCTAssertFalse(engine.isWakeWordEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "omni_wake_word_enabled"))
    }
    
    @MainActor
    func testWakeWordConfigurationUpdates() {
        let engine = VoiceActivationEngine.shared
        
        engine.setWakeWordSensitivity(.high)
        XCTAssertEqual(engine.wakeDetector.config.sensitivity, .high)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "omni_wake_word_sensitivity"), "High")
        
        engine.setActiveKeywordPhrase("HEY NEXUS")
        XCTAssertEqual(engine.wakeDetector.config.activeKeyword, "HEY NEXUS")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "omni_active_keyword"), "HEY NEXUS")
        
        // Reset to default
        engine.setWakeWordSensitivity(.balanced)
        engine.setActiveKeywordPhrase("NEXUS")
    }
    
    @MainActor
    func testWakeWordLockedOutDuringActiveConfirmationPrompt() async {
        let engine = VoiceActivationEngine.shared
        let gate = SafetyPolicyGate.shared
        
        // 1. Create a simulated active confirmation request
        let approvalTask = Task { @MainActor in
            await withCheckedContinuation { continuation in
                let req = PendingConfirmationRequest(
                    connectorId: "com.omnidesk.apps",
                    toolName: "apps_terminate",
                    arguments: ["app_name": "Terminal"],
                    riskLevel: .destructiveOrOutbound,
                    descriptionText: "Terminate Terminal",
                    continuation: continuation
                )
                gate.activeRequest = req
            }
        }
        
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertNotNil(gate.activeRequest)
        
        // 2. Attempt to trigger wake word "Nexus" while confirmation is pending
        let previousState = engine.state
        engine.triggerWakeWordActivation(keyword: "NEXUS")
        
        // 3. Assert wake word is ignored: state does NOT change to .awake and confirmation request remains active
        XCTAssertEqual(engine.state, previousState)
        XCTAssertNotNil(gate.activeRequest)
        
        // Clean up
        gate.resolveActiveRequest(approved: false)
        _ = await approvalTask.value
        XCTAssertNil(gate.activeRequest)
    }
    
    @MainActor
    func testLifecycleHandlersSafeExecution() {
        let engine = VoiceActivationEngine.shared
        
        // Verify sleep, wake, and audio config change handlers execute safely without throwing or crashing
        engine.handleSystemSleep()
        engine.handleSystemWake()
        engine.handleAudioConfigurationChange()
        
        XCTAssertTrue(true)
    }
}
