//
//  WhisperKitConfig.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 02/11/26.
//

import Foundation

/// Available Whisper model variants optimized for Apple Silicon Core ML and Apple Neural Engine (ANE).
public enum WhisperModelTier: String, CaseIterable, Identifiable, Sendable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .tiny:
            return "Whisper Tiny (~75 MB)"
        case .base:
            return "Whisper Base (~145 MB, Recommended)"
        case .small:
            return "Whisper Small (~460 MB)"
        }
    }
    
    public var shortName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        }
    }
    
    public var description: String {
        switch self {
        case .tiny:
            return "Ultra-low latency (<80ms). Ideal for short English-dominant voice commands."
        case .base:
            return "Balanced accuracy and speed (<150ms on ANE). Reliable on Hindi, Gujarati & Hinglish."
        case .small:
            return "Maximum linguistic precision for heavy code-switching and accented dialects (~280ms on ANE)."
        }
    }
    
    public var modelSizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 145
        case .small: return 460
        }
    }
}

/// Target language decoding preferences for WhisperKit tokenization.
public enum WhisperLanguageOption: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case english = "en"
    case hindi = "hi"
    case gujarati = "gu"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .auto:
            return "Auto-Detect / Hinglish (Code-Switching)"
        case .english:
            return "English (en)"
        case .hindi:
            return "Hindi (hi - हिन्दी)"
        case .gujarati:
            return "Gujarati (gu - ગુજરાતી)"
        }
    }
    
    public var codeHint: String? {
        return self == .auto ? nil : rawValue
    }
}

/// Configuration settings for on-device WhisperKit transcription.
public struct WhisperKitConfig: Sendable, Equatable {
    
    public static let engineTypeKey = "omni_speech_engine_type"
    public static let modelTierKey = "omni_whisper_model_tier"
    public static let languageKey = "omni_whisper_language"
    public static let fallbackToSystemKey = "omni_whisper_fallback_to_system"
    
    public var selectedEngine: SpeechEngineType
    public var modelTier: WhisperModelTier
    public var languageOption: WhisperLanguageOption
    public var fallbackToSystemSpeech: Bool
    public var temperature: Float
    public var sampleRate: Double
    
    public static let `default` = WhisperKitConfig(
        selectedEngine: .whisperKit,
        modelTier: .base,
        languageOption: .auto,
        fallbackToSystemSpeech: true,
        temperature: 0.0,
        sampleRate: 16000.0
    )
    
    public init(
        selectedEngine: SpeechEngineType = .whisperKit,
        modelTier: WhisperModelTier = .base,
        languageOption: WhisperLanguageOption = .auto,
        fallbackToSystemSpeech: Bool = true,
        temperature: Float = 0.0,
        sampleRate: Double = 16000.0
    ) {
        self.selectedEngine = selectedEngine
        self.modelTier = modelTier
        self.languageOption = languageOption
        self.fallbackToSystemSpeech = fallbackToSystemSpeech
        self.temperature = temperature
        self.sampleRate = sampleRate
    }
    
    /// Loads configuration from UserDefaults or returns the default.
    public static func loadPersisted() -> WhisperKitConfig {
        var config = WhisperKitConfig.default
        
        if let engineRaw = UserDefaults.standard.string(forKey: engineTypeKey),
           let engine = SpeechEngineType(rawValue: engineRaw) {
            config.selectedEngine = engine
        }
        
        if let modelRaw = UserDefaults.standard.string(forKey: modelTierKey),
           let tier = WhisperModelTier(rawValue: modelRaw) {
            config.modelTier = tier
        }
        
        if let langRaw = UserDefaults.standard.string(forKey: languageKey),
           let lang = WhisperLanguageOption(rawValue: langRaw) {
            config.languageOption = lang
        }
        
        if UserDefaults.standard.object(forKey: fallbackToSystemKey) != nil {
            config.fallbackToSystemSpeech = UserDefaults.standard.bool(forKey: fallbackToSystemKey)
        }
        
        return config
    }
    
    /// Saves the current configuration to UserDefaults.
    public func persist() {
        UserDefaults.standard.set(selectedEngine.rawValue, forKey: Self.engineTypeKey)
        UserDefaults.standard.set(modelTier.rawValue, forKey: Self.modelTierKey)
        UserDefaults.standard.set(languageOption.rawValue, forKey: Self.languageKey)
        UserDefaults.standard.set(fallbackToSystemSpeech, forKey: Self.fallbackToSystemKey)
    }
}
