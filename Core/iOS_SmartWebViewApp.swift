import SwiftUI

@main
struct iOS_SmartWebViewApp: App {
    // This uses the AppDelegate already defined in your Managers/AppDelegate.swift
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            // This uses the main ContentView which handles the WebView and Config
            ContentView()
                .ignoresSafeArea()
        }
    }
}
