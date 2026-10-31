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
    private var eventHandler: EventHandlerRef?
    private var onTrigger: (@MainActor () -> Void)?
    
    private init() {}
    
    /// Registers a global hotkey (default: Option + Space = Keycode 49 with optionKey).
    public func registerDefaultHotKey(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
        
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
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        
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
    
    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
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
