//
//  DesignTokens.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 28/10/26.
//

import SwiftUI

// MARK: - Semantic Color Tokens (High-Contrast Linear/Raycast Dark Theme)
extension Color {
    /// Deep dark obsidian background
    static let omniBackground = Color(red: 0.08, green: 0.09, blue: 0.11)
    
    /// Solid rich dark card surface (eliminates muddy translucency)
    static let omniCardSurface = Color(red: 0.12, green: 0.13, blue: 0.16)
    
    /// Slightly lighter surface for hover states
    static let omniCardSurfaceHover = Color(red: 0.15, green: 0.16, blue: 0.20)
    
    /// Deep inset background for textfields and input areas
    static let omniInputSurface = Color(red: 0.09, green: 0.10, blue: 0.13)
    
    /// Precision 1px border stroke
    static let omniBorder = Color.white.opacity(0.08)
    
    /// Active or hovered 1px border stroke
    static let omniBorderHover = Color.white.opacity(0.18)
    
    // MARK: High-Contrast Text Tokens (Independent of System Light/Dark quirks)
    /// Crisp, high-contrast primary text
    static let omniTextPrimary = Color(white: 0.95)
    
    /// Clean, readable secondary text
    static let omniTextSecondary = Color(red: 0.65, green: 0.68, blue: 0.74)
    
    /// Muted tertiary text and subtle metadata
    static let omniTextMuted = Color(red: 0.44, green: 0.47, blue: 0.52)
    
    // MARK: Accent Colors
    /// Primary brand accent (Electric Indigo)
    static let omniAccent = Color(red: 99/255, green: 102/255, blue: 241/255)
    
    /// Active / Success Emerald
    static let omniEmerald = Color(red: 52/255, green: 211/255, blue: 153/255)
    
    /// Warning Amber
    static let omniAmber = Color(red: 251/255, green: 191/255, blue: 36/255)
    
    /// Recording / Error Crimson
    static let omniRed = Color(red: 248/255, green: 113/255, blue: 113/255)
}

// MARK: - Minimalist Card Modifier (Linear / Raycast Style)
struct MinimalCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var isHovered: Bool = false
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(isHovered ? Color.omniCardSurfaceHover : Color.omniCardSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isHovered ? Color.omniBorderHover : Color.omniBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Keyboard Shortcut Badge View
struct KeyboardShortcutBadge: View {
    let shortcut: String
    
    var body: some View {
        Text(shortcut)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color.omniTextSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Color.white.opacity(0.06))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}

// MARK: - View Extensions
extension View {
    /// Wraps content in a Linear/Raycast style dark container with 1px border
    func minimalCard(padding: CGFloat = 16, cornerRadius: CGFloat = 12, isHovered: Bool = false) -> some View {
        self.modifier(MinimalCardModifier(padding: padding, cornerRadius: cornerRadius, isHovered: isHovered))
    }
}
