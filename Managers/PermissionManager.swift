import Foundation
import CoreLocation

// MARK: - Permission Manager
class PermissionManager: ObservableObject {
    // FIXED: Added shared instance so the App struct can find it
    static let shared = PermissionManager()
    
    // FIXED: Changed to use the shared LocationPlugin
    private let locationPlugin = LocationPlugin.shared
    
    func checkPermissions() {
        locationPlugin.requestInitialPermission()
    }
    
    // FIXED: Added this specific name to match what your @main App calls
    func requestInitialPermissions() {
        checkPermissions()
    }
}

// MARK: - Location Plugin
class LocationPlugin: NSObject, CLLocationManagerDelegate {
    // FIXED: Added shared instance
    static let shared = LocationPlugin()
    
    // FIXED: Added register method so the App's registerPlugins() works
    static func register() {
        print("Location Plugin Registered")
    }
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestInitialPermission() {
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location Access Granted")
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            print("Location Access Denied")
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("Lat: \(location.coordinate.latitude), Lon: \(location.coordinate.longitude)")
    }
}
