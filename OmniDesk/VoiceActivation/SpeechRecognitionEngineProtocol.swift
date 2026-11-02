//
//  SpeechRecognitionEngineProtocol.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 02/11/26.
//

import Foundation

/// Defines the underlying speech recognition engine types supported in OmniDesk.
public enum SpeechEngineType: String, CaseIterable, Identifiable, Sendable {
    case appleSystem = "Apple System Speech"
    case whisperKit = "WhisperKit (On-Device ANE)"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .appleSystem:
            return "Apple System Speech (Built-in)"
        case .whisperKit:
            return "WhisperKit (On-Device Core ML / ANE)"
        }
    }
    
    public var summary: String {
        switch self {
        case .appleSystem:
            return "Native Speech.framework dictation. Zero download size; best for basic English."
        case .whisperKit:
            return "100% offline Whisper model on Apple Neural Engine. Superior for Hindi, Gujarati & Hinglish."
        }
    }
}

/// Unified abstraction protocol for speech recognition and transcription engines.
public protocol SpeechRecognitionEngineProtocol: Sendable {
    
    /// The engine type identifier.
    var engineType: SpeechEngineType { get }
    
    /// Whether the engine is available and ready for inference on this device.
    var isAvailable: Bool { get }
    
    /// Prepares or loads the underlying model weights into memory.
    func prepare() async throws
    
    /// Transcribes an array of 16,000 Hz Float32 audio samples into text.
    /// - Parameters:
    ///   - audioSamples: Linear PCM float samples normalized to [-1.0, 1.0].
    ///   - sampleRate: The sampling rate of the provided samples (default: 16,000 Hz).
    ///   - language: Optional language code hint (e.g. "en", "hi", "gu", or nil for auto-detect).
    /// - Returns: The transcribed string transcript.
    func transcribe(
        audioSamples: [Float],
        sampleRate: Double,
        language: String?
    ) async throws -> String
    
    /// Resets any ongoing recognition tasks or caches.
    func reset()
}
