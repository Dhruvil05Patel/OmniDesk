//
//  WakeAcknowledgementPlayer.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 01/11/26.
//

import AVFoundation
import Combine
import Foundation

/// Item representing an installed system TTS voice available for selection in OmniDesk.
public struct AvailableVoiceItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: String
    
    public init(id: String, name: String, language: String, quality: String) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }
}

/// Handles instantaneous spoken wake acknowledgements ("Yes boss") and voice responses with echo suppression.
@MainActor
public final class WakeAcknowledgementPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    
    public static let shared = WakeAcknowledgementPlayer()
    
    /// Pre-rendered acknowledgment phrase choices.
    public enum AckPhrase: String, CaseIterable, Sendable {
        case yesBoss = "Yes boss"
        case listening = "Listening"
        case rightHere = "Right here"
        case onIt = "On it"
    }
    
    @Published public private(set) var isAudioOutputPlaying: Bool = false
    @Published public var selectedPhrase: AckPhrase = .yesBoss
    @Published public var randomizePhrase: Bool = false
    @Published public var ttsConfig: TTSVoiceConfig = .loadPersisted()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var onPlaybackFinished: (@MainActor () -> Void)?
    
    /// Statically cached default voice instance to prevent repeated synchronous XPC IPC calls to speechsynthesisd
    private static let defaultVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "en-US")
    
    /// Cached voice map for instantaneous lookup
    private var cachedVoices: [String: AVSpeechSynthesisVoice] = [:]
    
    /// The mandatory refractory cooldown period in seconds following audio output before listening re-arms.
    public let refractoryCooldownSeconds: TimeInterval = 0.5
    
    public override init() {
        super.init()
        speechSynthesizer.delegate = self
        preloadVoiceCache()
    }
    
    private func preloadVoiceCache() {
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            cachedVoices[voice.identifier] = voice
        }
    }
    
    /// Returns installed candidate voices sorted by naturalness and language relevance.
    public func fetchAvailableVoices() -> [AvailableVoiceItem] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let relevantLanguages = Set(["en-US", "en-GB", "en-AU", "en-IN", "hi-IN", "gu-IN"])
        
        let filtered = allVoices.filter { relevantLanguages.contains($0.language) || $0.language.hasPrefix("en-") }
        
        return filtered.map { voice in
            let qualityStr: String
            switch voice.quality {
            case .enhanced: qualityStr = "Enhanced"
            case .premium: qualityStr = "Premium"
            default: qualityStr = "Standard"
            }
            return AvailableVoiceItem(
                id: voice.identifier,
                name: voice.name,
                language: voice.language,
                quality: qualityStr
            )
        }.sorted { $0.name < $1.name }
    }
    
    /// Updates the active TTS voice and echo cancellation configuration.
    public func updateTTSConfig(_ newConfig: TTSVoiceConfig) {
        self.ttsConfig = newConfig
        newConfig.persist()
        VoiceService.shared.setEchoCancellationEnabled(newConfig.isEchoCancellationEnabled)
    }
    
    /// Plays an instantaneous wake acknowledgement ("Yes boss") and triggers a callback when the audio and cooldown finish.
    public func playWakeAcknowledgement(completion: (@MainActor () -> Void)? = nil) {
        self.onPlaybackFinished = completion
        self.isAudioOutputPlaying = true
        
        let phraseToSpeak: String
        if randomizePhrase {
            phraseToSpeak = AckPhrase.allCases.randomElement()?.rawValue ?? selectedPhrase.rawValue
        } else {
            phraseToSpeak = selectedPhrase.rawValue
        }
        
        // 1. Check for bundled pre-rendered audio asset first (for instant <10ms latency)
        let assetName = phraseToSpeak.lowercased().replacingOccurrences(of: " ", with: "_")
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: assetName, withExtension: "caf"),
            Bundle.main.resourceURL?.appendingPathComponent("\(assetName).caf"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(assetName).caf"),
            Bundle(for: WakeAcknowledgementPlayer.self).url(forResource: assetName, withExtension: "caf"),
            URL(fileURLWithPath: "OmniDesk/\(assetName).caf")
        ]
        
        for candidate in candidateURLs.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: candidate)
                    audioPlayer?.delegate = self
                    audioPlayer?.prepareToPlay()
                    audioPlayer?.play()
                    return
                } catch {
                    print("⚠️ Pre-rendered audio playback failed: \(error)")
                }
            }
        }
        
        // 2. High-quality system speech synthesizer fallback
        let utterance = AVSpeechUtterance(string: phraseToSpeak)
        utterance.rate = ttsConfig.speechRate
        utterance.pitchMultiplier = ttsConfig.pitchMultiplier
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        
        if let voiceId = ttsConfig.selectedVoiceIdentifier, let customVoice = cachedVoices[voiceId] {
            utterance.voice = customVoice
        } else if let voice = Self.defaultVoice {
            utterance.voice = voice
        }
        
        speechSynthesizer.speak(utterance)
    }
    
    /// Vocalizes arbitrary feedback text (e.g. task creation or calendar event summaries).
    public func speakText(_ text: String, completion: (@MainActor () -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }
        
        // Respect user setting: if voice feedback is disabled, skip speech
        guard ttsConfig.isVoiceFeedbackEnabled else {
            completion?()
            return
        }
        
        self.onPlaybackFinished = completion
        self.isAudioOutputPlaying = true
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = ttsConfig.speechRate
        utterance.pitchMultiplier = ttsConfig.pitchMultiplier
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05 // Allows CoreAudio AudioQueue to buffer initial packets before DAC starts rendering
        
        if let voiceId = ttsConfig.selectedVoiceIdentifier, let customVoice = cachedVoices[voiceId] {
            utterance.voice = customVoice
        } else if let voice = Self.defaultVoice {
            utterance.voice = voice
        }
        
        speechSynthesizer.speak(utterance)
    }
    
    /// Stops any ongoing playback immediately and clears the audio lock.
    public func stopAllPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        isAudioOutputPlaying = false
        onPlaybackFinished = nil
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.handlePlaybackCompleted()
        }
    }
    
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.handlePlaybackCompleted()
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.handlePlaybackCompleted()
        }
    }
    
    // MARK: - Cooldown & AudioQueue Drain Barrier
    
    private func handlePlaybackCompleted() {
        Task { @MainActor in
            // 1. Wait until synthesizer finishes actively generating frames
            while self.speechSynthesizer.isSpeaking {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms polling
            }
            
            // 2. Enforce the hardware audio drain barrier + refractory cooldown
            // Ensures physical CoreAudio DAC buffers drain completely before input capture starts
            try? await Task.sleep(nanoseconds: UInt64(self.refractoryCooldownSeconds * 1_000_000_000))
            
            self.isAudioOutputPlaying = false
            let callback = self.onPlaybackFinished
            self.onPlaybackFinished = nil
            callback?()
        }
    }
}
