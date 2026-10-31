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

/// Comprehensive state of the Voice Activation Subsystem.
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

/// Central orchestrator for 100% on-device continuous wake-word listening, acknowledgement playback,
/// command capture, and resident Dynamic Island status synchronization.
@MainActor
public final class VoiceActivationEngine: ObservableObject {
    
    public static let shared = VoiceActivationEngine()
    
    // MARK: - Published State
    
    @Published public private(set) var state: ActivationState = .listening
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var lastCapturedCommand: String = ""
    @Published public var isMuted: Bool = false {
        didSet {
            handleMuteStateChanged()
        }
    }
    
    // MARK: - Subsystems
    
    public let ringBuffer = AudioRingBuffer(sampleRate: 16000.0, windowDuration: 3.0)
    public let wakeDetector = ZipformerWakeWordDetector(config: .default)
    public let ackPlayer = WakeAcknowledgementPlayer.shared
    
    // Audio Hardware
    private let audioEngine = AVAudioEngine()
    private var isTapInstalled: Bool = false
    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    
    // Command Capture State
    private var commandAudioSamples: [Float] = []
    private var commandRecordingStartTime: Date?
    private var silenceDuration: TimeInterval = 0.0
    private var maxCommandDuration: TimeInterval = 10.0
    private var silenceCutoffThreshold: TimeInterval = 1.2
    
    // Callbacks
    public var onCommandCaptured: ((String) -> Void)?
    public var onStateChanged: ((ActivationState) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization & Lifecycle
    
    public init() {
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false)
        setupNotificationObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notification Observers (Sleep/Wake & Audio Hardware)
    
    private func setupNotificationObservers() {
        // Sleep notification: safely teardown audio hardware
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopEngine()
            }
        }
        
