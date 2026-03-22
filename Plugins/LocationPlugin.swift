import Foundation
import CoreLocation

class LocationPlugin: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPlugin()
    static func register() { print("Location Ready") }
    
    private let locationManager = CLLocationManager()
    
    func requestInitialPermission() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            locationManager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            print("Location: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        }
    }
}
