//
//  DynamicIslandPanelController.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/10/26.
//

import AppKit
import SwiftUI
import Combine

/// Hardware display helper detecting macOS camera housing ("notch") geometry.
public extension NSScreen {
    var hasHardwareNotch: Bool {
        if #available(macOS 12.0, *) {
            return auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
        }
        return false
    }
    
    var notchRect: NSRect? {
        guard #available(macOS 12.0, *),
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }
        let notchWidth = frame.width - (left.width + right.width)
        let notchHeight = left.height
        let notchX = left.maxX
        let notchY = frame.maxY - notchHeight
        return NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
    }
}

/// Custom borderless NSPanel that floats at status/popup level and persists across all Spaces.
final class DynamicIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
    }
}

/// Central controller managing the Dynamic Island NSPanel, notch detection, and expansion transitions.
@MainActor
public final class DynamicIslandPanelController: NSObject, ObservableObject, NSWindowDelegate {
    
    public static let shared = DynamicIslandPanelController()
    
    @Published public private(set) var isExpanded: Bool = false
    @Published public private(set) var hasNotch: Bool = false
    @Published public private(set) var activeNotchRect: NSRect = .zero
    
    private var panel: DynamicIslandPanel?
    private var cancellables = Set<AnyCancellable>()
    
    public override init() {
        super.init()
        setupNotifications()
    }
    
    public func start() {
        guard panel == nil else { return }
        
        let targetScreen = NSScreen.main ?? NSScreen.screens.first!
        let hasNotch = targetScreen.hasHardwareNotch
        self.hasNotch = hasNotch
        
        let initialWidth: CGFloat = hasNotch ? (targetScreen.notchRect?.width ?? 200) + 20 : 200
        let initialHeight: CGFloat = hasNotch ? (targetScreen.notchRect?.height ?? 34) : 34
        let initialRect = calculateFrame(width: initialWidth, height: initialHeight, on: targetScreen)
        
        let panel = DynamicIslandPanel(contentRect: initialRect)
        panel.delegate = self
        
        let containerView = DynamicIslandContainerView(controller: self)
        panel.contentView = NSHostingView(rootView: containerView)
        
        self.panel = panel
        repositionPanel(animated: false)
        panel.orderFrontRegardless()
    }
    
    public func toggleExpanded() {
        setExpanded(!isExpanded)
    }
    
    public func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        repositionPanel(animated: true)
        
        if expanded {
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    public func repositionPanel(animated: Bool = true) {
        guard let panel = panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let hasNotch = screen.hasHardwareNotch
        self.hasNotch = hasNotch
        
        if let rect = screen.notchRect {
            self.activeNotchRect = rect
        }
        
        let targetWidth: CGFloat = isExpanded ? 440 : (hasNotch ? (screen.notchRect?.width ?? 200) + 16 : 190)
        let targetHeight: CGFloat = isExpanded ? 320 : (hasNotch ? (screen.notchRect?.height ?? 34) : 34)
        
        let targetRect = calculateFrame(width: targetWidth, height: targetHeight, on: screen)
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetRect, display: true)
            }
        } else {
            panel.setFrame(targetRect, display: true)
        }
    }
    
    private func calculateFrame(width: CGFloat, height: CGFloat, on screen: NSScreen) -> NSRect {
        let hasNotch = screen.hasHardwareNotch
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2.0
        
        if hasNotch {
            // Snug against the top bezel inside/surrounding the camera housing
            let y = screenFrame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)
        } else {
            // Anchor 6 points below the standard macOS menu bar
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            let y = screenFrame.maxY - menuBarHeight - height - 6
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionPanel(animated: false)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionPanel(animated: false)
            }
            .store(in: &cancellables)
    }
}
