//
//  ActionConfirmationModalView.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 30/10/26.
//

import SwiftUI

/// Modal overlay rendered when a high-risk or destructive action requires explicit human authorization.
public struct ActionConfirmationModalView: View {
    @ObservedObject var policyGate: SafetyPolicyGate = .shared
    
    public init() {}
    
    public var body: some View {
        if let request = policyGate.activeRequest {
            ZStack {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(alignment: .leading, spacing: 16) {
                    // Header with warning icon and risk badge
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Action Authorization Required")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("The AI assistant is requesting permission to execute an outbound or state-modifying action on your MacBook.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(request.riskLevel.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                    
                    Divider()
                    
                    // Action Details Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tool:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text(request.toolName)
                                .font(.caption.monospaced())
                                .foregroundColor(.primary)
                        }
                        
                        Text(request.descriptionText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    
                    // Parameters Breakdown
                    if !request.arguments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parameters:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            ForEach(Array(request.arguments.keys.sorted()), id: \.self) { key in
                                HStack(alignment: .top) {
                                    Text("\(key):")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    Text(String(describing: request.arguments[key] ?? ""))
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(6)
                    }
                    
                    Divider()
                    
                    // Action Buttons
                    HStack {
                        Button(action: {
                            policyGate.rejectActiveRequest()
                        }) {
                            Text("Cancel / Deny")
                                .frame(minWidth: 100)
                        }
                        .keyboardShortcut(.cancelAction)
                        
                        Spacer()
                        
                        Button(action: {
                            policyGate.approveActiveRequest()
                        }) {
                            Text("Authorize Action")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.red)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .frame(width: 520)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 20)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.easeInOut(duration: 0.2), value: policyGate.activeRequest?.id)
        }
    }
}
