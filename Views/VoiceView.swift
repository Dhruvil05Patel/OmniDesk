//
//  VoiceView.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import SwiftUI

struct VoiceView: View {
    @ObservedObject var voiceService: VoiceService
    let onCommitTranscript: (String) -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    
    var isRecording: Bool {
        voiceService.state == .recording
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Top Status Bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .scaleEffect(isRecording ? pulseScale : 1.0)
                    
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
                
                Spacer()
                
                Text("Groq Qwen-3.8")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // Audio Visualizer Waveform Bars
            HStack(spacing: 5) {
                ForEach(0..<9) { index in
                    WaveformBar(
                        level: voiceService.audioLevel,
                        index: index,
                        isRecording: isRecording
                    )
                }
            }
            .frame(height: 48)
            .padding(.vertical, 4)
            
            // Live Transcription Box
            VStack(alignment: .leading, spacing: 6) {
                Text(voiceService.recognizedText.isEmpty ? (isRecording ? "Listening to your voice..." : "Press the microphone and say something like \"Remind me to finish portfolio tomorrow at 5pm\"") : voiceService.recognizedText)
                    .font(.system(size: 15, weight: voiceService.recognizedText.isEmpty ? .regular : .medium))
                    .foregroundColor(voiceService.recognizedText.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isRecording ? Color.indigo.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 1)
                    )
            }
            
            // Primary Control Button (Microphone Action)
            Button(action: handleVoiceToggle) {
                ZStack {
                    if isRecording {
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .frame(width: 84, height: 84)
                            .scaleEffect(pulseScale)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseScale)
                    }
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isRecording ? [Color.red, Color.orange] : [Color.indigo, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: isRecording ? Color.red.opacity(0.4) : Color.indigo.opacity(0.35), radius: 10, x: 0, y: 5)
                    
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Quick Tip
            Text(isRecording ? "Tap button to stop and process action" : "Tap to speak • Speaks intent into task or calendar")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.75))
                .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: voiceService.state) { newState in
            if newState == .recording {
                pulseScale = 1.2
            } else {
                pulseScale = 1.0
            }
        }
    }
    
    private func handleVoiceToggle() {
        if voiceService.state == .recording {
            let capturedText = voiceService.recognizedText
            voiceService.stopRecording()
            onCommitTranscript(capturedText)
        } else {
            voiceService.startRecording()
        }
    }
    
    private var statusColor: Color {
        switch voiceService.state {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .permissionDenied:
            return .orange
        }
    }
    
    private var statusText: String {
        switch voiceService.state {
        case .idle:
            return "Ready"
        case .recording:
            return "Listening..."
        case .permissionDenied(let msg):
            return msg
        }
    }
}

// Interactive Audio Bar
private struct WaveformBar: View {
    let level: Float
    let index: Int
    let isRecording: Bool
    
    // Stagger height calculation
    var computedHeight: CGFloat {
        if !isRecording { return 6 }
        let waveOffsets: [CGFloat] = [0.4, 0.7, 1.0, 0.8, 1.2, 0.9, 1.1, 0.6, 0.4]
        let offset = waveOffsets[index % waveOffsets.count]
        let baseHeight = CGFloat(level) * 44.0 * offset
        return max(6, min(44, baseHeight))
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: isRecording ? [Color.indigo, Color.cyan] : [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 4, height: computedHeight)
            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: level)
    }
}
