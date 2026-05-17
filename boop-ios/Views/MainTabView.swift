import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

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
    }
}

#Preview {
    MainTabView()
}
