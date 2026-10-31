//
//  ActionConfirmationModalView.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import SwiftUI

/// Modal overlay rendered when a high-risk or destructive action requires explicit human authorization.
public struct ActionConfirmationModalView: View {
    @ObservedObject var policyGate: SafetyPolicyGate
    
    public init(policyGate: SafetyPolicyGate = .shared) {
        self.policyGate = policyGate
    }
    
    public var body: some View {
        if let request = policyGate.activeRequest {
            ZStack {
                // Dimmed glassmorphic backdrop blocking background interactions
                Color.black.opacity(0.55)
                    .edgesIgnoringSafeArea(.all)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Prevent dismissing by tapping outside to enforce explicit choice
                    }
                
                // Centered Confirmation Dialog Card
                VStack(alignment: .leading, spacing: 16) {
                    // Header with warning icon and risk badge
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 26))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Action Authorization Required")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(Color.omniTextPrimary)
                            
                            Text("OmniDesk assistant is requesting permission to execute an action on your Mac.")
                                .font(.system(size: 11))
                                .foregroundColor(Color.omniTextSecondary)
                        }
                        
                        Spacer()
                        
                        Text(request.riskLevel.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(riskBadgeBackground(for: request.riskLevel))
                            .foregroundColor(riskBadgeTextColor(for: request.riskLevel))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(riskBadgeBorderColor(for: request.riskLevel), lineWidth: 1)
                            )
                    }
                    
                    Divider()
                        .background(Color.omniBorder)
                    
                    // Action Details Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("TOOL:")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.omniTextMuted)
                            
                            Text(request.toolName)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color.omniTextPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.omniPillBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            
                            Spacer()
                            
                            Text("ID: \(request.connectorId)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color.omniTextMuted)
                        }
                        
                        Text(request.descriptionText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.omniTextPrimary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.omniInputSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.omniBorder, lineWidth: 1)
                            )
                        
                        // Hands-free voice confirmation badge
                        HStack(spacing: 5) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color.omniAccent)
                            Text("Say \"Confirm\" or \"Cancel\" to respond hands-free")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.omniTextSecondary)
                        }
                        .padding(.top, 2)
                    }
                    
                    // Parameters Breakdown
                    if !request.arguments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PARAMETERS:")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.omniTextMuted)
                            
                            VStack(spacing: 4) {
                                ForEach(Array(request.arguments.keys.sorted()), id: \.self) { key in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(key):")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundColor(Color.omniTextSecondary)
                                            .frame(width: 110, alignment: .leading)
                                        
                                        Text(String(describing: request.arguments[key] ?? ""))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(Color.omniTextPrimary)
                                            .lineLimit(2)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                }
                            }
                            .padding(6)
                            .background(Color.omniInputSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.omniBorder, lineWidth: 1)
                            )
                        }
                    }
                    
                    Divider()
                        .background(Color.omniBorder)
                    
                    // Action Buttons with standard keyboard shortcuts
                    HStack(spacing: 12) {
                        Button(action: {
                            policyGate.rejectActiveRequest()
                        }) {
                            HStack(spacing: 6) {
                                KeyboardShortcutBadge(shortcut: "ESC")
                                Text("Cancel / Deny")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(Color.omniTextSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.omniPillBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.omniBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        
                        Spacer()
                        
                        Button(action: {
                            policyGate.approveActiveRequest()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 11))
                                Text("Authorize Action")
                                    .font(.system(size: 12, weight: .semibold))
                                KeyboardShortcutBadge(shortcut: "↵")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.omniRed)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: Color.omniRed.opacity(0.35), radius: 6, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
                .frame(width: 480)
                .background(Color.omniCardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.omniBorderHover, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 24, y: 12)
            }
        }
    }
    
    private func riskBadgeBackground(for level: ActionRiskLevel) -> Color {
        switch level {
        case .destructiveOrOutbound:
            return Color.omniRed.opacity(0.12)
        case .reversibleWrite:
            return Color.omniAmber.opacity(0.12)
        case .safeReadOnly:
            return Color.omniEmerald.opacity(0.12)
        }
    }
    
    private func riskBadgeTextColor(for level: ActionRiskLevel) -> Color {
        switch level {
        case .destructiveOrOutbound:
            return Color.omniRed
        case .reversibleWrite:
            return Color.omniAmber
        case .safeReadOnly:
            return Color.omniEmerald
        }
    }
    
    private func riskBadgeBorderColor(for level: ActionRiskLevel) -> Color {
        switch level {
        case .destructiveOrOutbound:
            return Color.omniRed.opacity(0.3)
        case .reversibleWrite:
            return Color.omniAmber.opacity(0.3)
        case .safeReadOnly:
            return Color.omniEmerald.opacity(0.3)
        }
    }
}
