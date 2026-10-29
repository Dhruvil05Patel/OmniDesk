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
                        .shadow(color: isRecording ? Color.omniRed.opacity(0.8) : Color.omniEmerald.opacity(0.4), radius: 4)
                    
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
                        .foregroundColor(Color.omniTextSecondary)
                    
                    KeyboardShortcutBadge(shortcut: isRecording ? "ESC" : "SPACE")
                }
            }
            
            // Ultra-Slim Minimalist Audio Waveform
            HStack(spacing: 5) {
                ForEach(0..<15) { index in
                    MinimalWaveformBar(
                        level: voiceService.audioLevel,
                        index: index,
                        isRecording: isRecording
                    )
                }
            }
            .frame(height: 28)
            .padding(.vertical, 2)
            
            // Live Transcription Surface
            VStack(alignment: .leading, spacing: 4) {
                if voiceService.recognizedText.isEmpty {
                    Text(isRecording ? "Listening to your voice..." : "Click microphone or press Space to capture voice command...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.omniTextMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(voiceService.recognizedText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.omniTextPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.omniInputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isRecording ? Color.omniAccent.opacity(0.4) : Color.omniBorder, lineWidth: 1)
            )
            
            // Primary Control Bar (Pill Button with No Focus Ring)
            Button(action: handleVoiceToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isRecording ? .white : Color.omniTextPrimary)
                    
                    Text(isRecording ? "Stop & Process" : "Start Speaking")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isRecording ? .white : Color.omniTextPrimary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    isRecording
                        ? Color.omniRed
                        : (isHoveringMic ? Color.omniBorderHover : Color.omniPillBackground)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isRecording
                                ? Color.omniRed.opacity(0.5)
                                : (isHoveringMic ? Color.omniBorderHover : Color.omniBorder),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isRecording ? Color.omniRed.opacity(0.4) : Color.black.opacity(0.12),
                    radius: 6,
                    y: 2
                )
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
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
            return Color.omniEmerald
        case .recording:
            return Color.omniRed
        case .permissionDenied:
            return Color.omniAmber
        }
    }
    
    private var statusTextColor: Color {
        switch voiceService.state {
        case .idle:
            return Color.omniTextSecondary
        case .recording:
            return Color.omniRed
        case .permissionDenied:
            return Color.omniAmber
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

// MARK: - Ultra-Slim Minimalist Audio Bar
private struct MinimalWaveformBar: View {
    let level: Float
    let index: Int
    let isRecording: Bool
    
    // Wave heights pattern for idle state
    private let idleHeights: [CGFloat] = [4, 6, 10, 14, 8, 16, 12, 18, 14, 10, 16, 8, 12, 6, 4]
    
    var computedHeight: CGFloat {
        if !isRecording {
            return idleHeights[index % idleHeights.count]
        }
        let waveOffsets: [CGFloat] = [0.4, 0.7, 1.0, 1.3, 0.8, 1.5, 1.1, 0.9, 1.4, 1.0, 1.2, 0.7, 1.1, 0.6, 0.4]
        let offset = waveOffsets[index % waveOffsets.count]
        let baseHeight = CGFloat(level) * 28.0 * offset
        return max(4, min(28, baseHeight))
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(
                isRecording
                    ? Color.omniAccent
                    : Color.omniTextMuted.opacity(0.35)
            )
            .frame(width: 2.5, height: computedHeight)
            .animation(.spring(response: 0.12, dampingFraction: 0.6), value: level)
    }
}
