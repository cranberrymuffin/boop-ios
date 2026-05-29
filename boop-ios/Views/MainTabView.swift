import SwiftData
import SwiftUI

@MainActor
final class DeepLinkState {
    static let shared = DeepLinkState()
    var pendingCameraInteractionID: UUID?
}

struct MainTabView: View {
    @EnvironmentObject var boopManager: BoopManager
    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var contactsPath = NavigationPath()

    @Query private var interactions: [BoopInteraction]
    @Query private var allContacts: [Contact]

    private var hasHomeContent: Bool {
        !interactions.isEmpty
    }

    private var isProfileSetUp: Bool {
        guard let uuidString = UserDefaults.standard.string(forKey: UserDefaultsKeys.localDeviceUUID),
              let uuid = UUID(uuidString: uuidString) else { return false }
        return allContacts.contains { $0.uuid == uuid }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if isProfileSetUp {
                if hasHomeContent {
                    HomeView(path: $homePath)
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(0)
                }

                BoopRangingView()
                    .tabItem { Label("Boop", systemImage: "hand.tap.fill") }
                    .tag(1)

                ContactsView(path: $contactsPath, onSwitchToBoop: { selectedTab = 1 })
                    .tabItem { Label("Contacts", systemImage: "person.2") }
                    .tag(2)
            }

            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .onChange(of: isProfileSetUp) { _, setUp in
            if !setUp {
                selectedTab = 3
            } else if selectedTab == 3 {
                selectedTab = 1
            }
        }
        .onChange(of: hasHomeContent) { _, hasContent in
            if !hasContent && selectedTab == 0 {
                selectedTab = 1
            }
        }
        .onChange(of: boopManager.latestBoopEvent?.id) { _, eventID in
            guard eventID != nil, let interaction = boopManager.latestBoopInteraction else { return }
            // Wait for the boop overlay animation to finish, then navigate to detail.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                homePath = NavigationPath()
                homePath.append(interaction)
                selectedTab = 0
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "boop", url.host == "timeline" else { return }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard let idString = segments.first,
              let uuid = UUID(uuidString: idString),
              let interaction = interactions.first(where: { $0.id == uuid }),
              let contact = interaction.contact else { return }
        if segments.count > 1 && segments[1] == "camera" {
            DeepLinkState.shared.pendingCameraInteractionID = uuid
        }
        contactsPath = NavigationPath()
        contactsPath.append(contact)
        contactsPath.append(interaction)
        selectedTab = 2
    }
}

#Preview {
    MainTabView()
}