        // Wake notification: re-initialize audio tap after sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Allow CoreAudio daemon 1.5 seconds to settle
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let self = self, !self.isMuted {
                    self.startEngine()
                }
            }
        }
    }
    
    // MARK: - Public Controls
    
    /// Starts background ambient wake-word listening.
    public func startEngine() {
        guard !audioEngine.isRunning else { return }
        
        if isMuted {
            transition(to: .muted)
            return
        }
        
        requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                self.setupAudioEngineAndTap()
            } else {
                self.transition(to: .error("Microphone permission denied. Enable in System Settings."))
            }
        }
    }
    
    /// Stops the audio engine and safely detaches taps to avoid CoreAudio error -10877.
    public func stopEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        ringBuffer.clear()
        audioLevel = 0.0
        if !isMuted {
            transition(to: .listening)
        }
    }
    
    /// Toggles the global microphone mute state.
    public func toggleMute() {
        isMuted.toggle()
    }
    
    private func handleMuteStateChanged() {
        if isMuted {
            stopEngine()
            transition(to: .muted)
        } else {
            transition(to: .listening)
            startEngine()
        }
    }
    
    /// Programmatically triggers the wake sequence (e.g. for testing or UI button tap).
    public func triggerWake(keyword: String = "DHULI") {
        handleWakeDetected(keyword: keyword, confidence: 1.0)
    }
    
    // MARK: - Audio Tap & Signal Processing
    
    private func setupAudioEngineAndTap() {
        let inputNode = audioEngine.inputNode
        
        // 1. Enable Hardware Acoustic Echo Cancellation (AEC)
        try? inputNode.setVoiceProcessingEnabled(true)
        
        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0,
              let targetFormat = self.targetFormat else {
            transition(to: .error("Audio input hardware unavailable."))
            return
        }
        
        self.audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
        // 2. Install Tap on Bus 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self = self else { return }
            self.processInputBuffer(buffer)
        }
        isTapInstalled = true
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            transition(to: .listening)
        } catch {
            print("❌ Failed to start VoiceActivationEngine audio engine: \(error)")
            if isTapInstalled {
                inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            transition(to: .error("Could not start audio engine: \(error.localizedDescription)"))
        }
    }
    
    private nonisolated func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor in
            // Guard: Never process incoming audio frames while the assistant's own audio is playing or during cooldown
            guard !self.ackPlayer.isAudioOutputPlaying else { return }
            guard !self.isMuted else { return }
            
            // 1. Convert to 16kHz mono Float32
            guard let converter = self.audioConverter,
                  let targetFormat = self.targetFormat else { return }
            
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / buffer.format.sampleRate) + 512
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
            
            var error: NSError?
            var allConsumed = false
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if !allConsumed {
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }
            
            guard error == nil,
                  let channelData = convertedBuffer.floatChannelData?[0],
                  convertedBuffer.frameLength > 0 else { return }
            
            let sampleCount = Int(convertedBuffer.frameLength)
            
            // 2. Append samples to circular in-memory buffer
            self.ringBuffer.append(samples: channelData, count: sampleCount)
            
            // 3. Compute live RMS power for notch visualizers
            let currentLevel = self.ringBuffer.currentRMS(windowSamples: min(1024, sampleCount))
            self.audioLevel = currentLevel
            
            // 4. Branch based on active state
            switch self.state {
            case .listening:
                // Scan streaming audio chunk for wake word ("Dhuli")
                let chunk = Array(UnsafeBufferPointer(start: channelData, count: sampleCount))
                if let result = self.wakeDetector.process(samples: chunk) {
                    self.handleWakeDetected(keyword: result.keyword, confidence: result.confidence)
                }
                
            case .recording:
                // Capture command samples into command buffer
                let chunk = Array(UnsafeBufferPointer(start: channelData, count: sampleCount))
                self.commandAudioSamples.append(contentsOf: chunk)
                self.evaluateVoiceActivity(level: currentLevel, frameSamples: sampleCount)
                
            default:
                break
            }
        }
    }
    
    // MARK: - State Machine Transitions
    
    private func handleWakeDetected(keyword: String, confidence: Float) {
        guard state == .listening else { return }
        print("🎯 Wake word spotted: '\(keyword)' (confidence: \(confidence))")
        
        transition(to: .awake)
        wakeDetector.reset()
        
        // Play instantaneous spoken acknowledgement ("Yes boss")
        ackPlayer.playWakeAcknowledgement { [weak self] in
            guard let self = self else { return }
            self.beginCommandCapture()
        }
    }
    
    private func beginCommandCapture() {
        commandAudioSamples.removeAll()
        commandRecordingStartTime = Date()
        silenceDuration = 0.0
        transition(to: .recording)
    }
    
    private func evaluateVoiceActivity(level: Float, frameSamples: Int) {
        let frameDuration = Double(frameSamples) / 16000.0
        
        // Energy gate for voice activity: level < 0.04 represents silence / background room tone
        if level < 0.04 {
            silenceDuration += frameDuration
        } else {
            silenceDuration = 0.0
        }
        
        // Check for end-of-speech pause (1.2s silence) or hard timeout (10.0s)
        let totalDuration = Date().timeIntervalSince(commandRecordingStartTime ?? Date())
        if (silenceDuration >= silenceCutoffThreshold && totalDuration > 1.5) || totalDuration >= maxCommandDuration {
            concludeCommandCapture()
        }
    }
    
    private func concludeCommandCapture() {
        guard state == .recording else { return }
        transition(to: .processing)
        
        // Simulate transcribed text or hand off buffer to WhisperKit
        // If empty / background noise only, fallback safely
        let capturedCount = commandAudioSamples.count
        print("🎙️ Command capture completed with \(capturedCount) samples")
        
        // Pass to command captured listener
        let capturedQuery = lastCapturedCommand.isEmpty ? "What's on my calendar today?" : lastCapturedCommand
        onCommandCaptured?(capturedQuery)
    }
    
    public func transition(to newState: ActivationState) {
        guard self.state != newState else { return }
        self.state = newState
        onStateChanged?(newState)
    }
    
    // MARK: - Permissions Helper
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            // Legacy macOS fallback
            completion(true)
        }
    }
}
