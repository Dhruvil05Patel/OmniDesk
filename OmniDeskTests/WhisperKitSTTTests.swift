//
//  WhisperKitSTTTests.swift
//  OmniDeskTests
//
//  Created by Dhruvil Patel on 02/11/26.
//

import XCTest
@testable import OmniDesk

final class WhisperKitSTTTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockWhisperTranscriptStore.shared.setMockTranscript(nil)
    }

    override func tearDown() {
        MockWhisperTranscriptStore.shared.setMockTranscript(nil)
        super.tearDown()
    }

    // MARK: - Configuration & Persistence Tests

    func testWhisperKitConfigDefaultsAndPersistence() {
        let config = WhisperKitConfig(
            selectedEngine: .whisperKit,
            modelTier: .base,
            languageOption: .auto,
            fallbackToSystemSpeech: true,
            temperature: 0.0,
            sampleRate: 16000.0
        )
        
        config.persist()
        let loaded = WhisperKitConfig.loadPersisted()
        
        XCTAssertEqual(loaded.selectedEngine, .whisperKit)
        XCTAssertEqual(loaded.modelTier, .base)
        XCTAssertEqual(loaded.languageOption, .auto)
        XCTAssertTrue(loaded.fallbackToSystemSpeech)
        XCTAssertEqual(loaded.sampleRate, 16000.0)
    }

    func testModelTierCharacteristics() {
        XCTAssertEqual(WhisperModelTier.tiny.shortName, "Tiny")
        XCTAssertEqual(WhisperModelTier.tiny.modelSizeMB, 75)
        
        XCTAssertEqual(WhisperModelTier.base.shortName, "Base")
        XCTAssertEqual(WhisperModelTier.base.modelSizeMB, 145)
        
        XCTAssertEqual(WhisperModelTier.small.shortName, "Small")
        XCTAssertEqual(WhisperModelTier.small.modelSizeMB, 460)
    }

    func testLanguageOptionCodes() {
        XCTAssertNil(WhisperLanguageOption.auto.codeHint)
        XCTAssertEqual(WhisperLanguageOption.english.codeHint, "en")
        XCTAssertEqual(WhisperLanguageOption.hindi.codeHint, "hi")
        XCTAssertEqual(WhisperLanguageOption.gujarati.codeHint, "gu")
    }

    // MARK: - CommandAudioAccumulator & Resampling Tests

    func testCommandAudioAccumulatorDownsamplingAndCapacity() {
        let accumulator = CommandAudioAccumulator(targetSampleRate: 16000.0, maxDurationSeconds: 1.0)
        XCTAssertEqual(accumulator.targetSampleRate, 16000.0)
        XCTAssertEqual(accumulator.maxSampleCapacity, 16000)
        
        // Generate 48,000 samples of synthetic audio at 48kHz (1.0 second of audio)
        let sampleCount48k = 48000
        var audio48k = [Float](repeating: 0.0, count: sampleCount48k)
        for i in 0..<sampleCount48k {
            audio48k[i] = sin(Float(i) * 0.05) * 0.5
        }
        
        // Append 48kHz audio into 16kHz accumulator
        accumulator.append(samples: audio48k, inputSampleRate: 48000.0)
        
        // After 3:1 decimation/resampling, sample count should be approximately 16,000
        let extracted = accumulator.extractAndReset()
        XCTAssertEqual(extracted.count, 16000, "Resampling from 48kHz to 16kHz should yield 16,000 samples for 1s.")
        XCTAssertEqual(accumulator.currentSampleCount, 0, "extractAndReset should empty the buffer.")
        XCTAssertEqual(accumulator.currentDuration, 0.0)
    }

    func testAccumulatorEnforcesCapacityCap() {
        let accumulator = CommandAudioAccumulator(targetSampleRate: 16000.0, maxDurationSeconds: 0.5)
        XCTAssertEqual(accumulator.maxSampleCapacity, 8000)
        
        // Try appending 20,000 samples at 16kHz
        let largeBatch = [Float](repeating: 0.1, count: 20000)
        accumulator.append(samples: largeBatch, inputSampleRate: 16000.0)
        
        // Should be capped at 8,000 samples
        XCTAssertEqual(accumulator.currentSampleCount, 8000)
        XCTAssertEqual(accumulator.currentDuration, 0.5)
    }

    // MARK: - WhisperKitEngine Inference Tests

    func testWhisperKitEnginePreparationAndAvailability() async throws {
        let engine = WhisperKitEngine.shared
        XCTAssertTrue(engine.isAvailable)
        XCTAssertEqual(engine.engineType, .whisperKit)
        
        try await engine.prepare()
        XCTAssertTrue(engine.isAvailable)
    }

    func testWhisperKitEngineRejectsShortOrSilentAudio() async throws {
        let engine = WhisperKitEngine.shared
        
        // 1. Shorter than 0.3s (e.g. 1000 samples at 16kHz = 0.0625s)
        let shortAudio = [Float](repeating: 0.5, count: 1000)
        let resultShort = try await engine.transcribe(audioSamples: shortAudio, sampleRate: 16000.0)
        XCTAssertEqual(resultShort, "", "Audio shorter than 0.3s should return an empty string.")
        
        // 2. Silent audio (> 0.3s but near-zero RMS < 0.005)
        let silentAudio = [Float](repeating: 0.0001, count: 8000)
        let resultSilent = try await engine.transcribe(audioSamples: silentAudio, sampleRate: 16000.0)
        XCTAssertEqual(resultSilent, "", "Pure silence audio should return an empty string.")
    }

    func testWhisperKitEngineMultilingualDecoding() async throws {
        let engine = WhisperKitEngine.shared
        
        // Valid synthetic audio buffer of 1.0s (16,000 samples with audible energy)
        var voiceAudio = [Float](repeating: 0.0, count: 16000)
        for i in 0..<16000 {
            voiceAudio[i] = sin(Float(i) * 0.1) * 0.25
        }
        
        // Test English Transcript
        MockWhisperTranscriptStore.shared.setMockTranscript("Create a new note about roadmap")
        let englishResult = try await engine.transcribe(audioSamples: voiceAudio, sampleRate: 16000.0, language: "en")
        XCTAssertEqual(englishResult, "Create a new note about roadmap")
        
        // Test Hindi Transcript
        MockWhisperTranscriptStore.shared.setMockTranscript("मेरा आज का कैलेंडर चेक करो")
        let hindiResult = try await engine.transcribe(audioSamples: voiceAudio, sampleRate: 16000.0, language: "hi")
        XCTAssertEqual(hindiResult, "मेरा आज का कैलेंडर चेक करो")
        
        // Test Gujarati Transcript
        MockWhisperTranscriptStore.shared.setMockTranscript("નવા ઇમેઇલ તપાસો")
        let gujaratiResult = try await engine.transcribe(audioSamples: voiceAudio, sampleRate: 16000.0, language: "gu")
        XCTAssertEqual(gujaratiResult, "નવા ઇમેઇલ તપાસો")
        
        // Test Hinglish Code-Switching
        MockWhisperTranscriptStore.shared.setMockTranscript("Nexus, mara unread emails check kar")
        let hinglishResult = try await engine.transcribe(audioSamples: voiceAudio, sampleRate: 16000.0, language: nil)
        XCTAssertEqual(hinglishResult, "Nexus, mara unread emails check kar")
    }

    // MARK: - VoiceActivationEngine STT Settings Integration

    @MainActor
    func testVoiceActivationEngineUpdatesSTTPreferences() {
        let engine = VoiceActivationEngine.shared
        
        engine.setSpeechEngineType(.whisperKit)
        engine.setWhisperModelTier(.small)
        engine.setWhisperLanguageOption(.gujarati)
        engine.setWhisperFallbackToSystem(false)
        
        let activeCfg = WhisperKitEngine.shared.currentConfig()
        XCTAssertEqual(activeCfg.selectedEngine, .whisperKit)
        XCTAssertEqual(activeCfg.modelTier, .small)
        XCTAssertEqual(activeCfg.languageOption, .gujarati)
        XCTAssertFalse(activeCfg.fallbackToSystemSpeech)
        
        // Reset to balanced defaults
        engine.setSpeechEngineType(.whisperKit)
        engine.setWhisperModelTier(.base)
        engine.setWhisperLanguageOption(.auto)
        engine.setWhisperFallbackToSystem(true)
    }
}
