//
//  AddManualBoopView.swift
//  boop-ios
//
//  Form sheet for manually adding a boop entry to the timeline
//

import SwiftUI
import SwiftData

struct AddManualBoopView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var locationManager: LocationManager
    @Query private var contacts: [Contact]

    @State private var selectedContact: Contact?
    @State private var searchText: String = ""
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = Date().addingTimeInterval(2 * 60 * 60)

    private var isUsingNewName: Bool {
        selectedContact == nil && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        selectedContact != nil || isUsingNewName
    }

    private var filteredContacts: [Contact] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return contacts.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // MARK: - Contact (typeahead with create fallback)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Contact")
                            .subtitleStyle()
                            .padding(.horizontal, Spacing.lg)

                        TextField("Search or enter a name", text: $searchText)
                            .font(.body)
                            .foregroundColor(.textPrimary)
                            .padding(Spacing.md)
                            .background(Color.formBackgroundInactive)
                            .cornerRadius(CornerRadius.md)
                            .onChange(of: searchText) { _, newValue in
                                if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                    selectedContact = nil
                                }
                            }
                            .overlay(
                                HStack {
                                    Spacer()
                                    if !searchText.isEmpty {
                                        Button(action: { searchText = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.textMuted)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.trailing, Spacing.md)
                                    }
                                }
                            )
                            .padding(.horizontal, Spacing.lg)

                        // Suggestions / existing contacts
                        LazyVStack(spacing: Spacing.sm) {
                            if filteredContacts.isEmpty {
                                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Button {
                                        // keep selectedContact nil; the entered text will be used as new contact on save
                                        selectedContact = nil
                                    } label: {
                                        HStack {
                                            Text("Create new: \(searchText.trimmingCharacters(in: .whitespaces))")
                                                .font(.body)
                                                .foregroundColor(.textPrimary)
                                            Spacer()
                                            if selectedContact == nil {
                                                Image(systemName: "plus")
                                                    .foregroundColor(.accentPrimary)
                                            }
                                        }
                                        .padding(Spacing.md)
                                        .background(Color.backgroundSecondary)
                                        .cornerRadius(CornerRadius.md)
                                    }
                                    .padding(.horizontal, Spacing.lg)
                                } else {
                                    // No query and no contacts match (rare) — show empty state
                                    if contacts.isEmpty {
                                        Text("No contacts yet — enter a name to create one")
                                            .font(.body)
                                            .foregroundColor(.textMuted)
                                            .padding(.horizontal, Spacing.lg)
                                    }
                                }
                            } else {
                                ForEach(filteredContacts) { contact in
                                    Button {
                                        selectedContact = contact
                                        searchText = contact.displayName
                                    } label: {
                                        HStack {
                                            Text(contact.displayName)
                                                .font(.body)
                                                .foregroundColor(.textPrimary)
                                            Spacer()
                                            if selectedContact?.uuid == contact.uuid {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.accentPrimary)
                                            }
                                        }
                                        .padding(Spacing.md)
                                        .background(
                                            selectedContact?.uuid == contact.uuid
                                                ? Color.accentSecondary
                                                : Color.backgroundSecondary
                                        )
                                        .cornerRadius(CornerRadius.md)
                                    }
                                    .padding(.horizontal, Spacing.lg)
                                }
                            }
                        }
                    }

                    // MARK: - Start & End Date/Time Pickers
                    DatePickerField(
                        title: "Start",
                        placeholder: "When did this boop start?",
                        showTimePicker: true,
                        selectedDate: $startDate
                    )
                    .padding(.horizontal, Spacing.lg)

                    DatePickerField(
                        title: "End",
                        placeholder: "When did this boop end?",
                        showTimePicker: true,
                        selectedDate: $endDate
                    )
                    .padding(.horizontal, Spacing.lg)

                    // MARK: - Add Button
                    Button(action: saveBoop) {
                        Text("Add")
                            .primaryButtonStyle()
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1.0 : 0.5)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
                }
                .padding(.top, Spacing.md)
            }
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add Boop")
                        .heading1Style()
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.accentPrimary)
                }
            }
        }
    }

    private func saveBoop() {
        let contact: Contact
        if let existing = selectedContact {
            contact = existing
        } else {
            let trimmedName = searchText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }
            guard let created = ContactRepository.shared.findOrCreate(
                uuid: UUID(), displayName: trimmedName, birthday: nil, bio: nil, gradientColors: []
            ) else { return }
            contact = created
        }

        _ = BoopInteractionRepository.shared.create(
            title: contact.displayName,
            location: locationManager.currentLocationName,
            timestamp: startDate ?? Date(),
            endTimestamp: endDate,
            contact: contact,
            pathCoordinates: locationManager.snapshotPath()
        )

        dismiss()
    }
}

#Preview {
    AddManualBoopView()
        .modelContainer(for: [Contact.self, BoopInteraction.self], inMemory: true)
}
