import Foundation

class PermissionManager: ObservableObject {
    // FIXED: Added shared instance so the App can call it
    static let shared = PermissionManager()
    
    // FIXED: Uses the shared plugin instance
    private let locationPlugin = LocationPlugin.shared
    
    func checkPermissions() {
        // Your original logic
        locationPlugin.requestInitialPermission()
    }
    
    // FIXED: Added this to match the call in your App's init
    func requestInitialPermissions() {
        checkPermissions()
    }
}
