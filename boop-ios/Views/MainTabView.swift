import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BoopRangingView()
                .tabItem { Label("Boop", systemImage: "hand.tap.fill") }
                .tag(0)

            ContactsView(onSwitchToBoop: { selectedTab = 0 })
                .tabItem { Label("Contacts", systemImage: "person.2") }
                .tag(1)

            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(2)
        }
    }
}

#Preview {
    MainTabView()
}
