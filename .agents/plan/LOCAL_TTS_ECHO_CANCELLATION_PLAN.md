# Phase 4: Local TTS Engine & Acoustic Echo Cancellation (AEC) — Architectural Plan
**Document Location:** `.agents/plan/LOCAL_TTS_ECHO_CANCELLATION_PLAN.md`  
**Current Branch:** `feature/local-tts-echo-cancellation`  
**Task ID:** `OD-20261104-TTS-AEC`  
**Target Assistant:** OmniDesk (Native macOS Operating Layer)  
**Status:** `PLANNED`  

---

## 1. Executive Summary & Objective

In ambient, voice-driven operating layers, audio output (acknowledgements, status responses, and task completions) shares the physical acoustic space with the input microphone. Without aggressive echo suppression and acoustic session isolation:
1. **Acoustic Feedback Loops**: The assistant's own spoken output (e.g. *"Added task: check emails"*) is captured by the microphone tap and re-evaluated by the wake-word detector or STT engine.
2. **False Wake Triggers**: Spoken sentences containing phonetically adjacent syllables can false-trigger the wake-word detector.
3. **Rigid Vocal Delivery**: Fixed speech rates, unnatural pitches, or missing regional voices limit user personalization and conversational comfort.

### Objective
Implement **Phase 4 of the Voice Pipeline Roadmap**:
- **Hardware DSP Acoustic Echo Cancellation (AEC)**: Enable macOS `VoiceProcessingIO` on `AVAudioEngine.inputNode` to instruct CoreAudio to actively subtract speaker output from the microphone stream.
- **Dynamic TTS Personalization**: Provide speech rate (0.35–0.60), pitch multiplier (0.75–1.25), and system voice selection (Siri, Samantha, Alex, regional Indic voices `en-IN`, `hi-IN`).
- **Echo-Lock & Audio Session Drain Barrier**: Solidify continuation-based audio output locking, ensuring wake-word detection and dictation strictly suspend during playback and for 500ms post-synthesis.
- **Settings UI**: Add a dedicated `AUDIO & VOICE OUTPUT (TTS)` card in `SettingsView`.

---

## 2. Audio Pipeline & Echo Cancellation Topology

```mermaid
flowchart TD
    subgraph CoreAudioLayer ["macOS CoreAudio Hardware & DSP"]
        MicHardware["Microphone In"] --> AECDSP["CoreAudio VoiceProcessingIO (Hardware DSP AEC)"]
        SpeakerHardware["Speaker Out"] -.->|Acoustic Bleedback| MicHardware
        SpeakerHardware -.->|Reference Signal| AECDSP
        AECDSP --> CleanPCM["Echo-Suppressed 16kHz PCM Buffer"]
    end

    subgraph AudioEngineOwner ["Single Audio Owner (VoiceService)"]
        CleanPCM --> InputTap["Bus 0 Tap (Real-Time Audio Stream)"]
        InputTap --> EchoLockGate{"Is Audio Output Playing / Cooldown?"}
        EchoLockGate -->|Yes (Echo Locked)| DropStream["Drop Wake Word Evaluation"]
        EchoLockGate -->|No (Clear)| WakeDetector["VoiceActivationEngine (Nexus Spotting)"]
        EchoLockGate -->|Active Recording| Accumulator["CommandAudioAccumulator (STT)"]
    end

    subgraph TTSOutputEngine ["TTS Engine (WakeAcknowledgementPlayer)"]
        ActionFeedback["Task / Action Handler Spoken Output"] --> TTSConfigCheck{"Voice Feedback Enabled?"}
        TTSConfigCheck -->|Yes| SetEchoLock["Set isAudioOutputPlaying = true"]
        SetEchoLock --> Synth["AVSpeechSynthesizer / AVAudioPlayer Playback"]
        Synth --> SpeakerHardware
        Synth --> PlaybackComplete["didFinishUtterance Event"]
        PlaybackComplete --> DrainBarrier["500ms Hardware DAC Drain Barrier"]
        DrainBarrier --> ClearEchoLock["Set isAudioOutputPlaying = false"]
    end
```

---

## 3. Detailed Component Architecture

### 3.1 Hardware DSP Acoustic Echo Cancellation (`VoiceProcessingIO`)
In `Services/VoiceService.swift`:
```swift
if #available(macOS 10.15, *) {
    do {
        try inputNode.setVoiceProcessingEnabled(isEchoCancellationEnabled)
    } catch {
        print("⚠️ VoiceProcessingIO not supported on current audio device: \(error)")
    }
}
```
Enabling `VoiceProcessingIO` on the input unit engages macOS system-level digital signal processing, dynamically modeling speaker output transfer functions and subtracting speaker bleed from the microphone tap.

