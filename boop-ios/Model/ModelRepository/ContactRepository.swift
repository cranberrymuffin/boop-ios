//
//  ContactRepository.swift
//  boop-ios
//
//  Singleton repository for Contact model CRUD operations.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ContactRepository {
    static let shared = ContactRepository()
    private var modelContext: ModelContext? { ModelContextProvider.shared.context }

    private init() {}

    // MARK: - Read

    /// Fetch all contacts stored locally.
    func fetchAllContacts() -> [Contact] {
        guard let modelContext else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []
    }

    /// Find an existing contact by its device UUID.
    func find(byUUID uuid: UUID) -> Contact? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Contact>(predicate: #Predicate { $0.uuid == uuid })
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Create / Update

    /// Find a contact by UUID and update its profile fields, or create a new one if not found.
    func findOrCreate(
        uuid: UUID,
        displayName: String,
        birthday: Date?,
        bio: String?,
        gradientColors: [Color]
    ) -> Contact? {
        guard let modelContext else { return nil }

        if let existing = find(byUUID: uuid) {
            existing.displayName = displayName
            existing.birthday = birthday
            existing.bio = bio
            existing.gradientColorsData = gradientColors.map { Contact.colorToString($0) }
            return existing
        }

        let contact = Contact(
            uuid: uuid,
            displayName: displayName,
            birthday: birthday,
            bio: bio,
            gradientColors: gradientColors
        )
        modelContext.insert(contact)
        save()
        return contact
    }

    // MARK: - Own Profile

    /// Returns the Contact record for this device's own profile, or nil if not set up yet.
    func getOwnProfile() -> Contact? {
        guard let uuid = SupabaseManager.shared.session?.user.id else { return nil }
        return find(byUUID: uuid)
    }

    /// Upsert the user's own profile Contact keyed by the Supabase user ID, then sync to Supabase.
    @discardableResult
    func saveOwnProfile(
        displayName: String,
        birthday: Date?,
        bio: String?,
        gradientColors: [Color],
        avatarData: Data?
    ) async -> Contact? {
        guard let uuid = SupabaseManager.shared.session?.user.id else { return nil }
        guard let contact = findOrCreate(uuid: uuid, displayName: displayName, birthday: birthday, bio: bio, gradientColors: gradientColors) else { return nil }
        contact.avatarData = avatarData
        save()
        await SupabaseManager.shared.syncProfile(contact)
        return contact
    }

    // MARK: - Delete

    /// Delete a contact (cascades to its interactions).
    func delete(_ contact: Contact) {
        modelContext?.delete(contact)
        save()
    }

    /// Delete all contacts and their interactions (used on sign-out).
    func deleteAll() {
        try? modelContext?.delete(model: Contact.self)
        save()
    }

    // MARK: - Save

    /// Persist pending changes to the store.
    private func save() {
        try? modelContext?.save()
    }
}
