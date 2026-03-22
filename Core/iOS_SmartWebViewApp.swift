import SwiftUI

// FIXED: Added missing AppDelegate class
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
}

@main
struct iOS_SmartWebViewApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        registerPlugins()
        // FIXED: Now calls the shared instance correctly
        PermissionManager.shared.requestInitialPermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            // Change the URL string below to your website
            WebView(url: URL(string: "https://www.google.com")!)
        }
    }
    
    private func registerPlugins() {
        let context = SWVContext.shared
        
        if context.enabledPlugins.contains("Toast") { ToastPlugin.register() }
        if context.enabledPlugins.contains("Playground") { Playground.register() }
        if context.enabledPlugins.contains("Dialog") { DialogPlugin.register() }
        if context.enabledPlugins.contains("Location") { LocationPlugin.register() }
        if context.enabledPlugins.contains("Rating") { RatingPlugin.register() }
    }
}
