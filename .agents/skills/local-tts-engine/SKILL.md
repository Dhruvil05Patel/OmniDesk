---
name: local-tts-engine
description: Guides instant-latency audio acknowledgement playback via AVAudioPlayer and on-device natural text-to-speech synthesis using Apple AVSpeechSynthesizer and local neural models with acoustic echo-cancellation locks.
---

# Local TTS Engine Skill

Provides architectural patterns and Swift implementations for instant voice feedback and dynamic spoken responses in OmniDesk.

## 1. Dual-Tier Hybrid Architecture
To achieve instantaneous response times without synthesis delay:

1. **Tier 1 (Instant Wake Acknowledgement)**:
   - Use pre-rendered, lossless 16-bit 48kHz audio clips (WAV/CAF) bundled in the app bundle.
   - Phrases: *"Yes boss"*, *"Listening"*, *"Right here"*, *"On it"*.
   - Playback via `AVAudioPlayer` or `AVAudioPlayerNode`:
     - Latency: < 10ms.
     - 0% CPU synthesis overhead.
     - 100% natural, human studio fidelity.
2. **Tier 2 (Dynamic Spoken Responses)**:
   - For arbitrary dynamic text (e.g. reading calendar events or email summaries), use Apple's native `AVSpeechSynthesizer`:
     - Enhanced Siri voices or Personal Voice (macOS 14+).
     - Native Swift, zero external dependencies, 100% offline.

## 2. Echo Cancellation & Audio Session Locking
To prevent the assistant's own voice from re-triggering the microphone tap or wake word detector:

```swift
// Lock wake-word detection during playback
WakeWordDetector.shared.isAudioOutputPlaying = true
audioPlayer.play()

// In AVAudioPlayerDelegate / completion:
func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    // Enforce 500ms refractory cooldown before re-enabling microphone listening
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        WakeWordDetector.shared.isAudioOutputPlaying = false
    }
}
```

## 3. macOS VoiceProcessingIO Integration
Always set:
```swift
audioEngine.inputNode.isVoiceProcessingEnabled = true
```
This instructs macOS CoreAudio to engage hardware DSP acoustic echo cancellation (AEC), subtracting speaker output from the microphone stream.
