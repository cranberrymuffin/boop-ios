//
//  AddManualBoopView.swift
//  boop-ios
//
//  Form sheet for manually adding a boop entry to the timeline
//

import SwiftUI
import SwiftData

struct AddManualBoopView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var contacts: [Contact]

    @State private var selectedContact: Contact?
    @State private var newContactName: String = ""
    @State private var selectedDate: Date = Date()

    private var isUsingNewName: Bool {
        selectedContact == nil && !newContactName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        selectedContact != nil || isUsingNewName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // MARK: - New Contact Name
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Or enter a new name")
                            .subtitleStyle()
                            .padding(.horizontal, Spacing.lg)

                        TextField("New contact name", text: $newContactName)
                            .font(.body)
                            .foregroundColor(.textPrimary)
                            .padding(Spacing.md)
                            .background(Color.formBackgroundInactive)
                            .cornerRadius(CornerRadius.md)
                            .padding(.horizontal, Spacing.lg)
                            .onChange(of: newContactName) { _, newValue in
                                if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                    selectedContact = nil
                                }
                            }
                    }

                    // MARK: - Existing Contacts
                    if !contacts.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Select a contact")
                                .subtitleStyle()
                                .padding(.horizontal, Spacing.lg)

                            LazyVStack(spacing: Spacing.sm) {
                                ForEach(contacts) { contact in
                                    Button {
                                        selectedContact = contact
                                        newContactName = ""
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

                    // MARK: - Date Picker
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Date & Time")
                            .subtitleStyle()
                            .padding(.horizontal, Spacing.lg)

                        DatePicker(
                            "Date",
                            selection: $selectedDate,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .tint(.accentPrimary)
                        .padding(Spacing.md)
                        .cardStyle()
                        .padding(.horizontal, Spacing.lg)
                    }

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
            let trimmedName = newContactName.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { return }
            contact = Contact(uuid: UUID(), displayName: trimmedName)
            modelContext.insert(contact)
        }

        let interaction = BoopInteraction(
            title: contact.displayName,
            location: "",
            timestamp: selectedDate,
            contact: contact
        )
        modelContext.insert(interaction)
        contact.interactions.append(interaction)

        dismiss()
    }
}

#Preview {
    AddManualBoopView()
        .modelContainer(for: [Contact.self, BoopInteraction.self], inMemory: true)
}
