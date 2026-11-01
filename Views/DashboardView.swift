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
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var policyGate = SafetyPolicyGate.shared
    @State private var showSettingsSheet: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Minimalist Top Window Bar (Includes space for macOS traffic lights)
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.omniAccent)
                    
                    Text("OmniDesk")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Color.omniTextPrimary)
                        .tracking(0.3)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Status Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.omniEmerald)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.omniEmerald.opacity(0.5), radius: 3)
                        
                        Text("Groq Cloud Ready")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.omniTextSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.omniPillBackground)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.omniBorder, lineWidth: 1)
                    )
                    
                    // Settings Button
                    Button(action: { showSettingsSheet.toggle() }) {
                        Image(systemName: "gearshape")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.omniTextSecondary)
                            .padding(6)
                            .background(Color.omniPillBackground)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.omniBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                    .popover(isPresented: $showSettingsSheet, arrowEdge: .bottom) {
                        SettingsView()
                            .preferredColorScheme(themeManager.currentTheme.colorScheme)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
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
                                .foregroundColor(Color.omniTextPrimary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(statusBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.omniBorder, lineWidth: 1)
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
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    KeyboardShortcutBadge(shortcut: "SPACE")
                    Text("Record Voice")
                        .font(.system(size: 11))
                        .foregroundColor(Color.omniTextSecondary)
                }
                
                HStack(spacing: 6) {
                    KeyboardShortcutBadge(shortcut: "↵")
                    Text("Add Task")
                        .font(.system(size: 11))
                        .foregroundColor(Color.omniTextSecondary)
                }
                
                Spacer()
                
                Text("Personal AI OS • v1.0")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.omniTextMuted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.omniFooterBackground)
        }
        .frame(minWidth: 540, maxWidth: 660, minHeight: 620, maxHeight: 720)
        .background(Color.omniBackground.ignoresSafeArea())
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .overlay {
            if policyGate.activeRequest != nil {
                ActionConfirmationModalView(policyGate: policyGate)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        )
                    )
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: policyGate.activeRequest != nil)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.status {
        case .idle:
            EmptyView()
        case .listening:
            Image(systemName: "waveform")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color.omniRed)
                .font(.system(size: 12))
        case .processing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .actionSuccess:
            Image(systemName: "checkmark")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color.omniEmerald)
                .font(.system(size: 11, weight: .bold))
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(Color.omniAmber)
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
            return Color.omniRed.opacity(0.15)
        case .processing:
            return Color.omniAccent.opacity(0.15)
        case .actionSuccess:
            return Color.omniEmerald.opacity(0.15)
        case .error:
            return Color.omniAmber.opacity(0.15)
        }
    }
}

