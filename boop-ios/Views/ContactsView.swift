//
//  ContactsView.swift
//  boop-ios
//
//  Created by Anu Lal on 11/26/25.
//

import SwiftUI
import SwiftData

struct ContactsView: View {
    @Query private var contacts: [Contact]
    @State private var showBoopRanging = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack {
                    ForEach(contacts) { contact in
                        NavigationLink(value: contact) {
                            buildContactCard(contact: contact)
                        }
                    }
                    .onDelete(perform: deleteContact)
                }
                .scrollContentBackground(Visibility.hidden)
            }
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Contacts")
                        .heading1Style()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showBoopRanging = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: IconSize.standard, weight: .semibold))
                            .foregroundColor(.accentPrimary)
                    }
                }
            }
            .navigationDestination(for: Contact.self) { contact in
                ContactDetailView(contact: contact)
            }
            .navigationDestination(for: BoopHistoryRoute.self) { route in
                BoopHistoryView(contact: route.contact)
            }
            .navigationDestination(for: BoopInteraction.self) { interaction in
                BoopInteractionDetailView(interaction: interaction)
            }
            .sheet(isPresented: $showBoopRanging) {
                BoopRangingView(isPresented: $showBoopRanging)
            }

        }
    }

    private func deleteContact(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                ContactRepository.shared.delete(contacts[index])
            }
        }
    }
}

@ViewBuilder
func buildContactCard(contact: Contact) -> some View {
    ContactInteractionCard(contact: contact) {
        // Optionally handle tap
    }
}

#Preview {
    ContactsView()
        .modelContainer(for: Contact.self, inMemory: true)
}
