//
//  TTSVoiceConfig.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 04/11/26.
//

import AVFoundation
import Foundation

/// Configuration settings for local Text-to-Speech (TTS) synthesis, voice selection,
/// and hardware DSP Acoustic Echo Cancellation (AEC).
public struct TTSVoiceConfig: Sendable, Equatable {
    
    public static let voiceFeedbackEnabledKey = "omni_tts_voice_feedback_enabled"
    public static let speechRateKey = "omni_tts_speech_rate"
    public static let pitchMultiplierKey = "omni_tts_pitch_multiplier"
    public static let selectedVoiceIdKey = "omni_tts_selected_voice_id"
    public static let echoCancellationEnabledKey = "omni_tts_echo_cancellation_enabled"
    
    /// Whether OmniDesk speaks dynamic task completions and status confirmations aloud.
    public var isVoiceFeedbackEnabled: Bool
    
    /// Speech synthesis speed (natural conversational range: 0.35 slow to 0.60 fast; default: 0.46).
    public var speechRate: Float
    
    /// Speech pitch multiplier (natural range: 0.75 low to 1.25 high; default: 1.0).
    public var pitchMultiplier: Float
    
    /// Optional AVSpeechSynthesisVoice identifier chosen by the user (or nil for system default).
    public var selectedVoiceIdentifier: String?
    
    /// Whether macOS VoiceProcessingIO hardware DSP acoustic echo cancellation is enabled on inputNode.
    public var isEchoCancellationEnabled: Bool
    
    public static let `default` = TTSVoiceConfig(
        isVoiceFeedbackEnabled: true,
        speechRate: 0.46,
        pitchMultiplier: 1.0,
        selectedVoiceIdentifier: nil,
        isEchoCancellationEnabled: true
    )
    
    public init(
        isVoiceFeedbackEnabled: Bool = true,
        speechRate: Float = 0.46,
        pitchMultiplier: Float = 1.0,
        selectedVoiceIdentifier: String? = nil,
        isEchoCancellationEnabled: Bool = true
    ) {
        self.isVoiceFeedbackEnabled = isVoiceFeedbackEnabled
        self.speechRate = min(max(speechRate, 0.30), 0.65)
        self.pitchMultiplier = min(max(pitchMultiplier, 0.70), 1.30)
        self.selectedVoiceIdentifier = selectedVoiceIdentifier
        self.isEchoCancellationEnabled = isEchoCancellationEnabled
    }
    
    /// Loads persisted settings from UserDefaults or returns standard defaults.
    public static func loadPersisted() -> TTSVoiceConfig {
        var config = TTSVoiceConfig.default
        
        if UserDefaults.standard.object(forKey: voiceFeedbackEnabledKey) != nil {
            config.isVoiceFeedbackEnabled = UserDefaults.standard.bool(forKey: voiceFeedbackEnabledKey)
        }
        
        let savedRate = UserDefaults.standard.float(forKey: speechRateKey)
        if savedRate > 0.1 {
            config.speechRate = min(max(savedRate, 0.30), 0.65)
        }
        
        let savedPitch = UserDefaults.standard.float(forKey: pitchMultiplierKey)
        if savedPitch > 0.1 {
            config.pitchMultiplier = min(max(savedPitch, 0.70), 1.30)
        }
        
        if let savedVoiceId = UserDefaults.standard.string(forKey: selectedVoiceIdKey), !savedVoiceId.isEmpty {
            config.selectedVoiceIdentifier = savedVoiceId
        }
        
        if UserDefaults.standard.object(forKey: echoCancellationEnabledKey) != nil {
            config.isEchoCancellationEnabled = UserDefaults.standard.bool(forKey: echoCancellationEnabledKey)
        }
        
        return config
    }
    
    /// Persists the current configuration to UserDefaults.
    public func persist() {
        UserDefaults.standard.set(isVoiceFeedbackEnabled, forKey: Self.voiceFeedbackEnabledKey)
        UserDefaults.standard.set(speechRate, forKey: Self.speechRateKey)
        UserDefaults.standard.set(pitchMultiplier, forKey: Self.pitchMultiplierKey)
        if let voiceId = selectedVoiceIdentifier {
            UserDefaults.standard.set(voiceId, forKey: Self.selectedVoiceIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedVoiceIdKey)
        }
        UserDefaults.standard.set(isEchoCancellationEnabled, forKey: Self.echoCancellationEnabledKey)
    }
}
