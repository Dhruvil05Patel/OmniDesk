//
//  DesignTokens.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 28/10/26.
//

import SwiftUI

// MARK: - Semantic Color Tokens
extension Color {
    /// Deep frosted background color
    static let omniBackground = Color(red: 0.06, green: 0.07, blue: 0.09)
    
    /// Translucent card surface to layer over materials
    static let omniCardSurface = Color.black.opacity(0.32)
    
    /// Precision 1px border stroke for dark interfaces
    static let omniBorder = Color.white.opacity(0.08)
    
    /// Active / hovered 1px border stroke
    static let omniBorderHover = Color.white.opacity(0.18)
    
    /// Minimalist primary brand accent (Electric Indigo)
    static let omniAccent = Color(red: 99/255, green: 102/255, blue: 241/255)
    
    /// Status success / completion
    static let omniEmerald = Color(red: 16/255, green: 185/255, blue: 129/255)
    
    /// Warning / listening amber
    static let omniAmber = Color(red: 245/255, green: 158/255, blue: 11/255)
    
    /// Recording / destructive crimson
    static let omniRed = Color(red: 239/255, green: 68/255, blue: 68/255)
}

// MARK: - Minimalist Card Modifier (Linear / Raycast Style)
struct MinimalCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var isHovered: Bool = false
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial)
            .background(Color.omniCardSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isHovered ? Color.omniBorderHover : Color.omniBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Keyboard Shortcut Badge View
struct KeyboardShortcutBadge: View {
    let shortcut: String
    
    var body: some View {
        Text(shortcut)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Color.white.opacity(0.06))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - View Extensions
extension View {
    /// Wraps content in a Linear/Raycast style frosted glass container with 1px border
    func minimalCard(padding: CGFloat = 16, cornerRadius: CGFloat = 12, isHovered: Bool = false) -> some View {
        self.modifier(MinimalCardModifier(padding: padding, cornerRadius: cornerRadius, isHovered: isHovered))
    }
}
