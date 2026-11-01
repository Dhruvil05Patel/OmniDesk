//
//  VoiceService.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import Foundation
import Combine
import Speech
import AVFoundation

enum VoiceState: Equatable {
    case idle
    case idleListening
    case recording
    case permissionDenied(String)
}

@MainActor
class VoiceService: ObservableObject {
    
    public static let shared = VoiceService()
    
    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isTapInstalled: Bool = false
    private var isTransitioning: Bool = false
    private var isListening: Bool = false
    private var levelTimer: Timer?
    
    @Published var recognizedText: String = ""
    @Published var state: VoiceState = .idle
    @Published var audioLevel: Float = 0.0
    
    func toggleRecording() {
        if state == .recording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    // MARK: - Idle Background Listening (Wake Word Mode)
    
    /// Starts low-power background microphone capture feeding the shared AudioRingBuffer for wake-word detection.
    /// Runs strictly on-device without allocating an SFSpeechAudioBufferRecognitionRequest.
    func startIdleListening() {
        guard !isTransitioning else { return }
        guard state != .recording else { return }
        if isTapInstalled && audioEngine.isRunning {
            self.state = .idleListening
            self.isListening = true
            return
        }
        
        isTransitioning = true
        
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isTransitioning = false
                    if granted {
                        self.beginAudioEngineIdleListening()
                    } else {
                        self.state = .permissionDenied("Microphone permission denied.")
                    }
                }
            }
        } else {
            isTransitioning = false
            beginAudioEngineIdleListening()
        }
    }
    
    private func beginAudioEngineIdleListening() {
        if isTapInstalled && audioEngine.isRunning {
            self.state = .idleListening
            self.isListening = true
            return
        }
        
        let inputNode = audioEngine.inputNode
        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("❌ CoreAudio device not ready. SampleRate is 0.")
            self.state = .permissionDenied("Microphone not ready. Please check System Settings > Privacy & Security > Microphone.")
            return
        }
        
        self.isListening = true
        
        // Real-Time Audio Tap: 0 allocations, 0 locks, 0 actor hops
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self = self, self.isListening else { return }
            
            guard buffer.frameLength > 0,
                  buffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0,
                  let channelData = buffer.floatChannelData?[0] else {
                return
            }
            
            // Forward to active dictation if present
            self.recognitionRequest?.append(buffer)
            
            // Lock-free append to shared ring buffer for wake-word spotting
            VoiceActivationEngine.shared.ringBuffer.append(samples: channelData, count: Int(buffer.frameLength))
        }
        isTapInstalled = true
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            self.state = .idleListening
        } catch {
            print("❌ Idle Audio Engine Start Error:", error)
            self.state = .permissionDenied("Could not start background microphone: \(error.localizedDescription)")
            self.isListening = false
            if isTapInstalled {
                inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
        }
    }
    
    /// Stops idle background listening completely, releasing the CoreAudio input tap.
    func stopIdleListening() {
        guard state == .idleListening || (isTapInstalled && state != .recording) else { return }
        self.isListening = false
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        self.state = .idle
    }
    
    // MARK: - Active Command Recording (Dictation Mode)
    
    func startRecording() {
        guard !isTransitioning else { return }
        
        if state == .recording {
            stopRecording()
        }
        
        isTransitioning = true
        
        // Request Speech Recognition Authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isTransitioning = false
                
                switch speechStatus {
                case .authorized:
                    self.requestMicrophoneAndRecord()
                case .denied:
                    self.state = .permissionDenied("Speech recognition permission denied.")
                case .restricted:
                    self.state = .permissionDenied("Speech recognition is restricted on this device.")
                case .notDetermined:
                    self.state = .permissionDenied("Speech recognition permission not determined.")
                @unknown default:
                    self.state = .permissionDenied("Unknown authorization status.")
                }
            }
        }
    }
    
    private func requestMicrophoneAndRecord() {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if granted {
                        self.beginAudioEngineRecording()
                    } else {
                        self.state = .permissionDenied("Microphone permission denied.")
                    }
                }
            }
        } else {
            beginAudioEngineRecording()
        }
    }
    
    private func beginAudioEngineRecording() {
        // Reset state & text
        recognizedText = ""
        audioLevel = 0.0
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                Task { @MainActor [weak self] in
                    self?.recognizedText = result.bestTranscription.formattedString
                }
            }
        }
        
        // If tap is already active from background idle listening, seamlessly transition
        if isTapInstalled && audioEngine.isRunning {
            self.state = .recording
            self.isListening = true
            startLevelPolling()
            return
        }
        
        let inputNode = audioEngine.inputNode
        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Guard against uninitialized / sandbox-restricted audio hardware
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("❌ CoreAudio device not ready. SampleRate is 0.")
            self.state = .permissionDenied("Microphone not ready. Please check System Settings > Privacy & Security > Microphone.")
            return
        }
        
        self.isListening = true
        
        // Real-Time Audio Tap: 0 allocations, 0 locks, 0 actor hops
        // Use recordingFormat (outputFormat for Bus 0) to prevent -10877 (kAudioUnitErr_InvalidElement)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            guard let self = self, self.isListening else { return }
            
            // 1. Strict pre-flight checks: frameLength > 0, buffer byte size > 0, floatChannelData non-nil
            // Eliminates AVAudioBuffer.mm:291 mBuffers[0].mDataByteSize (0) should be non-zero
            guard buffer.frameLength > 0,
                  buffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0,
                  let channelData = buffer.floatChannelData?[0] else {
                return
            }
            
            // 2. Append buffer to speech recognition request
            self.recognitionRequest?.append(buffer)
            
            // 3. Append samples to shared AudioRingBuffer without allocations or locks
            VoiceActivationEngine.shared.ringBuffer.append(samples: channelData, count: Int(buffer.frameLength))
        }
        isTapInstalled = true
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            self.state = .recording
            startLevelPolling()
        } catch {
            print("❌ Audio Engine Start Error:", error)
            self.state = .permissionDenied("Could not start microphone: \(error.localizedDescription)")
            self.isListening = false
            if isTapInstalled {
                inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
        }
    }
    
    private func startLevelPolling() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .recording else { return }
            let currentLevel = VoiceActivationEngine.shared.ringBuffer.currentRMS(windowSamples: 1024)
            self.audioLevel = currentLevel
        }
    }
    
    private func stopLevelPolling() {
        levelTimer?.invalidate()
        levelTimer = nil
        self.audioLevel = 0.0
    }
    
    func stopRecording() {
        guard state == .recording || isTapInstalled || audioEngine.isRunning else {
            return
        }
        
        stopLevelPolling()
        
        // 1. Signal clean end of audio stream to speech recognizer
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 2. If wake word is enabled and not muted, seamlessly drop back to idle listening
        if VoiceActivationEngine.shared.isWakeWordEnabled && !VoiceActivationEngine.shared.isMuted {
            self.state = .idleListening
            self.isListening = true
            return
        }
        
        // 3. Otherwise completely tear down audio tap and engine
        self.isListening = false
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        self.state = .idle
    }
}
