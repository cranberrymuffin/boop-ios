import SwiftUI

/// Root tab view for authenticated users
struct MainTabView: View {
    @Binding var selectedTab: Int
    @Binding var selectedInteractionID: UUID?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            BoopTimelineView(selectedInteractionID: $selectedInteractionID)
                .tabItem {
                    Label("Timeline", systemImage: "clock.fill")
                }
                .tag(0)

            BoopRangingView()
                .tabItem {
                    Label("Boop", systemImage: "hand.tap.fill")
                }

            ContactsView()
                .tabItem {
                    Label("Contacts", systemImage: "person.2")
                }
                .tag(1)

            ProfileView()
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
            }
            .tag(2)
        }
    }
}

#Preview {
    MainTabView(selectedTab: .constant(0), selectedInteractionID: .constant(nil))
}
