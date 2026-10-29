//
//  DesignTokens.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 28/10/26.
//

import SwiftUI
import AppKit
import Combine

// MARK: - App Theme Mode (System, Dark, Light)
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case dark = "dark"
    case light = "light"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }
    
    var iconName: String {
        switch self {
        case .system:
            return "laptopcomputer"
        case .dark:
            return "moon.fill"
        case .light:
            return "sun.max.fill"
        }
    }
    
    var description: String {
        switch self {
        case .system:
            return "Follows your macOS system appearance automatically."
        case .dark:
            return "Always use high-contrast dark mode."
        case .light:
            return "Always use clean, crisp light mode."
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

// MARK: - Global Theme Manager
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "app_theme")
            applyTheme()
        }
    }
    
    init() {
        let raw = UserDefaults.standard.string(forKey: "app_theme") ?? AppTheme.system.rawValue
        self.currentTheme = AppTheme(rawValue: raw) ?? .system
        applyTheme()
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }
    
    func applyTheme() {
        let targetAppearance: NSAppearance?
        switch currentTheme {
        case .system:
            targetAppearance = nil
        case .dark:
            targetAppearance = NSAppearance(named: .darkAqua)
        case .light:
            targetAppearance = NSAppearance(named: .aqua)
        }
        
        NSApplication.shared.appearance = targetAppearance
        for window in NSApplication.shared.windows {
            window.appearance = targetAppearance
        }
    }
}

// MARK: - Semantic Adaptive Color Tokens (Dynamic Light / Dark)
extension Color {
    /// Native AppKit dynamic color that respects NSApplication appearance and system appearance
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
    
    /// Canvas background: Deep obsidian in dark mode, clean slate off-white in light mode
    static let omniBackground = Color.adaptive(
        light: NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1.0),
        dark: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0)
    )
    
    /// Card surface: Solid pure white in light mode, deep charcoal in dark mode
    static let omniCardSurface = Color.adaptive(
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)
    )
    
    /// Card surface hover state
    static let omniCardSurfaceHover = Color.adaptive(
        light: NSColor(srgbRed: 0.97, green: 0.98, blue: 0.99, alpha: 1.0),
        dark: NSColor(srgbRed: 0.15, green: 0.16, blue: 0.20, alpha: 1.0)
    )
    
    /// Recessed background for textfields, inputs, and transcription container
    static let omniInputSurface = Color.adaptive(
        light: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0),
        dark: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0)
    )
    
    /// Precision 1px border stroke
    static let omniBorder = Color.adaptive(
        light: NSColor(white: 0.0, alpha: 0.09),
        dark: NSColor(white: 1.0, alpha: 0.08)
    )
    
    /// Active or hovered 1px border stroke
    static let omniBorderHover = Color.adaptive(
        light: NSColor(white: 0.0, alpha: 0.18),
        dark: NSColor(white: 1.0, alpha: 0.18)
    )
    
    // MARK: High-Contrast Typography Tokens
    /// Crisp, high-contrast primary text
    static let omniTextPrimary = Color.adaptive(
        light: NSColor(srgbRed: 0.06, green: 0.09, blue: 0.15, alpha: 1.0), // Deep ink/navy
        dark: NSColor(white: 0.95, alpha: 1.0)
    )
    
    /// Clean, readable secondary text
    static let omniTextSecondary = Color.adaptive(
        light: NSColor(srgbRed: 0.28, green: 0.33, blue: 0.42, alpha: 1.0), // Clean medium slate
        dark: NSColor(srgbRed: 0.65, green: 0.68, blue: 0.74, alpha: 1.0)
    )
    
    /// Muted tertiary text and subtle metadata
    static let omniTextMuted = Color.adaptive(
        light: NSColor(srgbRed: 0.45, green: 0.50, blue: 0.58, alpha: 1.0),
        dark: NSColor(srgbRed: 0.44, green: 0.47, blue: 0.52, alpha: 1.0)
    )
    
    /// Sub-surface background for interactive badges & pills
    static let omniPillBackground = Color.adaptive(
        light: NSColor(white: 0.0, alpha: 0.05),
        dark: NSColor(white: 1.0, alpha: 0.04)
    )
    
    /// Bottom status footer background
    static let omniFooterBackground = Color.adaptive(
        light: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 0.95),
        dark: NSColor(white: 0.0, alpha: 0.40)
    )
    
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
    @Environment(\.colorScheme) private var colorScheme
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
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.05),
                radius: colorScheme == .dark ? 10 : 6,
                x: 0,
                y: colorScheme == .dark ? 4 : 2
            )
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
            .background(Color.omniPillBackground)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.omniBorder, lineWidth: 0.5)
            )
    }
}

// MARK: - View Extensions
extension View {
    /// Wraps content in a Linear/Raycast style container with adaptive 1px border and elevation
    func minimalCard(padding: CGFloat = 16, cornerRadius: CGFloat = 12, isHovered: Bool = false) -> some View {
        self.modifier(MinimalCardModifier(padding: padding, cornerRadius: cornerRadius, isHovered: isHovered))
    }
}
