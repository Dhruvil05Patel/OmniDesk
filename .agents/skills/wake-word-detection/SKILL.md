---
name: wake-word-detection
description: Guides low-power on-device keyword spotting (KWS), streaming Zipformer audio graphs, keywords.txt boosting configuration, and false-accept prevention for macOS desktop assistants. Use when building or debugging custom wake words (e.g., "Dhuli"), in-memory circular audio ring buffers, or background audio listening pipelines in Swift.
---

# Wake-Word Detection Skill

Provides authoritative guidelines, patterns, and Swift implementation rules for continuous, low-power on-device keyword spotting and wake-word detection in OmniDesk.

## 1. Core Principles & Privacy Guarantees
- **100% On-Device & Zero Cloud Audio**: Audio captured for keyword spotting must never leave device memory.
- **In-Memory Ring Buffer**: Streaming PCM audio samples are maintained in an ephemeral circular buffer in RAM (default: 3.0s FIFO). Zero disk persistence.
- **Low CPU Consumption**: Wake detection must consume < 1.5% CPU on Apple Silicon during ambient idle listening.

## 2. Audio Resampling & Buffer Management
macOS audio input hardware typically operates at 44.1 kHz, 48 kHz, or 96 kHz. Transducer and acoustic KWS models require 16,000 Hz, 1-channel (mono), 16-bit or Float32 PCM.

### Converting Audio Streams in Real Time:
```swift
let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
    throw AudioEngineError.converterInitializationFailed
}
```

### Circular Ring Buffer:
Maintain an array of `Float` samples with thread-safe pointer wrapping:
- Max capacity: `sampleRate * windowSeconds` (e.g. 16,000 * 3 = 48,000 floats).
- Never reallocate memory inside the real-time audio tap callback.

## 3. Dynamic Keyword Boosting (`keywords.txt`)
When using `sherpa-onnx` open-vocabulary keyword spotting:
- Keywords are declared in a plain text configuration file with boosting weights and thresholds:
  ```text
  # PHRASE :BOOST_WEIGHT #THRESHOLD
  DHULI :1.5 #0.35
  DHOOLI :1.4 #0.38
  HEY DHULI :1.8 #0.40
  ```
- **Boost weight (`:1.5`)**: Multiplies the lattice score for the target word.
- **Threshold (`#0.35`)**: The minimum posterior confidence required to fire the wake event. Lower values increase recall (fewer missed wakes) but increase false accepts; higher values decrease false accepts but may require louder or clearer pronunciation.

## 4. Acoustic Self-Trigger Prevention
When the assistant speaks ("Yes boss" or reading back task results):
1. **Software Mute**: Immediately halt pushing microphone frames to the KWS detector while audio output is active.
2. **Refractory Cooldown**: Enforce a mandatory 500ms cooldown timer post-playback before re-enabling wake word triggers.
3. **macOS Hardware AEC**: Set `inputNode.isVoiceProcessingEnabled = true` to engage system acoustic echo cancellation.
