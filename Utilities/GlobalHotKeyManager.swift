//
//  GlobalHotKeyManager.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/10/26.
//

import Carbon
import AppKit

/// Global Hotkey Manager using Carbon's `RegisterEventHotKey`.
/// Operates without requiring macOS Accessibility (AXUIElement) permissions.
public final class GlobalHotKeyManager {
    
    public static let shared = GlobalHotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var muteHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onTrigger: (@MainActor () -> Void)?
    private var onMuteTrigger: (@MainActor () -> Void)?
    
    private init() {}
    
    /// Registers a global hotkey (default: Option + Space = Keycode 49 with optionKey).
    public func registerDefaultHotKey(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
        setupEventHandlerIfNeeded()
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 1) // 'OMNI'
        let modifiers = UInt32(optionKey)
        let keyCode = UInt32(kVK_Space) // 49
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("⚠️ [GlobalHotKeyManager] Failed to register Option+Space hotkey, error code:", status)
        }
    }
    
    /// Registers a global mute hotkey (Option + Shift + M = Keycode 46 with optionKey | shiftKey).
    public func registerMuteHotKey(onTrigger: @escaping @MainActor () -> Void) {
        self.onMuteTrigger = onTrigger
        setupEventHandlerIfNeeded()
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F4D4E49), id: 2) // 'OMNI' id 2
        let modifiers = UInt32(optionKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_M) // 46
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &muteHotKeyRef
        )
        
        if status != noErr {
            print("⚠️ [GlobalHotKeyManager] Failed to register Option+Shift+M mute hotkey, error code:", status)
        }
    }
    
    private func setupEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if hotKeyID.id == 1 {
                    Task { @MainActor in
                        manager.onTrigger?()
                    }
                } else if hotKeyID.id == 2 {
                    Task { @MainActor in
                        manager.onMuteTrigger?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }
    
    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = muteHotKeyRef {
            UnregisterEventHotKey(ref)
            muteHotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    deinit {
        unregister()
    }
}
