//
//  OmniDeskApp.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import SwiftUI

@main
struct OmniDeskApp: App {
    @AppStorage("app_theme") private var appThemeRaw: String = AppTheme.system.rawValue
    
    private var currentTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }
    
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(currentTheme.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Settings {
            SettingsView()
                .preferredColorScheme(currentTheme.colorScheme)
        }
    }
}
