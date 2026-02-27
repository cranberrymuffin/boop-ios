import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isProfileLoaded: Bool? = nil
    @Binding var selectedTab: Int
    @Binding var selectedInteractionID: UUID?

    private func checkProfileExists() {
        Task {
            let profile = await DataStore.shared.getUserProfile()
            isProfileLoaded = (profile != nil)
        }
    }

    var body: some View {
        Group {
            if let isProfileLoaded = isProfileLoaded {
                if isProfileLoaded {
                    MainTabView(selectedTab: $selectedTab, selectedInteractionID: $selectedInteractionID)
                } else {
                    ProfileSetupView(onSave: { profile, _ in
                        Task {
                            modelContext.insert(profile)
                            await DataStore.shared.setUserProfile(profile)
                            await DataStore.shared.setProfileComplete(true)
                            
                            await MainActor.run {
                                self.isProfileLoaded = true
                            }
                        }
                    })
                }
            } else {
                // Loading indicator while checking profile
                ProgressView().onAppear(perform: checkProfileExists)
            }
        }.pageBackground()
    }
}

#Preview {
    RootView(selectedTab: .constant(0), selectedInteractionID: .constant(nil))
}
