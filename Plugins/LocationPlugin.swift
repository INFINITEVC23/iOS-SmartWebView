import Foundation
import CoreLocation

class LocationPlugin: NSObject, CLLocationManagerDelegate {
    // FIXED: Added shared instance
    static let shared = LocationPlugin()
    
    // FIXED: Added register method to satisfy the App's registerPlugins call
    static func register() {
        print("Location Plugin Registered")
    }
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        // Standard accuracy for web-based location services
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // Your original logic
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
        // Your original logic
        guard let location = locations.last else { return }
        print("Lat: \(location.coordinate.latitude), Lon: \(location.coordinate.longitude)")
    }
}
