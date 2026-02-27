//
//  BoopRangingView.swift
//  boop-ios
//
//  Handles Bluetooth ranging/scanning for new boops
//

import SwiftUI
import SwiftData

struct BoopRangingView: View {
    var isPresented: Binding<Bool>?
    @EnvironmentObject var boopManager: BoopManager
    @Environment(\.modelContext) private var modelContext
    @Query private var contacts: [Contact]
    @Query(sort: \BoopInteraction.timestamp, order: .reverse)
    private var allInteractions: [BoopInteraction]
    @State private var showBoop = false
    @State private var currentBoopDisplayName: String = ""

    private let animationDuration: TimeInterval = 2
    private let duplicateWindow: TimeInterval = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.accentPrimary)

                Text("Tap to boop")
                    .subtitleStyle()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground()
            .ignoresSafeArea(edges: .horizontal)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Boop")
                        .heading1Style()
                }
                if isPresented != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            isPresented?.wrappedValue = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: IconSize.standard, weight: .semibold))
                                .foregroundColor(.accentPrimary)
                        }
                    }
                }
            }
            .overlay {
                if showBoop {
                    ZStack {
                        Color.backgroundPrimary.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: Spacing.xl) {
                            Text("Boop!")
                                .heading1Style()
                            Text(currentBoopDisplayName)
                                .heading2Style()
                        }
                        .cardStyle()
                        .padding(Spacing.lg)
                    }
                }
            }
            .animation(.easeInOut(duration: animationDuration), value: showBoop)
            .onChange(of: boopManager.latestBoopEvent) { _, newValue in
                // Only handle if event is new
                guard let event = newValue, !showBoop else { return }
                handleNewBoop(event: event)
            }
        }
        .onAppear { boopManager.start() }
        .onDisappear { boopManager.stop() }
    }

    private func handleNewBoop(event: BoopEvent) {
        let boop = event.boop

        // Store display name for modal
        currentBoopDisplayName = boop.displayName

        // Use senderUUID from boop
        let contactUUID = boop.senderUUID

        // Find or create contact
        let contact: Contact
        if let existingContact = contacts.first(where: { $0.uuid == contactUUID }) {
            contact = existingContact
            // Update contact with latest profile data
            contact.displayName = boop.displayName
            contact.birthday = boop.birthday
            contact.bio = boop.bio
            contact.gradientColorsData = boop.gradientColors.map { Contact.colorToString($0) }
        } else {
            // Create new contact with profile data
            contact = Contact(
                uuid: contactUUID,
                displayName: boop.displayName,
                avatarData: nil,
                birthday: boop.birthday,
                bio: boop.bio,
                gradientColors: boop.gradientColors
            )
            modelContext.insert(contact)
        }

        guard !isDuplicateInteraction(for: contactUUID, displayName: boop.displayName, timestamp: event.timestamp) else {
            print("⏭️ BoopRangingView: Skipping duplicate interaction for \(contactUUID.uuidString.prefix(8))")
            showBoop = true
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                showBoop = false
                isPresented?.wrappedValue = false
            }
            return
        }

        // Create interaction with contact relationship
        let newInteraction = BoopInteraction(
            title: boop.displayName,
            location: "temp - todo",
            timestamp: event.timestamp,
            contact: contact  // Set relationship
        )
        modelContext.insert(newInteraction)  // Insert as top-level entity
        contact.interactions.append(newInteraction)  // Also add to contact's array

        LiveActivityManager.shared.startBoopLiveActivity(
            contactName: boop.displayName,
            contactID: contactUUID,
            interactionID: newInteraction.id,
            gradientColors: boop.gradientColors.map { Contact.colorToString($0) }
        )

        // Show modal
        showBoop = true

        // Hide modal after animation duration (dismiss sheet if presented as one)
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            showBoop = false
            isPresented?.wrappedValue = false
        }
    }

    private func isDuplicateInteraction(for contactUUID: UUID, displayName: String, timestamp: Date) -> Bool {
        allInteractions.contains { interaction in
            guard interaction.contact?.uuid == contactUUID else { return false }
            guard interaction.title == displayName else { return false }
            return abs(interaction.timestamp.timeIntervalSince(timestamp)) <= duplicateWindow
        }
    }
}


