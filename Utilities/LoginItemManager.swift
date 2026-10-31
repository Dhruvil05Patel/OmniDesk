//
//  LoginItemManager.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/10/26.
//

import Foundation
import ServiceManagement
import Combine

/// Manages launch-at-login state using Apple's modern `SMAppService` (macOS 13+).
@MainActor
public final class LoginItemManager: ObservableObject {
    
    public static let shared = LoginItemManager()
    
    @Published public private(set) var isEnabled: Bool = false
    
    public init() {
        refreshStatus()
    }
    
    public func refreshStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }
    
    public func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("⚠️ [LoginItemManager] Failed to toggle login item:", error.localizedDescription)
            }
            refreshStatus()
        }
    }
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
}
