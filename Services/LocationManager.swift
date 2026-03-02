import CoreLocation
import Foundation

final class LocationManager: NSObject, Sendable {
    static let shared = LocationManager()

    // Published location values (nonisolated(unsafe) for Sendable conformance)
    nonisolated(unsafe) private(set) var currentLatitude: Double?
    nonisolated(unsafe) private(set) var currentLongitude: Double?

    nonisolated(unsafe) private let manager: CLLocationManager

    private override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermissionAndStart() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startMonitoring()
        default:
            break
        }
    }

    private func startMonitoring() {
        manager.startMonitoringSignificantLocationChanges()
        // Also get an initial fix
        manager.requestLocation()
    }
}

extension LocationManager: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLatitude = location.coordinate.latitude
        currentLongitude = location.coordinate.longitude
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently handle — location is best-effort
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startMonitoring()
        default:
            break
        }
    }
}
