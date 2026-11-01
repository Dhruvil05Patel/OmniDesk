//
//  VoiceActivationEngine.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 01/11/26.
//

import Foundation
import Combine
@preconcurrency import AVFoundation
import AppKit

/// Comprehensive state of the Voice Assistant Subsystem.
public enum ActivationState: Equatable, Sendable {
    case muted
    case listening
    case awake
    case recording
    case processing
    case awaitingApproval
    case executing
    case error(String)
}

/// Central orchestrator for on-demand hotkey voice activation (⌘⌥O), instant spoken acknowledgement ("Yes Boss"),
/// speech command capture, and resident Dynamic Island status synchronization.
@MainActor
public final class VoiceActivationEngine: ObservableObject {
    
    public static let shared = VoiceActivationEngine()
    
    private static let wakeWordEnabledKey = "omni_wake_word_enabled"
    private static let activeKeywordKey = "omni_active_keyword"
    private static let sensitivityKey = "omni_wake_word_sensitivity"
    
    // MARK: - Published State
    
    @Published public private(set) var state: ActivationState = .listening
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var lastCapturedCommand: String = ""
    @Published public var isMuted: Bool = false {
        didSet {
            handleMuteStateChanged()
        }
    }
    @Published public var isWakeWordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWakeWordEnabled, forKey: Self.wakeWordEnabledKey)
            handleWakeWordSettingChanged()
        }
    }
    
    // MARK: - Subsystems
    
    public let ringBuffer = AudioRingBuffer(sampleRate: 16000.0, windowDuration: 3.0)
    public let wakeDetector = ZipformerWakeWordDetector(config: .default)
    public let ackPlayer = WakeAcknowledgementPlayer.shared
    let voiceService = VoiceService.shared
    
    // Command Capture State
    private var commandRecordingStartTime: Date?
    private var silenceDuration: TimeInterval = 0.0
    private let maxCommandDuration: TimeInterval = 10.0
    private let silenceCutoffThreshold: TimeInterval = 1.2
    private var hasDetectedSpeech: Bool = false
    private var silenceTimer: Timer?
    private var wakeDetectionTimer: Timer?
    
    // Callbacks
    public var onCommandCaptured: ((String) -> Void)?
    public var onStateChanged: ((ActivationState) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization & Lifecycle
    
    public init() {
        self.isWakeWordEnabled = UserDefaults.standard.bool(forKey: Self.wakeWordEnabledKey)
        
        // Restore saved active keyword if configured
        if let savedKeyword = UserDefaults.standard.string(forKey: Self.activeKeywordKey) {
            var cfg = wakeDetector.config
            cfg.setActiveKeyword(savedKeyword)
            wakeDetector.updateConfig(cfg)
        }
        
        // Restore saved sensitivity if configured
        if let savedSensitivityStr = UserDefaults.standard.string(forKey: Self.sensitivityKey),
           let savedSensitivity = WakeWordSensitivity(rawValue: savedSensitivityStr) {
            var cfg = wakeDetector.config
            cfg.setSensitivity(savedSensitivity)
            wakeDetector.updateConfig(cfg)
        }
        
        setupVoiceServiceBinding()
        setupLifecycleObservers()
        
        if isWakeWordEnabled && !isMuted {
            startBackgroundWakeWordListening()
        }
    }
    
    deinit {
        silenceTimer?.invalidate()
        wakeDetectionTimer?.invalidate()
    }
    
    private func setupVoiceServiceBinding() {
        // Forward live audio level to visualizer
        voiceService.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self = self, self.state == .recording else { return }
                self.audioLevel = level
                self.evaluateSpeechEnergy(level: level)
            }
            .store(in: &cancellables)
        
        // Forward recognized transcript
        voiceService.$recognizedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self = self else { return }
                if !transcript.isEmpty {
                    self.lastCapturedCommand = transcript
                    self.hasDetectedSpeech = true
                    self.silenceDuration = 0.0 // Reset silence counter when text is actively updating
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Primary Hotkey Activation (⌘⌥O)
    
    /// Triggered by ⌘⌥O: Expands the island, speaks the acknowledgement ("Yes Boss"), then listens for the command.
    public func triggerHotkeyActivation() {
        if isMuted {
            isMuted = false
        }
        
        // If already recording, pressing hotkey again concludes and submits immediately
        if state == .recording {
            concludeCommandRecording()
            return
        }
        
        guard state != .awake && state != .processing else { return }
        
        // 1. Expand Resident Notch / Menu Bar Island
        DynamicIslandPanelController.shared.setExpanded(true)
        transition(to: .awake)
        
        // 2. Play instantaneous wake acknowledgement ("Yes boss")
        ackPlayer.playWakeAcknowledgement { [weak self] in
            guard let self = self else { return }
            self.beginCommandRecording()
        }
    }
    
    // MARK: - Wake-Word Activation ("Nexus")
    
    /// Triggered when the wake word "Nexus" is spotted from continuous audio evaluation.
    public func triggerWakeWordActivation(keyword: String = "NEXUS") {
        if isMuted {
            isMuted = false
        }
        
        guard state != .awake && state != .recording && state != .processing && state != .awaitingApproval else { return }
        
        // Strict Zero-Trust Safety Lock: Never trigger or alter an in-flight confirmation prompt
        guard SafetyPolicyGate.shared.activeRequest == nil else {
            print("🛡️ [SafetyPolicyGate] Wake word '\(keyword)' locked out during active confirmation window.")
            return
        }
        
        print("🎙️ Wake word detected: '\(keyword)' — expanding island and playing acknowledgement")
        
        // 1. Expand Resident Notch / Menu Bar Island
        DynamicIslandPanelController.shared.setExpanded(true)
        transition(to: .awake)
        
        // 2. Play instantaneous wake acknowledgement ("Yes boss")
        ackPlayer.playWakeAcknowledgement { [weak self] in
            guard let self = self else { return }
            self.beginCommandRecording()
        }
    }
    
    // MARK: - Background Wake Word Streaming
    
    private func handleWakeWordSettingChanged() {
        if isWakeWordEnabled {
            if !isMuted {
                startBackgroundWakeWordListening()
            }
        } else {
            stopBackgroundWakeWordListening()
        }
    }
    
    public func startBackgroundWakeWordListening() {
        guard isWakeWordEnabled, !isMuted else { return }
        voiceService.startIdleListening()
        startWakeDetectionTimer()
    }
    
    public func stopBackgroundWakeWordListening() {
        stopWakeDetectionTimer()
        if state != .recording {
            voiceService.stopIdleListening()
        }
    }
    
    private func startWakeDetectionTimer() {
        wakeDetectionTimer?.invalidate()
        wakeDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.evaluateBackgroundAudioForWakeWord()
        }
    }
    
    private func stopWakeDetectionTimer() {
        wakeDetectionTimer?.invalidate()
        wakeDetectionTimer = nil
    }
    
    public func evaluateBackgroundAudioForWakeWord() {
        guard isWakeWordEnabled, !isMuted else { return }
        guard state == .listening else { return }
        guard !ackPlayer.isAudioOutputPlaying else { return }
        guard SafetyPolicyGate.shared.activeRequest == nil else { return }
        
        // Read recent 1600 samples (100ms of 16kHz audio)
        let samples = ringBuffer.readRecent(count: 1600)
        guard samples.count >= 512 else { return }
        
        if let result = wakeDetector.process(samples: samples) {
            triggerWakeWordActivation(keyword: result.keyword)
        }
    }
    
    // MARK: - Configuration Updates
    
    public func setWakeWordSensitivity(_ sensitivity: WakeWordSensitivity) {
        var cfg = wakeDetector.config
        cfg.setSensitivity(sensitivity)
        wakeDetector.updateConfig(cfg)
        UserDefaults.standard.set(sensitivity.rawValue, forKey: Self.sensitivityKey)
    }
    
    public func setActiveKeywordPhrase(_ phrase: String) {
        var cfg = wakeDetector.config
        cfg.setActiveKeyword(phrase)
        wakeDetector.updateConfig(cfg)
        UserDefaults.standard.set(phrase, forKey: Self.activeKeywordKey)
    }
    
    // MARK: - Command Recording Lifecycle
    
    public func beginCommandRecording() {
        guard !isMuted else {
            transition(to: .muted)
            return
        }
        
        lastCapturedCommand = ""
        hasDetectedSpeech = false
        silenceDuration = 0.0
        commandRecordingStartTime = Date()
        transition(to: .recording)
        
        // Start speech dictation via VoiceService
        voiceService.startRecording()
        
        // Start 100ms cadence timer for end-of-speech silence detection on RunLoop.main
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkRecordingTimeout()
        }
    }
    
    private func evaluateSpeechEnergy(level: Float) {
        if level > 0.05 {
            hasDetectedSpeech = true
            silenceDuration = 0.0
        } else {
            silenceDuration += 0.05
        }
    }
    
    private func checkRecordingTimeout() {
        guard state == .recording else {
            silenceTimer?.invalidate()
            silenceTimer = nil
            return
        }
        
        let elapsed = Date().timeIntervalSince(commandRecordingStartTime ?? Date())
        
        // If user spoke and then fell silent for >= 1.2s, or if max 10.0s reached
        if (hasDetectedSpeech && silenceDuration >= silenceCutoffThreshold && elapsed > 1.2) || elapsed >= maxCommandDuration {
            concludeCommandRecording()
        }
    }
    
    public func concludeCommandRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        guard state == .recording else { return }
        voiceService.stopRecording()
        audioLevel = 0.0
        transition(to: .processing)
        
        let capturedQuery = lastCapturedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🎙️ Concluded recording with transcript: '\(capturedQuery)'")
        
        if capturedQuery.isEmpty {
            // If empty, return to listening after brief pause
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                if self.state == .processing {
                    self.transition(to: .listening)
                }
            }
        } else {
            onCommandCaptured?(capturedQuery)
        }
    }
    
    // MARK: - Mute & State Controls
    
    public func toggleMute() {
        isMuted.toggle()
    }
    
    private func handleMuteStateChanged() {
        if isMuted {
            if state == .recording {
                concludeCommandRecording()
            }
            stopBackgroundWakeWordListening()
            transition(to: .muted)
        } else {
            transition(to: .listening)
            if isWakeWordEnabled {
                startBackgroundWakeWordListening()
            }
        }
    }
    
    // MARK: - Lifecycle Observers
    
    private func setupLifecycleObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemSleep()
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAudioConfigurationChange()
            }
        }
    }
    
    public func handleSystemSleep() {
        print("💤 [VoiceActivationEngine] System sleep detected — pausing audio engine.")
        stopBackgroundWakeWordListening()
        voiceService.stopRecording()
    }
    
    public func handleSystemWake() {
        print("☀️ [VoiceActivationEngine] System wake detected — settling CoreAudio before re-arming.")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self.isWakeWordEnabled && !self.isMuted {
                self.startBackgroundWakeWordListening()
            }
        }
    }
    
    public func handleAudioConfigurationChange() {
        print("🎧 [VoiceActivationEngine] Audio route or hardware configuration changed.")
        Task { @MainActor in
            if self.state != .recording && self.isWakeWordEnabled && !self.isMuted {
                self.voiceService.stopIdleListening()
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.voiceService.startIdleListening()
            }
        }
    }
    
    public func transition(to newState: ActivationState) {
        guard self.state != newState else { return }
        self.state = newState
        onStateChanged?(newState)
    }
}
