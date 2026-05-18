import SwiftData
import SwiftUI

@MainActor
final class DeepLinkState {
    static let shared = DeepLinkState()
    var pendingCameraInteractionID: UUID?
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var contactsPath = NavigationPath()

    @Query private var interactions: [BoopInteraction]

    private var hasHomeContent: Bool {
        interactions.contains(where: \.hasContent)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if hasHomeContent {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                    .tag(0)
            }

            BoopRangingView()
                .tabItem { Label("Boop", systemImage: "hand.tap.fill") }
                .tag(1)

            ContactsView(path: $contactsPath, onSwitchToBoop: { selectedTab = 1 })
                .tabItem { Label("Contacts", systemImage: "person.2") }
                .tag(2)

            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .onChange(of: hasHomeContent) { _, hasContent in
            if !hasContent && selectedTab == 0 {
                selectedTab = 1
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
