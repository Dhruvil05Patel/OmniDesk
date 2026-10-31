---
name: local-stt-whisperkit
description: Guides on-device Speech-to-Text transcription with WhisperKit on Apple Silicon, Core ML / Apple Neural Engine (ANE) zero-copy buffer dispatch, multilingual decoding (English, Hindi, Gujarati, Hinglish), and Voice Activity Detection (VAD) streaming in Swift.
---

# Local STT with WhisperKit Skill

Provides patterns and implementation guidelines for on-device, zero-cost, privacy-preserving speech transcription on macOS using Argmax `WhisperKit`.

## 1. Core Principles
- **100% On-Device**: Audio buffers remain strictly in local memory.
- **Apple Neural Engine (ANE) Optimization**: WhisperKit compiles Whisper models (`tiny`, `base`, `small`) directly into Core ML models targeted for the ANE and GPU.
- **Multilingual Support**: OpenAI Whisper weights natively support 99+ languages. In OmniDesk, multilingual tokenization covers:
  - English (`en`)
  - Hindi (`hi`)
  - Gujarati (`gu`)
  - Hinglish code-switching (transcription preserving romanized or Devanagari/Gujarati script depending on decode options).

## 2. Model Selection & Sizing
- `openai/whisper-tiny` (~75 MB): Ultra-fast (<80ms), suitable for short English commands.
- `openai/whisper-base` (~145 MB): Balanced accuracy (<180ms on ANE), robust on basic Hindi/Gujarati phrases. Recommended default.
- `openai/whisper-small` (~460 MB): High accuracy on regional dialects and complex Hinglish syntax (~300ms on ANE).

## 3. Audio Buffer Conversion & Transcription Pipeline
Audio captured from `AVAudioEngine` must be converted to 16,000 Hz, 1-channel, Float32 PCM:
```swift
// Feed Float32 array directly into WhisperKit without saving to WAV/disk
let audioSamples: [Float] = commandRingBuffer.readSamples()
let transcriptionResults = try await whisperKit.transcribe(audioArray: audioSamples)
let text = transcriptionResults.first?.text ?? ""
```

## 4. Voice Activity Detection (VAD) & End-of-Speech
- Monitor RMS energy and speech probability in continuous 100ms frames.
- Detect end-of-speech when speech energy drops below threshold for > 1.2 consecutive seconds.
- Enforce hard cutoff timeout at 10.0 seconds to prevent hanging buffers.
