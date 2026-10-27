---
name: voice-task-pipeline
description: Handles macOS AVAudioEngine real-time audio power metering, SFSpeechRecognizer speech-to-text, low-latency Groq AI intent parsing, and high-performance SwiftUI audio visualizers. Use when working on voice assistant features, audio capture, speech recognition, or low-latency LLM intent classification in Swift.
---

# Voice Task Pipeline Skill

Provides established patterns and implementation rules for building and optimizing the voice-driven task automation engine in OmniDesk.

## 1. Audio Capture & Real-Time Power Metering (`AVAudioEngine`)

When capturing microphone audio on macOS and calculating live volume for audio visualizers:

- **Audio Buffer Power (RMS)**: Compute Root Mean Square (RMS) from the float audio buffer channel data inside `inputNode.installTap`:
  ```swift
  let channelData = buffer.floatChannelData?[0]
  let frameLength = UInt(buffer.frameLength)
  var sum: Float = 0.0
  if let channelData = channelData, frameLength > 0 {
      for i in 0..<Int(frameLength) {
          sum += channelData[i] * channelData[i]
      }
      let rms = sqrt(sum / Float(frameLength))
      // Normalize to 0.0 ... 1.0 range
      let normalized = min(max(rms * 5.0, 0.0), 1.0)
      DispatchQueue.main.async {
          self.audioLevel = normalized
      }
  }
  ```
- **Lifecycle Safety**:
  - Always call `inputNode.removeTap(onBus: 0)` *before* installing a new tap or stopping the audio engine.
  - Cancel any in-flight `recognitionTask` and reset requests before starting a new recording session.
  - Guard against `audioEngine.isRunning` states.

## 2. Low-Latency, Cost-Effective Cloud LLM Intent Parsing

To minimize cloud API cost and achieve sub-350ms response times:

- **Pre-flight Input Guard**:
  ```swift
  let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard cleaned.count >= 3 else {
      return nil // Zero cost: do not fire network request
  }
  ```
- **Local Fast-Path**:
  Match explicit local commands before calling the network:
  - If text matches `"clear all tasks"` or `"delete all"`, execute directly via `MainViewModel` with 0 network latency.
- **Optimized Prompt Structure**:
  - Place instructions and JSON schema inside the `system` message.
  - Send only the raw transcribed string in the `user` message.
  - Enforce `response_format: {"type": "json_object"}`.
  - Limit `max_tokens: 150` and `temperature: 0.1` for maximum inference speed and determinism.
- **Swift Modern Concurrency**:
  - Use `async throws -> AIResponse?` over completion handlers.
  - Use `URLSession.shared.data(for: request)`.

## 3. High-Performance SwiftUI Audio Visualizers

- **Separation of Concerns**: Keep audio visualizer rendering in `VoiceView.swift` decoupled from business logic in `DashboardView.swift`.
- **Canvas / Geometry / Bar Visualizer**:
  Use normalized `audioLevel` (0.0 to 1.0) to dynamically scale bars with smooth spring animations:
  ```swift
  RoundedRectangle(cornerRadius: 3)
      .fill(isRecording ? Color.indigo : Color.gray.opacity(0.3))
      .frame(width: 4, height: max(6, barHeight * CGFloat(audioLevel)))
      .animation(.spring(response: 0.15, dampingFraction: 0.5), value: audioLevel)
  ```

## 4. Test Verification Pattern

- Mock inputs:
  - Empty text $\rightarrow$ verified to return `nil` without firing network tasks.
  - Valid task string $\rightarrow$ parses JSON into `AIResponse` model.
  - Event with dates $\rightarrow$ verifies `create_calendar_event` intent.
- Model state transitions:
  - `state` progresses from `.idle` $\rightarrow$ `.recording` $\rightarrow$ `.processing` $\rightarrow$ `.idle`.
