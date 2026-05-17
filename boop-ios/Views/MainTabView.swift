import SwiftData
import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

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

            ContactsView(onSwitchToBoop: { selectedTab = 1 })
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
    }
}

#Preview {
    MainTabView()
}
