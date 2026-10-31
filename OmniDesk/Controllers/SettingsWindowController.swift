//
//  SettingsWindowController.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 01/11/26.
//

import AppKit
import SwiftUI

/// Window controller that reliably manages and displays the standalone Settings & Customization window
/// across accessory (LSUIElement) and menu-bar application lifecycles.
@MainActor
public final class SettingsWindowController: NSWindowController {
    
    public static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OmniDesk Settings"
        window.isReleasedWhenClosed = false
        window.center()
        
        let hosting = NSHostingController(rootView: SettingsView())
        window.contentViewController = hosting
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Presents the Settings window, centering it and activating the application.
    public func show() {
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
