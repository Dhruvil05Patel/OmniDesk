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

class VoiceService: ObservableObject {
    
    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var recognizedText: String = ""
    
    func startRecording() {
        
        if audioEngine.isRunning {
            stopRecording()
        }
        
        // 🔴 Request BOTH permissions properly
        
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            
            DispatchQueue.main.async {
                
                switch speechStatus {
                case .authorized:
                    print("Speech authorized")
                    self.record()
                    
                case .denied:
                    print("Speech denied")
                    
                case .restricted:
                    print("Speech restricted")
                    
                case .notDetermined:
                    print("Speech not determined")
                    
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func record() {
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        
        request.shouldReportPartialResults = true
        
        // 🔴 Cancel previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 🔴 REMOVE old tap before adding new
        inputNode.removeTap(onBus: 0)
        
        inputNode.volume = 1.0
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("Audio Engine Error:", error)
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
    }
}
