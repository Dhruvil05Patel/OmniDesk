//
//  DynamicIslandContainerView.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/10/26.
//

import SwiftUI
import Combine

/// Primary resident SwiftUI container rendering the Dynamic Island panel anchored to the notch.
public struct DynamicIslandContainerView: View {
    @ObservedObject var controller: DynamicIslandPanelController
    @ObservedObject var policyGate: SafetyPolicyGate = .shared
    @ObservedObject var activationEngine: VoiceActivationEngine = .shared
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var voiceService = VoiceService()
    
    @State private var textInput: String = ""
    @State private var isEditingArguments: Bool = false
    @State private var editedArgumentsText: String = ""
    @State private var isHovered: Bool = false
    
    public init(controller: DynamicIslandPanelController) {
        self.controller = controller
    }
    
    public var body: some View {
        ZStack {
            if controller.isExpanded {
                expandedView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                    ))
            } else {
                collapsedPillView
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: controller.isExpanded)
        .animation(.easeInOut(duration: 0.2), value: policyGate.activeRequest?.id)
        .onAppear {
            setupVoiceBinding()
        }
    }
    
    private var isVoiceRecording: Bool {
        voiceService.state == .recording || activationEngine.state == .recording
    }
    
    private var liveAudioLevel: Float {
        max(voiceService.audioLevel, activationEngine.audioLevel)
    }
    
    // MARK: - Collapsed Pill View
    
    private var collapsedPillView: some View {
        HStack(spacing: 8) {
            // Live Status Indicator / Waveform
            if activationEngine.isMuted {
                Image(systemName: "mic.slash.fill")
                    .foregroundColor(Color.red)
                    .font(.system(size: 11, weight: .bold))
            } else if activationEngine.state == .awake {
                Image(systemName: "sparkles")
                    .foregroundColor(Color.omniAccent)
                    .font(.system(size: 11, weight: .bold))
            } else if isVoiceRecording {
                HStack(spacing: 2) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.omniAccent)
                            .frame(width: 2.5, height: max(4, CGFloat(liveAudioLevel * 20) + CGFloat(index * 2)))
                    }
                }
                .frame(height: 14)
            } else if policyGate.activeRequest != nil {
                Image(systemName: "exclamationmark.shield.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 11, weight: .bold))
            } else {
                Circle()
                    .fill(viewModel.status == .idle ? Color.omniEmerald : Color.omniAmber)
                    .frame(width: 7, height: 7)
                    .shadow(color: (viewModel.status == .idle ? Color.omniEmerald : Color.omniAmber).opacity(0.6), radius: 3)
            }
            
            Text(collapsedStatusText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color.omniTextPrimary)
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.omniTextMuted)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.88))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
        )
        .contentShape(Capsule())
        .onTapGesture {
            controller.setExpanded(true)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var collapsedStatusText: String {
        if activationEngine.isMuted {
            return "Muted (⌥⇧M)"
        } else if activationEngine.state == .awake {
            return "Dhuli: Awake"
        } else if isVoiceRecording {
            return "Listening..."
        } else if let req = policyGate.activeRequest {
            return "Approval: \(req.toolName) (\(req.timeoutRemaining)s)"
        } else if viewModel.status != .idle || activationEngine.state == .processing {
            return "Processing..."
        } else {
            return "OmniDesk"
        }
    }
    
    // MARK: - Expanded Island View
    
    private var expandedView: some View {
        VStack(spacing: 12) {
            // Header Bar
            headerBar
            
            // Content Card: Switches based on Active Gate Request vs Normal Assistant State
            if let request = policyGate.activeRequest {
                approvalCard(request)
            } else {
                standardAssistantBody
            }
        }
        .padding(14)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 16, y: 8)
        )
    }
    
    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(Color.omniAccent)
                    .font(.system(size: 13, weight: .bold))
                
                Text("OmniDesk Assistant")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color.omniTextPrimary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Microphone mute toggle button
                Button(action: { activationEngine.toggleMute() }) {
                    Image(systemName: activationEngine.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(activationEngine.isMuted ? Color.red : Color.omniTextSecondary)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle microphone listening (⌥⇧M)")
                
                // Settings button
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.omniTextSecondary)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                
                // Collapse button
                Button(action: { controller.setExpanded(false) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.omniTextSecondary)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Approval Card View
    
    private func approvalCard(_ request: PendingConfirmationRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with Risk & Timeout Countdown
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                    
                    Text("Action Approval Required")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color.omniTextPrimary)
                }
                
                Spacer()
                
                // Timeout Badge
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text("\(request.timeoutRemaining)s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(request.timeoutRemaining <= 10 ? Color.omniRed : Color.omniAmber)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                
                Text(request.riskLevel.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.omniRed.opacity(0.2))
                    .foregroundColor(Color.omniRed)
                    .clipShape(Capsule())
            }
            
            // Description & Tool
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tool: \(request.toolName)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.omniTextSecondary)
                    Spacer()
                    Text("ID: \(request.connectorId)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.omniTextMuted)
                }
                
                Text(request.descriptionText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.omniTextPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // Parameter Editor Toggle / View
            if isEditingArguments {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Arguments (JSON):")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.omniTextMuted)
                    
                    TextEditor(text: $editedArgumentsText)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(height: 55)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                // Deny Button
                Button(action: { policyGate.rejectActiveRequest(timedOut: false) }) {
                    Text("Deny (⎋)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.omniTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
                
                // Edit Button
                Button(action: toggleEditMode) {
                    Text(isEditingArguments ? "Done" : "Edit (E)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.omniAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.omniAccent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut("e", modifiers: [])
                
                // Allow for Session (if reversible)
                if request.allowsSessionWhitelist {
                    Button(action: { policyGate.allowForSession() }) {
                        Text("Session")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.omniTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Approve Button
                Button(action: commitApproval) {
                    Text("Approve (⏎)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.omniEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
            }
            
            // Hands-Free Speech Cue
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color.omniAccent)
                Text("Say \"Confirm\" or \"Cancel\" to respond hands-free")
                    .font(.system(size: 9))
                    .foregroundColor(Color.omniTextMuted)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
    }
    
    private func toggleEditMode() {
        if !isEditingArguments, let req = policyGate.activeRequest {
            if let data = try? JSONSerialization.data(withJSONObject: req.arguments, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                editedArgumentsText = str
            }
            isEditingArguments = true
        } else {
            isEditingArguments = false
        }
    }
    
    private func commitApproval() {
        if isEditingArguments,
           let data = editedArgumentsText.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            policyGate.resolveActiveRequestWithEdit(newArguments: json)
            isEditingArguments = false
        } else {
            policyGate.approveActiveRequest()
        }
    }
    
    // MARK: - Standard Assistant Body
    
    private var standardAssistantBody: some View {
        VStack(spacing: 10) {
            // Live Voice Visualizer Bar
            HStack(spacing: 8) {
                Button(action: toggleVoiceRecording) {
                    HStack(spacing: 6) {
                        Image(systemName: isVoiceRecording ? "waveform.circle.fill" : "mic.fill")
                            .foregroundColor(isVoiceRecording ? Color.omniRed : Color.omniAccent)
                            .font(.system(size: 14))
                        
                        Text(isVoiceRecording ? "Recording Voice..." : "Click to Speak")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.omniTextPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Status indicator
                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(Color.omniTextSecondary)
                    .lineLimit(1)
            }
            
            // Text Command Input Field
            HStack(spacing: 6) {
                TextField("Ask OmniDesk or type a command...", text: $textInput, onCommit: submitTextCommand)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                    .foregroundColor(Color.omniTextPrimary)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if !textInput.isEmpty {
                    Button(action: submitTextCommand) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.omniAccent)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Active Voice Transcript Preview
            if !voiceService.recognizedText.isEmpty {
                Text("\"\(voiceService.recognizedText)\"")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(Color.omniTextSecondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    private var statusMessage: String {
        switch viewModel.status {
        case .idle:
            return ""
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .actionSuccess(let msg):
            return msg
        case .error(let msg):
            return msg
        }
    }
    
    private func toggleVoiceRecording() {
        if isVoiceRecording {
            voiceService.stopRecording()
            let transcript = voiceService.recognizedText
            if !transcript.isEmpty {
                Task {
                    await viewModel.processVoiceInput(transcript)
                }
            }
        } else {
            voiceService.startRecording()
        }
    }
    
    private func submitTextCommand() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        textInput = ""
        Task {
            await viewModel.processVoiceInput(trimmed)
        }
    }
    
    private func setupVoiceBinding() {
        // Automatically forward speech to MainViewModel voice gate when approval is active
        voiceService.$recognizedText
            .filter { !$0.isEmpty }
            .sink { newTranscript in
                if policyGate.activeRequest != nil {
                    viewModel.handleActiveVoiceApprovalInput(newTranscript)
                }
            }
            .store(in: &cancellables)
            
        // Expand notch panel when assistant wakes up
        activationEngine.$state
            .receive(on: DispatchQueue.main)
            .sink { newState in
                if newState == .awake || newState == .recording {
                    controller.setExpanded(true)
                }
            }
            .store(in: &cancellables)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
    
    private func openSettings() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
