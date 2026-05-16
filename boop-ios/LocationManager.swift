//
//  LocationManager.swift
//  boop-ios
//
//  Tracks device location continuously for path recording.
//  Keeps a rolling buffer of recent coordinates for use when boops are created.
//

import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject {

    @Published var currentLocationName: String = ""
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let clManager = CLLocationManager()

    // Rolling buffer of recent coordinates with timestamps (up to maxBufferSize)
    private var coordinateBuffer: [(timestamp: Date, coordinate: CLLocationCoordinate2D)] = []
    private let maxBufferSize = 3500
    // Minimum distance (meters) between recorded points to avoid GPS noise
    private let minDistanceBetweenPoints: Double = 1.0

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.distanceFilter = minDistanceBetweenPoints
        authorizationStatus = clManager.authorizationStatus
    }

    // MARK: - Public API

    func requestPermissionIfNeeded() {
        switch clManager.authorizationStatus {
        case .notDetermined:
            clManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startTracking()
        default:
            break
        }
    }

    func startTracking() {
        guard clManager.authorizationStatus == .authorizedWhenInUse ||
              clManager.authorizationStatus == .authorizedAlways else { return }
        clManager.startUpdatingLocation()
    }

    func stopTracking() {
        clManager.stopUpdatingLocation()
    }

    /// Returns a snapshot of the current path buffer for storage with a boop.
    func snapshotPath() -> [CLLocationCoordinate2D] {
        return coordinateBuffer.map(\.coordinate)
    }

    /// Returns coordinates recorded between two timestamps.
    func getLocations(from startDate: Date, to endDate: Date) -> [CLLocationCoordinate2D] {
        return coordinateBuffer
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .map(\.coordinate)
    }

    /// Returns the current single coordinate for use when there's no path.
    func currentCoordinate() -> CLLocationCoordinate2D? {
        return coordinateBuffer.last?.coordinate
    }

    /// Reverse geocodes the most recent coordinate to a human-readable location name.
    func reverseGeocodeCurrentLocation() async -> String {
        guard let coordinate = coordinateBuffer.last?.coordinate else { return "" }
        return await reverseGeocode(coordinate)
    }

    // MARK: - Reverse Geocoding

    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return "" }
            return formatPlacemark(placemark)
        } catch {
            return ""
        }
    }

    // MARK: - Helpers

    private func formatPlacemark(_ placemark: CLPlacemark) -> String {
        // Prefer: "Neighborhood, City" or "Street, City"
        var parts: [String] = []
        if let subLocality = placemark.subLocality {
            parts.append(subLocality)
        } else if let thoroughfare = placemark.thoroughfare {
            parts.append(thoroughfare)
        }
        if let locality = placemark.locality {
            parts.append(locality)
        }
        if parts.isEmpty, let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                startTracking()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last,
              newLocation.horizontalAccuracy > 0.1 else { return }

        let accuracy = newLocation.horizontalAccuracy
        let coordinate = newLocation.coordinate

        Task { @MainActor in
            appendToBuffer(coordinate)
        }
    }

    private func appendToBuffer(_ coordinate: CLLocationCoordinate2D) {
        // Filter out points too close to the last recorded point
        if let last = coordinateBuffer.last {
            let lastLocation = CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
            let newLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard newLocation.distance(from: lastLocation) >= minDistanceBetweenPoints else { return }
        }

        coordinateBuffer.append((timestamp: Date(),
                                 coordinate: coordinate))
        if coordinateBuffer.count > maxBufferSize {
            coordinateBuffer.removeFirst()
        }

        // Reverse-geocode in the background on significant location changes (every ~20 new points)
        if coordinateBuffer.count % 20 == 1 {
            Task {
                let name = await reverseGeocode(coordinate)
                if !name.isEmpty {
                    currentLocationName = name
                }
            }
        }
    }
}
