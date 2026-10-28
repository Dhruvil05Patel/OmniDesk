//
//  DashboardView.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import SwiftUI

struct DashboardView: View {
    
    @StateObject private var voiceService = VoiceService()
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimalist Top Window Bar
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.omniAccent)
                    
                    Text("OmniDesk")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(0.3)
                }
                
                Spacer()
                
                // Status Pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.omniEmerald)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.omniEmerald.opacity(0.4), radius: 3)
                    
                    Text("Groq Cloud Ready")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.omniBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)
            
            Divider()
                .background(Color.omniBorder)
            
            // Main Content Area
            ScrollView {
                VStack(spacing: 16) {
                    // Status Alert Banner (Linear style subtle bar)
                    if viewModel.status != .idle {
                        HStack(spacing: 8) {
                            statusIcon
                            
                            Text(statusMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(statusBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Voice Capture Section
                    VoiceView(voiceService: voiceService) { transcript in
                        viewModel.processVoiceInput(transcript)
                    }
                    
                    // Task Management Section
                    TaskListView(viewModel: viewModel)
                }
                .padding(22)
            }
            
            Divider()
                .background(Color.omniBorder)
            
            // Footer Navigation Legend (Raycast style)
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    KeyboardShortcutBadge(shortcut: "SPACE")
                    Text("Record Voice")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                HStack(spacing: 5) {
                    KeyboardShortcutBadge(shortcut: "↵")
                    Text("Add Task")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                Text("Personal AI OS • v1.0")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.2))
        }
        .frame(minWidth: 540, maxWidth: 660, minHeight: 620, maxHeight: 720)
        .background(
            Color.omniBackground
                .ignoresSafeArea()
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .listening:
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.omniRed)
                .font(.system(size: 12))
        case .processing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .actionSuccess:
            Image(systemName: "checkmark")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.omniEmerald)
                .font(.system(size: 11, weight: .bold))
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.omniAmber)
                .font(.system(size: 12))
        }
    }
    
    private var statusMessage: String {
        switch viewModel.status {
        case .idle:
            return ""
        case .listening:
            return "Listening..."
        case .processing:
            return "Synthesizing with Groq AI..."
        case .actionSuccess(let msg):
            return msg
        case .error(let err):
            return err
        }
    }
    
    private var statusBackgroundColor: Color {
        switch viewModel.status {
        case .idle:
            return .clear
        case .listening:
            return Color.omniRed.opacity(0.12)
        case .processing:
            return Color.omniAccent.opacity(0.12)
        case .actionSuccess:
            return Color.omniEmerald.opacity(0.12)
        case .error:
            return Color.omniAmber.opacity(0.12)
        }
    }
}

#Preview {
    DashboardView()
}
