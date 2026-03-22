import Foundation
import UserNotifications
import CoreLocation
import UIKit

class PermissionManager: NSObject { 
    static let shared = PermissionManager()
    
    private override init() {
        super.init()
    }
    
    func requestInitialPermissions() {
        let context = SWVContext.shared
        
        if context.permissionsOnLaunch.contains("NOTIFICATIONS") {
            requestNotificationPermission()
        }
        
        if context.permissionsOnLaunch.contains("LOCATION") {
            if let locationPlugin = PluginManager.shared.getPlugin(named: "Location") as? LocationPlugin {
                locationPlugin.requestInitialPermission()
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                } else if let error = error {
                    print("Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("PermissionManager: Location authorization status changed to: \(manager.authorizationStatus.rawValue)")
    }
}
