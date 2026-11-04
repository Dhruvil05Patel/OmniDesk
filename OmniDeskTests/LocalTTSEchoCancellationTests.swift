//
//  LocalTTSEchoCancellationTests.swift
//  OmniDeskTests
//
//  Created by Dhruvil Patel on 04/11/26.
//

import AVFoundation
import XCTest
@testable import OmniDesk

final class LocalTTSEchoCancellationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset to default config before each test
        let defaultConfig = TTSVoiceConfig.default
        defaultConfig.persist()
    }

    override func tearDown() {
        let defaultConfig = TTSVoiceConfig.default
        defaultConfig.persist()
        super.tearDown()
    }

    // MARK: - Configuration & Clamping Tests

    func testTTSVoiceConfigDefaultsAndClamping() {
        let normalConfig = TTSVoiceConfig(
            isVoiceFeedbackEnabled: true,
            speechRate: 0.46,
            pitchMultiplier: 1.0,
            selectedVoiceIdentifier: "com.apple.speech.synthesis.voice.siri",
            isEchoCancellationEnabled: true
        )
        
        XCTAssertTrue(normalConfig.isVoiceFeedbackEnabled)
        XCTAssertEqual(normalConfig.speechRate, 0.46)
        XCTAssertEqual(normalConfig.pitchMultiplier, 1.0)
        XCTAssertEqual(normalConfig.selectedVoiceIdentifier, "com.apple.speech.synthesis.voice.siri")
        XCTAssertTrue(normalConfig.isEchoCancellationEnabled)
        
        // Test lower and upper bounds clamping
        let clampedLow = TTSVoiceConfig(speechRate: 0.10, pitchMultiplier: 0.20)
        XCTAssertEqual(clampedLow.speechRate, 0.30, "Speech rate should be clamped to minimum 0.30.")
        XCTAssertEqual(clampedLow.pitchMultiplier, 0.70, "Pitch multiplier should be clamped to minimum 0.70.")
        
        let clampedHigh = TTSVoiceConfig(speechRate: 0.95, pitchMultiplier: 2.0)
        XCTAssertEqual(clampedHigh.speechRate, 0.65, "Speech rate should be clamped to maximum 0.65.")
        XCTAssertEqual(clampedHigh.pitchMultiplier, 1.30, "Pitch multiplier should be clamped to maximum 1.30.")
    }

    func testTTSVoiceConfigPersistence() {
        var config = TTSVoiceConfig(
            isVoiceFeedbackEnabled: false,
            speechRate: 0.52,
            pitchMultiplier: 1.15,
            selectedVoiceIdentifier: "test.voice.identifier",
            isEchoCancellationEnabled: false
        )
        config.persist()
        
        let loaded = TTSVoiceConfig.loadPersisted()
        XCTAssertFalse(loaded.isVoiceFeedbackEnabled)
        XCTAssertEqual(loaded.speechRate, 0.52, accuracy: 0.001)
        XCTAssertEqual(loaded.pitchMultiplier, 1.15, accuracy: 0.001)
        XCTAssertEqual(loaded.selectedVoiceIdentifier, "test.voice.identifier")
        XCTAssertFalse(loaded.isEchoCancellationEnabled)
    }

    // MARK: - WakeAcknowledgementPlayer Tests

    @MainActor
    func testFetchAvailableVoicesReturnsNonEmptyList() {
        let player = WakeAcknowledgementPlayer.shared
        let voices = player.fetchAvailableVoices()
        
        // Every macOS installation contains at least default English voices
        XCTAssertFalse(voices.isEmpty, "macOS system should have installed speech voices.")
        for voice in voices {
            XCTAssertFalse(voice.id.isEmpty)
            XCTAssertFalse(voice.name.isEmpty)
            XCTAssertFalse(voice.language.isEmpty)
        }
    }

    @MainActor
    func testUpdateTTSConfigAppliesAndPersists() {
        let player = WakeAcknowledgementPlayer.shared
        let customConfig = TTSVoiceConfig(
            isVoiceFeedbackEnabled: true,
            speechRate: 0.50,
            pitchMultiplier: 1.10,
            selectedVoiceIdentifier: nil,
            isEchoCancellationEnabled: true
        )
        
        player.updateTTSConfig(customConfig)
        XCTAssertEqual(player.ttsConfig.speechRate, 0.50)
        XCTAssertEqual(player.ttsConfig.pitchMultiplier, 1.10)
        
        let loaded = TTSVoiceConfig.loadPersisted()
        XCTAssertEqual(loaded.speechRate, 0.50, accuracy: 0.001)
        XCTAssertEqual(loaded.pitchMultiplier, 1.10, accuracy: 0.001)
    }

    @MainActor
    func testSpokenFeedbackDisabledBypassesAudioOutput() {
        let player = WakeAcknowledgementPlayer.shared
        var disabledConfig = player.ttsConfig
        disabledConfig.isVoiceFeedbackEnabled = false
        player.updateTTSConfig(disabledConfig)
        
        let expectation = expectation(description: "Completion called immediately when voice feedback is disabled")
        player.speakText("This should not generate audio") {
            expectation.fulfill()
        }
        
        // Should not engage audio playback lock
        XCTAssertFalse(player.isAudioOutputPlaying)
        waitForExpectations(timeout: 0.5)
    }

    @MainActor
    func testStopAllPlaybackClearsAudioLock() {
        let player = WakeAcknowledgementPlayer.shared
        player.stopAllPlayback()
        XCTAssertFalse(player.isAudioOutputPlaying)
    }

    // MARK: - VoiceService Acoustic Echo Cancellation (AEC)

    @MainActor
    func testVoiceServiceEchoCancellationToggle() {
        let voiceService = VoiceService.shared
        // Calling setEchoCancellationEnabled should execute without throwing
        voiceService.setEchoCancellationEnabled(true)
        voiceService.setEchoCancellationEnabled(false)
    }
}
