//
//  WakeAcknowledgementPlayer.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 01/11/26.
//

import Foundation
import Combine
import AVFoundation

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
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var onPlaybackFinished: (@MainActor () -> Void)?
    
    /// The mandatory refractory cooldown period in seconds following audio output before listening re-arms.
    public let refractoryCooldownSeconds: TimeInterval = 0.5
    
    public override init() {
        super.init()
        speechSynthesizer.delegate = self
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
        if let audioURL = Bundle.main.url(forResource: assetName, withExtension: "caf") ??
                          Bundle.main.url(forResource: assetName, withExtension: "wav") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                return
            } catch {
                print("⚠️ Pre-rendered audio playback failed, falling back to AVSpeechSynthesizer: \(error)")
            }
        }
        
        // 2. High-quality system speech synthesizer fallback
        let utterance = AVSpeechUtterance(string: phraseToSpeak)
        utterance.rate = 0.55 // Natural, brisk response
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        
        // Select preferred English voice
        if let preferredVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = preferredVoice
        }
        
        speechSynthesizer.speak(utterance)
    }
    
    /// Vocalizes arbitrary feedback text (e.g. task creation or calendar event summaries).
    public func speakText(_ text: String, completion: (@MainActor () -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }
        
        self.onPlaybackFinished = completion
        self.isAudioOutputPlaying = true
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.volume = 1.0
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
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
    
    // MARK: - Cooldown & State Transition
    
    private func handlePlaybackCompleted() {
        // Enforce the 500ms refractory cooldown before re-arming the wake detector
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(self.refractoryCooldownSeconds * 1_000_000_000))
            self.isAudioOutputPlaying = false
            let callback = self.onPlaybackFinished
            self.onPlaybackFinished = nil
            callback?()
        }
    }
}
