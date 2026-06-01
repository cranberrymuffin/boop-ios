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

struct PhotoMeta: Codable {
    var storagePath: String?       // nil = pending upload
    let uploadedByUserID: String   // Supabase auth UUID string
}

@Model
final class BoopInteraction {
    var id: UUID
    var location: String
    var timestamp: Date
    var endTimestamp: Date? // optional end time for interactions that span a duration
    var imageData: [Data]
    /// JSON-encoded array of PhotoMeta, parallel to imageData — tracks upload state per photo.
    var photoMetadataData: Data?
    /// JSON-encoded array of PathCoordinate representing the path traveled at boop time.
    var pathCoordinatesData: Data?
    var notes: String?
    var boopCount: Int = 1
    var supabaseInteractionID: UUID?

    // Relationship to Contact
    var contact: Contact?

    var displayTitle: String { contact?.displayName ?? "Unknown" }

    init(location: String, timestamp: Date, endTimestamp: Date? = Date().addingTimeInterval(2 * 60 * 60), imageData: [Data] = [], notes: String? = nil, contact: Contact? = nil, pathCoordinates: [CLLocationCoordinate2D] = [], boopCount: Int = 1) {
        self.id = UUID()
        self.location = location
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.imageData = imageData
        self.notes = notes
        self.contact = contact
        self.pathCoordinatesData = Self.encode(pathCoordinates)
        self.boopCount = boopCount
    }

    var hasContent: Bool { !imageData.isEmpty || !(notes ?? "").isEmpty || pathCoordinatesData != nil }

    var thumbnailCount: Int {
        contact != nil ? 1 : 0
    }

    var photoMetadata: [PhotoMeta] {
        get { photoMetadataData.flatMap { try? JSONDecoder().decode([PhotoMeta].self, from: $0) } ?? [] }
        set { photoMetadataData = try? JSONEncoder().encode(newValue) }
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
