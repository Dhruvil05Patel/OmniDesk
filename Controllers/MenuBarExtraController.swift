//
//  MenuBarExtraController.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/10/26.
//

import AppKit
import SwiftUI

/// Manages the system status bar item (`NSStatusItem`) providing quick menu access and fallback.
@MainActor
public final class MenuBarExtraController: NSObject {
    
    public static let shared = MenuBarExtraController()
    
    private var statusItem: NSStatusItem?
    
    public override init() {
        super.init()
    }
    
    public func start() {
        guard statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "OmniDesk Assistant")
            button.toolTip = "OmniDesk Assistant (⌥ Space)"
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        self.statusItem = item
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
            showContextMenu(from: sender)
        } else {
            // Left click toggles the Dynamic Island panel
            DynamicIslandPanelController.shared.toggleExpanded()
        }
    }
    
    public func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(title: "Toggle OmniDesk", action: #selector(toggleAssistant), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.option]
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let wakeWordEnabled = VoiceActivationEngine.shared.isWakeWordEnabled
        let wakeWordItem = NSMenuItem(
            title: wakeWordEnabled ? "Disable Wake Word ('Dhuli')" : "Enable Wake Word ('Dhuli')",
            action: #selector(toggleWakeWord),
            keyEquivalent: ""
        )
        wakeWordItem.target = self
        wakeWordItem.state = wakeWordEnabled ? .on : .off
        menu.addItem(wakeWordItem)
        
        let isMuted = VoiceActivationEngine.shared.isMuted
        let muteItem = NSMenuItem(
            title: isMuted ? "Unmute Microphone" : "Mute Microphone",
            action: #selector(toggleMute),
            keyEquivalent: "m"
        )
        muteItem.keyEquivalentModifierMask = [.option, .shift]
        muteItem.target = self
        menu.addItem(muteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings & Activity History...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItemManager.shared.isEnabled ? .on : .off
        menu.addItem(loginItem)
        
        let clearApprovals = NSMenuItem(title: "Clear Session Approvals", action: #selector(clearSessionApprovals), keyEquivalent: "")
        clearApprovals.target = self
        menu.addItem(clearApprovals)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit OmniDesk", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.popUpMenu(menu)
    }
    
    @objc private func toggleAssistant() {
        DynamicIslandPanelController.shared.toggleExpanded()
    }
    
    @objc private func toggleWakeWord() {
        VoiceActivationEngine.shared.isWakeWordEnabled.toggle()
    }
    
    @objc private func toggleMute() {
        VoiceActivationEngine.shared.toggleMute()
    }
    
    @objc private func openSettingsWindow() {
        SettingsWindowController.shared.show()
    }
    
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LoginItemManager.shared.toggle()
        sender.state = LoginItemManager.shared.isEnabled ? .on : .off
    }
    
    @objc private func clearSessionApprovals() {
        SafetyPolicyGate.shared.clearSessionWhitelist()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
