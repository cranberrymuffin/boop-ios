import SwiftUI
import SwiftData

struct ContactsView: View {
    @Query private var contacts: [Contact]
    @Binding var path: NavigationPath
    let onSwitchToBoop: () -> Void

    @EnvironmentObject private var supabaseManager: SupabaseManager

    private var localUUID: UUID? {
        supabaseManager.session?.user.id
    }

    private var visibleContacts: [Contact] {
        guard let localUUID else { return contacts }
        return contacts.filter { $0.uuid != localUUID }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack {
                    ForEach(visibleContacts) { contact in
                        NavigationLink(value: contact) {
                            BoopListRow(
                                avatarImages: [contact.avatarData],
                                title: contact.displayName,
                                staticLabel: contact.interactions.isEmpty
                                    ? "No boops yet"
                                    : "\(contact.interactions.count) boop\(contact.interactions.count == 1 ? "" : "s")",
                                timestamp: contact.interactions.last?.timestamp
                            )
                        }
                    }
                }
            }
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Contacts")
                        .heading1Style()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onSwitchToBoop) {
                        Image(systemName: "plus")
                            .font(.system(size: IconSize.standard, weight: .semibold))
                            .foregroundColor(.accentPrimary)
                    }
                }
            }
            .navigationDestination(for: Contact.self) { contact in
                ContactDetailView(contact: contact)
            }
            .navigationDestination(for: ContactHistoryRoute.self) { route in
                BoopHistoryView(
                    interactions: route.contact.interactions.sorted { $0.timestamp > $1.timestamp },
                    title: route.contact.displayName
                )
            }
            .navigationDestination(for: BoopInteraction.self) { interaction in
                InteractionDetailView(interaction: interaction)
            }
        }
    }
}

#Preview {
    ContactsView(path: .constant(NavigationPath()), onSwitchToBoop: {})
        .modelContainer(for: Contact.self, inMemory: true)
}
