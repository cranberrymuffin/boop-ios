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
.navigationDestination(for: BoopInteraction.self) { interaction in
                BoopInteractionDetailView(interaction: interaction)
            }
            .sheet(isPresented: $showBoopRanging) {
                BoopRangingView(isPresented: $showBoopRanging)
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
