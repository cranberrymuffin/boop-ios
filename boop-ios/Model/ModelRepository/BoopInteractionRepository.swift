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

    // MARK: - Migration

    /// One-time migration: merge interactions for the same contact on the same calendar day
    /// into a single interaction (keeps earliest timestamp, latest endTimestamp, merged images).
    func mergeSessionDuplicates() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<BoopInteraction>(
            sortBy: [SortDescriptor(\BoopInteraction.timestamp)]
        )
        guard let all = try? modelContext.fetch(descriptor) else { return }

        // Group by contact UUID (skip interactions without a contact)
        var byContact: [UUID: [BoopInteraction]] = [:]
        for interaction in all {
            guard let uuid = interaction.contact?.uuid else { continue }
            byContact[uuid, default: []].append(interaction)
        }

        let calendar = Calendar.current

        for (_, interactions) in byContact {
            let sorted = interactions.sorted { $0.timestamp < $1.timestamp }

            // Group consecutive interactions that share the same calendar day
            var dayGroups: [[BoopInteraction]] = []
            for interaction in sorted {
                if let last = dayGroups.last?.first,
                   calendar.isDate(interaction.timestamp, inSameDayAs: last.timestamp) {
                    dayGroups[dayGroups.count - 1].append(interaction)
                } else {
                    dayGroups.append([interaction])
                }
            }

            for group in dayGroups where group.count > 1 {
                let primary = group[0]
                let duplicates = group.dropFirst()

                // Keep the latest endTimestamp
                if let latestEnd = duplicates.compactMap(\.endTimestamp).max() {
                    primary.endTimestamp = max(primary.endTimestamp ?? latestEnd, latestEnd)
                }

                // Merge image data (avoid exact duplicates)
                for dup in duplicates {
                    primary.imageData.append(contentsOf: dup.imageData)
                }

                // Keep the longest path
                if let longestDup = duplicates.max(by: {
                    ($0.pathCoordinatesData?.count ?? 0) < ($1.pathCoordinatesData?.count ?? 0)
                }), (longestDup.pathCoordinatesData?.count ?? 0) > (primary.pathCoordinatesData?.count ?? 0) {
                    primary.pathCoordinatesData = longestDup.pathCoordinatesData
                }

                // Delete duplicates
                for dup in duplicates {
                    dup.contact?.interactions.removeAll { $0.id == dup.id }
                    modelContext.delete(dup)
                }
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
