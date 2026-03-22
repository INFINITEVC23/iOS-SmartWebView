import SwiftUI

// --- GLOBAL SETTINGS (Prevents "Cannot find in scope" errors) ---
class SWVContext {
    static let shared = SWVContext()
    var pullToRefreshEnabled = true
    var fileUploadsEnabled = true
    var multipleUploadsEnabled = true
    var enabledPlugins: [String] = ["Toast", "Dialog", "Location", "Rating", "Playground"]
}

class PermissionManager {
    static let shared = PermissionManager()
    func requestInitialPermissions() {
        LocationPlugin.shared.requestInitialPermission()
    }
}

// Fixed placeholders for plugins not yet fully implemented
class ToastPlugin { static func register() {} }
class DialogPlugin { static func register() {} }
class RatingPlugin { static func register() {} }
class Playground { static func register() {} }
// -------------------------------------------------------------

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

@main
struct iOS_SmartWebViewApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        registerPlugins()
        PermissionManager.shared.requestInitialPermissions()
    }
    
    var body: some Scene {
        WindowGroup {
            // Edit this URL to your site
            WebView(url: URL(string: "https://www.google.com")!)
                .ignoresSafeArea()
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
