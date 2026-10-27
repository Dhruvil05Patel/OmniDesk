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
        ScrollView {
            VStack(spacing: 24) {
                // Header Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "sparkles")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .bold))
                            }
                            
                            Text("OmniDesk")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                        }
                        
                        Text("Voice-First Personal Operating Layer")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Status Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 16/255, green: 185/255, blue: 129/255))
                            .frame(width: 8, height: 8)
                        Text("Groq Cloud Ready")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                }
                .padding(.top, 4)
                
                // Assistant Status Banner (Notifications / Alerts)
                if viewModel.status != .idle {
                    HStack(spacing: 10) {
                        statusIcon
                        
                        Text(statusMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(statusBackgroundColor)
                    .cornerRadius(10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Voice Dictation Component
                VoiceView(voiceService: voiceService) { transcript in
                    viewModel.processVoiceInput(transcript)
                }
                
                // Task List Component
                TaskListView(viewModel: viewModel)
            }
            .padding(28)
            .frame(minWidth: 520, maxWidth: 680)
        }
        .frame(minWidth: 560, minHeight: 640)
        .background(
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        case .actionSuccess:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }
    
    private var statusMessage: String {
        switch viewModel.status {
        case .idle:
            return ""
        case .listening:
            return "Listening to your voice..."
        case .processing:
            return "Analyzing intent with Groq AI..."
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
            return Color.red.opacity(0.1)
        case .processing:
            return Color.indigo.opacity(0.12)
        case .actionSuccess:
            return Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.12)
        case .error:
            return Color.orange.opacity(0.12)
        }
    }
}

#Preview {
    DashboardView()
}
