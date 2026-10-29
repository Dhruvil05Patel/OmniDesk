//
//  OmniDeskApp.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import SwiftUI

@main
struct OmniDeskApp: App {
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .onAppear {
                    themeManager.applyTheme()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView()
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
    }
}
