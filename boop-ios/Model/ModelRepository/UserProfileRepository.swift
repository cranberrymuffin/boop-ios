//
//  UserProfileRepository.swift
//  boop-ios
//
//  Singleton repository for UserProfile model CRUD operations.
//

import Foundation
import SwiftData

@MainActor
final class UserProfileRepository {
    static let shared = UserProfileRepository()
    private var modelContext: ModelContext?

    private init() {}

    func setModelContainer(_ container: ModelContainer) {
        self.modelContext = ModelContext(container)
    }

    // MARK: - Read

    /// Fetch the most recently created user profile, or nil if none exists.
    func getCurrent() -> UserProfile? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\UserProfile.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Create / Update

    /// Insert a new or updated profile and persist it.
    func save(_ profile: UserProfile) {
        guard let modelContext else { return }
        modelContext.insert(profile)
        try? modelContext.save()
    }
}
