import SwiftUI
import SwiftData

struct ContactDetailView: View {
    let contact: Contact

    var body: some View {
        PersonDetailView(
            displayName: contact.displayName,
            birthday: contact.birthday,
            bio: contact.bio,
            avatarData: contact.avatarData,
            gradientColors: contact.gradientColors,
            boopCount: contact.interactions.count,
            isOwnProfile: false,
            historyRoute: ContactHistoryRoute(contact: contact)
        )
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BoopHistoryView: View {
    let interactions: [BoopInteraction]
    let title: String

    var body: some View {
        ScrollView {
            BoopInteractionTimelineBody(interactions: interactions)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
    }
}

#Preview {
    let contact = Contact(
        uuid: UUID(),
        displayName: "Jane Doe",
        birthday: Date(),
        bio: "Coffee enthusiast and part-time adventurer"
    )

    ContactDetailView(contact: contact)
        .modelContainer(for: Contact.self, inMemory: true)
}
