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
    case recording
    case permissionDenied(String)
}

class VoiceService: ObservableObject {
    
    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
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
    
    func startRecording() {
        if audioEngine.isRunning {
            stopRecording()
        }
        
        // Request Speech Recognition Authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
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
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if granted {
                        self.beginAudioEngineRecording()
                    } else {
                        self.state = .permissionDenied("Microphone permission denied.")
                    }
                }
            }
        } else {
            // macOS 13 or earlier fallback
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
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                // If audio finished
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            request.append(buffer)
            
            // Calculate RMS power for audio level meter
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = UInt(buffer.frameLength)
                var sum: Float = 0.0
                if frameLength > 0 {
                    for i in 0..<Int(frameLength) {
                        sum += channelData[i] * channelData[i]
                    }
                    let rms = sqrt(sum / Float(frameLength))
                    // Scale and clamp to 0.0 ... 1.0
                    let normalizedLevel = min(max(rms * 6.0, 0.0), 1.0)
                    DispatchQueue.main.async {
                        self.audioLevel = normalizedLevel
                    }
                }
            }
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            self.state = .recording
        } catch {
            print("❌ Audio Engine Error:", error)
            self.state = .permissionDenied("Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
        }
    }
    
    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        DispatchQueue.main.async {
            self.audioLevel = 0.0
            self.state = .idle
        }
    }
}
