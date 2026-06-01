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
    private var modelContext: ModelContext? { ModelContextProvider.shared.context }

    private init() {}

    // MARK: - Create

    /// Create a new interaction, insert it, and associate it with the given contact.
    func create(
        location: String,
        timestamp: Date,
        endTimestamp: Date? = nil,
        contact: Contact,
        pathCoordinates: [CLLocationCoordinate2D] = []
    ) -> BoopInteraction? {
        guard let modelContext else { return nil }

        let interaction = BoopInteraction(
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
    func isDuplicate(contactUUID: UUID, timestamp: Date, window: TimeInterval) -> Bool {
        guard let modelContext else { return false }

        let windowStart = timestamp.addingTimeInterval(-window)
        let windowEnd = timestamp.addingTimeInterval(window)
        let descriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {
            $0.timestamp >= windowStart && $0.timestamp <= windowEnd
        })
        let interactions = (try? modelContext.fetch(descriptor)) ?? []
        return interactions.contains { $0.contact?.uuid == contactUUID }
    }

    /// Find the most recent interaction for a contact created on the current calendar day.
    func findToday(forContactUUID contactUUID: UUID) -> BoopInteraction? {
        guard let modelContext else { return nil }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }

        let descriptor = FetchDescriptor<BoopInteraction>(
            predicate: #Predicate { $0.timestamp >= startOfDay && $0.timestamp < endOfDay },
            sortBy: [SortDescriptor(\BoopInteraction.timestamp, order: .reverse)]
        )
        let interactions = (try? modelContext.fetch(descriptor)) ?? []
        return interactions.first { $0.contact?.uuid == contactUUID }
    }

    func fetchAll() -> [BoopInteraction] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<BoopInteraction>())) ?? []
    }

    /// Find an interaction by its Supabase interaction ID.
    func find(bySupabaseID id: UUID) -> BoopInteraction? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {
            $0.supabaseInteractionID == id
        })
        return (try? modelContext.fetch(descriptor))?.first
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

    /// Sets supabaseInteractionID on the local interaction matching contactUUID + timestamp if it's not already set.
    func backfillSupabaseID(_ remoteID: UUID, contactUUID: UUID, near timestamp: Date, window: TimeInterval) {
        guard let modelContext else { return }
        let windowStart = timestamp.addingTimeInterval(-window)
        let windowEnd = timestamp.addingTimeInterval(window)
        let descriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {
            $0.timestamp >= windowStart && $0.timestamp <= windowEnd
        })
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        guard let local = matches.first(where: { $0.contact?.uuid == contactUUID && $0.supabaseInteractionID == nil }) else { return }
        local.supabaseInteractionID = remoteID
        save()
    }

    /// Updates the boopCount on the local interaction matching contactUUID + timestamp to at least `count`.
    func updateBoopCount(_ count: Int, contactUUID: UUID, near timestamp: Date, window: TimeInterval) {
        guard let modelContext else { return }
        let windowStart = timestamp.addingTimeInterval(-window)
        let windowEnd = timestamp.addingTimeInterval(window)
        let descriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {
            $0.timestamp >= windowStart && $0.timestamp <= windowEnd
        })
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        guard let local = matches.first(where: { $0.contact?.uuid == contactUUID }) else { return }
        local.boopCount = max(local.boopCount, count)
        save()
    }

    /// Increment the boop count on an existing interaction and save.
    func incrementBoopCount(_ interaction: BoopInteraction) {
        interaction.boopCount += 1
        save()
    }

    /// Enrich an existing interaction with session-end data.
    func enrichWithSessionData(
        _ interaction: BoopInteraction,
        endTimestamp: Date,
        pathCoordinates: [CLLocationCoordinate2D],
        location: String? = nil
    ) {
        interaction.endTimestamp = endTimestamp
        if !pathCoordinates.isEmpty {
            interaction.pathCoordinates = interaction.pathCoordinates + pathCoordinates
        }
        if let location, !location.isEmpty {
            if interaction.location.isEmpty {
                interaction.location = location
            } else if !interaction.location.hasSuffix(location) {
                interaction.location += " → \(location)"
            }
        }
        save()
    }

    // MARK: - Save

    /// Persist pending changes to the store.
    private func save() {
        try? modelContext?.save()
    }
}