// MARK: - Dedicated Settings & Customization View
struct SettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var activationEngine = VoiceActivationEngine.shared
    @ObservedObject private var ackPlayer = WakeAcknowledgementPlayer.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.omniAccent)
                        
                        Text("Settings & Customization")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color.omniTextPrimary)
                    }
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color.omniTextMuted)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                }
                
                Divider()
                    .background(Color.omniBorder)
                
                // Voice Activation & Wake Word Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.omniAccent)
                        
                        Text("VOICE ACTIVATION & WAKE WORD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.omniTextSecondary)
                            .tracking(0.6)
                    }
                    
                    // Enable Wake Word Toggle
                    Toggle(isOn: $activationEngine.isWakeWordEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Always-On Wake Word (\"Dhuli\")")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.omniTextPrimary)
                            Text("Hands-free voice trigger alongside ⌘⌥O hotkey")
                                .font(.system(size: 10))
                                .foregroundColor(Color.omniTextMuted)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.omniAccent))
                    
                    if activationEngine.isWakeWordEnabled {
                        Divider()
                            .background(Color.omniBorder)
                        
                        // Active Keyword Selection
                        HStack {
                            Text("Wake Phrase")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.omniTextSecondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { activationEngine.wakeDetector.config.activeKeyword },
                                set: { activationEngine.setActiveKeywordPhrase($0) }
                            )) {
                                Text("Dhuli").tag("DHULI")
                                Text("Hey Dhuli").tag("HEY DHULI")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 160)
                        }
                        
                        // Sensitivity Selection
                        HStack {
                            Text("Sensitivity")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.omniTextSecondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { activationEngine.wakeDetector.config.sensitivity },
                                set: { activationEngine.setWakeWordSensitivity($0) }
                            )) {
                                ForEach(WakeWordSensitivity.allCases, id: \.self) { sens in
                                    Text(sens.rawValue).tag(sens)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 180)
                        }
                        
                        // Acknowledgment Sound Selection
                        HStack {
                            Text("Spoken Reply")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.omniTextSecondary)
                            Spacer()
                            Picker("", selection: $ackPlayer.selectedPhrase) {
                                ForEach(WakeAcknowledgementPlayer.AckPhrase.allCases, id: \.self) { phrase in
                                    Text(phrase.rawValue).tag(phrase)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 120)
                        }
                        
                        // Randomize toggle
                        Toggle(isOn: $ackPlayer.randomizePhrase) {
                            Text("Randomize Acknowledgement")
                                .font(.system(size: 11))
                                .foregroundColor(Color.omniTextSecondary)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.omniAccent))
                    }
                    
                    // Privacy disclosure note
                    Text("OmniDesk processes audio 100% locally in-memory for wake detection. Audio is never recorded to disk or sent to the cloud. macOS displays an orange dot in the menu bar when active.")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.omniTextMuted)
                        .lineSpacing(2)
                        .padding(.top, 2)
                }
                .minimalCard(padding: 14, cornerRadius: 10)
                
                // Appearance Section
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.righthalf.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.omniAccent)
                    
                    Text("COLOR SCHEME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.omniTextSecondary)
                        .tracking(0.6)
                }
                
                // Theme Selector Cards (System / Dark / Light)
                HStack(spacing: 8) {
                    ForEach(AppTheme.allCases) { theme in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                themeManager.setTheme(theme)
                            }
                        }) {
                            VStack(spacing: 7) {
                                Image(systemName: theme.iconName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(themeManager.currentTheme == theme ? Color.omniAccent : Color.omniTextSecondary)
                                
                                Text(theme.displayName)
                                    .font(.system(size: 11, weight: themeManager.currentTheme == theme ? .semibold : .medium))
                                    .foregroundColor(themeManager.currentTheme == theme ? Color.omniTextPrimary : Color.omniTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                themeManager.currentTheme == theme
                                    ? Color.omniAccent.opacity(0.12)
                                    : Color.omniInputSurface
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        themeManager.currentTheme == theme
                                            ? Color.omniAccent.opacity(0.6)
                                            : Color.omniBorder,
                                        lineWidth: themeManager.currentTheme == theme ? 1.5 : 1
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                    }
                }
                
                Text(themeManager.currentTheme.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color.omniTextMuted)
                    .padding(.top, 2)
            }
            .minimalCard(padding: 14, cornerRadius: 10)
            
            // Intelligence Engine Info
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.omniAccent)
                    
                    Text("INTELLIGENCE ENGINE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.omniTextSecondary)
                        .tracking(0.6)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active LLM")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.omniTextPrimary)
                        Text("Groq Cloud Ultra-Low Latency Inference")
                            .font(.system(size: 10))
                            .foregroundColor(Color.omniTextMuted)
                    }
                    
                    Spacer()
                    
                    Text("qwen-3.8-27b")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.omniEmerald)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.omniEmerald.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .minimalCard(padding: 14, cornerRadius: 10)
            
            // Safety & Live Connectors Testing Section
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.omniAmber)
                    
                    Text("SAFETY & ACTION GATEWAY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.omniTextSecondary)
                        .tracking(0.6)
                }
                
                Text("Test the Zero-Trust confirmation modal for high-risk outbound actions.")
                    .font(.system(size: 10))
                    .foregroundColor(Color.omniTextMuted)
                
                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        Task {
                            _ = try? await ActionHandler.shared.dispatchTool(
                                named: "mail_send_message",
                                arguments: [
                                    "recipient": "recruiter@apple.com",
                                    "subject": "Senior macOS Systems Architect Proposal",
                                    "body": "Please review the attached privacy-preserving assistant architecture."
                                ]
                            )
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.omniRed)
                        Text("Trigger Test Confirmation Modal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.omniTextPrimary)
                        Spacer()
                        KeyboardShortcutBadge(shortcut: "TEST")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.omniInputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.omniBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .minimalCard(padding: 14, cornerRadius: 10)
        }
        .padding(18)
        .frame(width: 380)
        }
        .frame(maxHeight: 520)
        .background(Color.omniBackground.ignoresSafeArea())
    }
}

#Preview {
    DashboardView()
}
