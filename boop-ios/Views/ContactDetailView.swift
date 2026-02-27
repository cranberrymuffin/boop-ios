//
//  ContactDetailView.swift
//  boop-ios
//

import SwiftUI
import SwiftData

/// Lightweight Hashable route used to push BoopHistoryView
/// without relying on an isPresented binding that stays true
/// while navigating deeper in the stack.
struct BoopHistoryRoute: Hashable {
    let contact: Contact
}

struct ContactDetailView: View {
    let contact: Contact

    var body: some View {
        ZStack {
            // Use contact's gradient colors as background
            AnimatedMeshGradient(
                colors: contact.gradientColors,
                animationStyle: .horizontalWave,
                duration: 3.0
            )
            .ignoresSafeArea()

            Form {
                Section {
                    ProfileDisplayCard(
                        avatarImage: contact.avatarData.flatMap { UIImage(data: $0) }.map { Image(uiImage: $0) },
                        displayName: contact.displayName,
                        birthday: contact.birthday,
                        bio: contact.bio
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // Interaction History Section
                Section {
                    NavigationLink(value: BoopHistoryRoute(contact: contact)) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.accentPrimary)
                            Text("Boop History")
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(contact.interactions.count)")
                                .subtitleStyle()
                                .foregroundColor(.textMuted)
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BoopHistoryView: View {
    let contact: Contact

    var body: some View {
        ScrollView {
            BoopInteractionTimelineBody(
                interactions: contact.interactions.sorted(by: { $0.timestamp > $1.timestamp })
            )
        }
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
    }
}

#Preview {
    let contact = Contact(
        uuid: UUID(),
        displayName: "Jane Doe",
        avatarData: nil,
        birthday: Date(),
        bio: "Coffee enthusiast and part-time adventurer"
    )
    
    ContactDetailView(contact: contact)
        .modelContainer(for: Contact.self, inMemory: true)
}
