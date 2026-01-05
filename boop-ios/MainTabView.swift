import SwiftUI

/// Root tab view for authenticated users
struct MainTabView: View {
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        TabView {
            BoopView()
                .tabItem {
                    Label("Timeline", systemImage: "clock.fill")
                }

            ProfileSetupView(
                authViewModel: nil,
                isSetupMode: false,
                onProfileUpdated: {
                    refreshTrigger = UUID()
                }
            )
            .id(refreshTrigger)
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
            }
        }
    }
}

#Preview {
    MainTabView()
}
