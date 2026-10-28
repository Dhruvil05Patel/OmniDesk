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
    
    @State private var isHoveringMic: Bool = false
    
    var isRecording: Bool {
        voiceService.state == .recording
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Bar
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: isRecording ? Color.omniRed.opacity(0.6) : .clear, radius: 4)
                    
                    Text(statusText.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(statusTextColor)
                        .tracking(0.8)
                }
                
                Spacer()
                
                // Model Tag + Shortcut Badge
                HStack(spacing: 8) {
                    Text("qwen-3.8-27b")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    KeyboardShortcutBadge(shortcut: isRecording ? "ESC" : "SPACE")
                }
            }
            
            // Ultra-Slim 2px Minimalist Audio Waveform
            HStack(spacing: 4) {
                ForEach(0..<15) { index in
                    MinimalWaveformBar(
                        level: voiceService.audioLevel,
                        index: index,
                        isRecording: isRecording
                    )
                }
            }
            .frame(height: 32)
            .padding(.vertical, 2)
            
            // Live Transcription Surface
            VStack(alignment: .leading, spacing: 4) {
                if voiceService.recognizedText.isEmpty {
                    Text(isRecording ? "Listening to your voice..." : "Click microphone or press Space to capture voice command...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(voiceService.recognizedText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isRecording ? Color.omniAccent.opacity(0.3) : Color.omniBorder, lineWidth: 1)
            )
            
            // Primary Control Bar (Frosted Glass Button)
            Button(action: handleVoiceToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isRecording ? .white : .primary)
                    
                    Text(isRecording ? "Stop & Process" : "Start Speaking")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isRecording ? .white : .primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isRecording
                        ? AnyView(LinearGradient(colors: [Color.omniRed, Color.omniRed.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyView(Color.white.opacity(isHoveringMic ? 0.08 : 0.04))
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isRecording ? Color.omniRed.opacity(0.4) : Color.omniBorder, lineWidth: 1)
                )
                .shadow(color: isRecording ? Color.omniRed.opacity(0.3) : .clear, radius: 8, y: 3)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringMic = hovering
                }
            }
        }
        .minimalCard(padding: 18, cornerRadius: 14, isHovered: isRecording)
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
    
    private var statusDotColor: Color {
        switch voiceService.state {
        case .idle:
            return .secondary.opacity(0.6)
        case .recording:
            return .omniRed
        case .permissionDenied:
            return .omniAmber
        }
    }
    
    private var statusTextColor: Color {
        switch voiceService.state {
        case .idle:
            return .secondary
        case .recording:
            return .omniRed
        case .permissionDenied:
            return .omniAmber
        }
    }
    
    private var statusText: String {
        switch voiceService.state {
        case .idle:
            return "Ready"
        case .recording:
            return "Listening"
        case .permissionDenied(let msg):
            return msg
        }
    }
}

// MARK: - Ultra-Slim 2px Minimalist Audio Bar
private struct MinimalWaveformBar: View {
    let level: Float
    let index: Int
    let isRecording: Bool
    
    var computedHeight: CGFloat {
        if !isRecording { return 4 }
        let waveOffsets: [CGFloat] = [0.3, 0.6, 0.9, 1.2, 0.7, 1.4, 1.0, 0.8, 1.3, 0.9, 1.1, 0.6, 1.0, 0.5, 0.3]
        let offset = waveOffsets[index % waveOffsets.count]
        let baseHeight = CGFloat(level) * 32.0 * offset
        return max(4, min(32, baseHeight))
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(
                isRecording
                    ? Color.omniAccent.opacity(0.85)
                    : Color.white.opacity(0.12)
            )
            .frame(width: 2, height: computedHeight)
            .animation(.spring(response: 0.12, dampingFraction: 0.6), value: level)
    }
}
