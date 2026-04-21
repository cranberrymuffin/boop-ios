//
//  BoopInteractionRepository.swift
//  boop-ios
//
//  Singleton repository for BoopInteraction model CRUD operations.
//

import CoreLocation
import Foundation
import SwiftData

@MainActor
final class BoopInteractionRepository {
    static let shared = BoopInteractionRepository()
    private var modelContext: ModelContext?

    private init() {}

    func setModelContainer(_ container: ModelContainer) {
        self.modelContext = ModelContext(container)
    }

    // MARK: - Create

    /// Create a new interaction, insert it, and associate it with the given contact.
    func create(
        title: String,
        location: String,
        timestamp: Date,
        endTimestamp: Date? = nil,
        contact: Contact,
        pathCoordinates: [CLLocationCoordinate2D] = []
    ) -> BoopInteraction? {
        guard let modelContext else { return nil }

        let interaction = BoopInteraction(
            title: title,
            location: location,
            timestamp: timestamp,
            endTimestamp: endTimestamp,
            contact: contact,
            pathCoordinates: pathCoordinates
        )
        modelContext.insert(interaction)
        contact.interactions.append(interaction)
        save()
        return interaction
    }

    // MARK: - Read

    /// Check whether an interaction for this contact + display name already exists
    /// within ±`window` seconds of `timestamp`.
    func isDuplicate(
        contactUUID: UUID,
        displayName: String,
        timestamp: Date,
        window: TimeInterval
    ) -> Bool {
        guard let modelContext else { return false }

        let windowStart = timestamp.addingTimeInterval(-window)
        let windowEnd = timestamp.addingTimeInterval(window)
        let descriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {
            $0.timestamp >= windowStart && $0.timestamp <= windowEnd
        })
        let interactions = (try? modelContext.fetch(descriptor)) ?? []
        return interactions.contains { $0.contact?.uuid == contactUUID && $0.title == displayName }
    }

    /// Find the most recent interaction for a contact (by contact UUID).
    func findLatest(forContactUUID contactUUID: UUID) -> BoopInteraction? {
        guard let modelContext else { return nil }

        let descriptor = FetchDescriptor<BoopInteraction>(
            predicate: #Predicate { $0.contact?.uuid == contactUUID },
            sortBy: [SortDescriptor(\BoopInteraction.timestamp, order: .reverse)]
        )
        let interactions = (try? modelContext.fetch(descriptor)) ?? []
        return interactions.first
    }

    // MARK: - Update

    /// Enrich an existing interaction with session-end data.
    func enrichWithSessionData(
        _ interaction: BoopInteraction,
        endTimestamp: Date,
        pathCoordinates: [CLLocationCoordinate2D],
        location: String? = nil
    ) {
        interaction.endTimestamp = endTimestamp
        if !pathCoordinates.isEmpty {
            interaction.pathCoordinates = pathCoordinates
        }
        if let location, !location.isEmpty {
            interaction.location = location
        }
        save()
    }

    // MARK: - Save

    /// Persist pending changes to the store.
    private func save() {
        try? modelContext?.save()
    }
}
