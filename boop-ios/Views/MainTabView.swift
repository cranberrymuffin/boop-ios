import SwiftUI

/// Root tab view for authenticated users
struct MainTabView: View {
    var body: some View {
        TabView {
            BoopRangingView()
                .tabItem {
                    Label("Boop", systemImage: "hand.tap.fill")
                }

            ContactsView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2")
                }

            ProfileView()
                .tabItem {
                    Label("You", systemImage: "person.crop.circle")
                }
        }
    }
}

#Preview {
    MainTabView()
}