### 3.2 TTS Configuration Model (`TTSVoiceConfig.swift`)
Stores user preferences for vocal feedback:
- `isVoiceFeedbackEnabled: Bool` (default: `true` — speaks task completions like *"Added task: ..."* or *"Action completed"*).
- `speechRate: Float` (clamped between 0.35 and 0.60; default: 0.46 for calm conversational cadence).
- `pitchMultiplier: Float` (clamped between 0.75 and 1.25; default: 1.0).
- `voiceIdentifier: String?` (allows selection among installed system voices).
- `isEchoCancellationEnabled: Bool` (default: `true`).
- `UserDefaults` persistence keys and restoration.

### 3.3 Enhanced `WakeAcknowledgementPlayer.swift`
- Manages `TTSVoiceConfig` and dispatches spoken feedback accordingly.
- Caches selected `AVSpeechSynthesisVoice` to eliminate repeated IPC overhead to `speechsynthesisd`.
- Implements `stopAllPlayback()` to immediately silence audio when hotkey `⌥⇧M` (Mute) is pressed.
- Refractory cooldown of 500ms following `didFinishUtterance` to drain DAC and audio queue buffers.

### 3.4 Settings UI (`Views/DashboardView.swift`)
Adds `AUDIO & VOICE OUTPUT (TTS)` section:
- Spoken Voice Feedback toggle.
- Voice Selector menu (listing available English / regional voices).
- Speech Rate slider (Slow $\leftrightarrow$ Fast).
- Hardware Echo Cancellation (AEC) toggle with system information note.

---

## 4. Skills Required

| Agent | Skill Name | Location / Status | Description |
| :--- | :--- | :--- | :--- |
| **Logic & Backend** | `local-tts-engine` | `.agents/skills/local-tts-engine/SKILL.md` | Dual-tier hybrid TTS, acoustic echo suppression, and `AVSpeechSynthesizer` voice caching. |
| **Logic & Backend** | `voice-task-pipeline` | `.agents/skills/voice-task-pipeline/SKILL.md` | `VoiceProcessingIO` configuration on `AVAudioEngine.inputNode`. |
| **UI/UX** | Apple HIG Design Tokens | `Utilities/DesignTokens.swift` | Glassmorphic cards, sliders, and controls. |
| **Testing** | `swift-test` | Built-in | Unit testing AEC toggle, voice config persistence, rate clamping, and echo lockout. |

---

## 5. File Inventory & Modifications

### New Files to Create:
1. `OmniDesk/VoiceActivation/TTSVoiceConfig.swift` — Model and settings for voice synthesis and echo cancellation.
2. `OmniDeskTests/LocalTTSEchoCancellationTests.swift` — Unit tests for TTS configuration, voice selection, echo locking, and AEC.

### Existing Files to Update:
1. `OmniDesk/VoiceActivation/WakeAcknowledgementPlayer.swift` — Integrate `TTSVoiceConfig`, voice selection, pitch/rate controls.
2. `Services/VoiceService.swift` — Configure `isVoiceProcessingEnabled` on `audioEngine.inputNode`.
3. `Views/DashboardView.swift` — Add `AUDIO & VOICE OUTPUT (TTS)` controls in `SettingsView`.
4. `.agents/summary.md` — Update roadmap milestones and test status.

---

## 6. Phased Implementation Roadmap

1. **Step 1: Models & Configuration (Logic & Backend)**
   - Create `TTSVoiceConfig.swift` with UserDefaults persistence.
2. **Step 2: VoiceProcessingIO & Audio Engine (Logic & Backend)**
   - Update `VoiceService.swift` to apply `setVoiceProcessingEnabled(true)`.
3. **Step 3: TTS Player Personalization & Refractory Barrier (Logic & Backend)**
   - Enhance `WakeAcknowledgementPlayer.swift` with voice selection, rate/pitch application, and echo lockouts.
4. **Step 4: Settings UI (UI/UX)**
   - Add `AUDIO & VOICE OUTPUT (TTS)` section in `SettingsView`.
5. **Step 5: Testing & Hardening (Testing)**
   - Create and execute `LocalTTSEchoCancellationTests.swift`.
   - Validate 0 regressions across all unit tests.

---

## 7. Acceptance Criteria

- [ ] Current branch verified as `feature/local-tts-echo-cancellation`.
- [ ] `TTSVoiceConfig` persists voice feedback toggle, speech rate, pitch multiplier, voice identifier, and AEC toggle.
- [ ] `VoiceService` cleanly sets `setVoiceProcessingEnabled` without CoreAudio crashes.
- [ ] `WakeAcknowledgementPlayer` respects voice feedback toggle and applies custom rate/pitch/voice.
- [ ] `isAudioOutputPlaying` locks out wake word during playback and 500ms cooldown.
- [ ] `SettingsView` displays glassmorphic voice and echo cancellation controls.
- [ ] 100% of unit tests pass with `xcodebuild test`.
- [ ] Clean atomic commits and conflict-free verification before push and PR.
