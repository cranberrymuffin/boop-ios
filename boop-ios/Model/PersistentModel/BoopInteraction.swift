//
//  BoopInteraction.swift
//  boop-ios
//
//  Model for Boop interaction data displayed in cards
//


import CoreLocation
import Foundation
import SwiftData

// Codable helper for storing CLLocationCoordinate2D in SwiftData
struct PathCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

@Model
final class BoopInteraction {
    var id: UUID
    var title: String
    var location: String
    var timestamp: Date
    var endTimestamp: Date? // optional end time for interactions that span a duration
    var imageData: [Data] // Use Data for images
    /// JSON-encoded array of PathCoordinate representing the path traveled at boop time.
    var pathCoordinatesData: Data?

    // Relationship to Contact
    var contact: Contact?

    init(title: String, location: String, timestamp: Date, endTimestamp: Date? = Date().addingTimeInterval(2 * 60 * 60), imageData: [Data] = [], contact: Contact? = nil, pathCoordinates: [CLLocationCoordinate2D] = []) {
        self.id = UUID()
        self.title = title
        self.location = location
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.imageData = imageData
        self.contact = contact
        self.pathCoordinatesData = Self.encode(pathCoordinates)
    }

    var thumbnailCount: Int {
        imageData.count
    }

    /// Decoded path coordinates for map display.
    var pathCoordinates: [CLLocationCoordinate2D] {
        get { Self.decode(pathCoordinatesData) }
        set { pathCoordinatesData = Self.encode(newValue) }
    }

    // MARK: - Encode/Decode Helpers

    private static func encode(_ coordinates: [CLLocationCoordinate2D]) -> Data? {
        guard !coordinates.isEmpty else { return nil }
        let portable = coordinates.map { PathCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        return try? JSONEncoder().encode(portable)
    }

    private static func decode(_ data: Data?) -> [CLLocationCoordinate2D] {
        guard let data else { return [] }
        guard let portable = try? JSONDecoder().decode([PathCoordinate].self, from: data) else { return [] }
        return portable.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
