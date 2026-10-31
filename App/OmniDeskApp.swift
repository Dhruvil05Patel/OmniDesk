//
//  OmniDeskApp.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import SwiftUI
import AppKit

/// Application Delegate managing resident background life cycle, panel startup, and global hotkeys.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeManager.shared.applyTheme()
        DynamicIslandPanelController.shared.start()
        MenuBarExtraController.shared.start()
        
        GlobalHotKeyManager.shared.registerDefaultHotKey {
            DynamicIslandPanelController.shared.toggleExpanded()
        }
        
        GlobalHotKeyManager.shared.registerMuteHotKey {
            VoiceActivationEngine.shared.toggleMute()
        }
        
        VoiceActivationEngine.shared.startEngine()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        VoiceActivationEngine.shared.stopEngine()
        SafetyPolicyGate.shared.abortAllPendingRequests()
        GlobalHotKeyManager.shared.unregister()
    }
}

@main
struct OmniDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some Scene {
        Settings {
            SettingsView()
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
    }
}
