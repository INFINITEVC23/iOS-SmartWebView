import Foundation
import CoreLocation

// MARK: - Permission Manager
// This is the class your UI calls to trigger permission checks.
class PermissionManager: ObservableObject {
    // We initialize the plugin directly here
    private let locationPlugin = LocationPlugin()
    
    func checkPermissions() {
        // FIX: This now correctly calls the method in the class below
        locationPlugin.requestInitialPermission()
    }
}

// MARK: - Location Plugin
// This handles the actual CoreLocation hardware communication.
class LocationPlugin: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        // Standard accuracy for web-based location services
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // FIX: Added this specific method to satisfy the PermissionManager call
    func requestInitialPermission() {
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    // Delegate method to handle the user's response to the popup
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
        // This is where you'd send data back to the WebView if needed
        guard let location = locations.last else { return }
        print("Lat: \(location.coordinate.latitude), Lon: \(location.coordinate.longitude)")
    }
}
