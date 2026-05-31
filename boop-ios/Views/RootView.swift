import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var boopManager: BoopManager
    @EnvironmentObject var supabaseManager: SupabaseManager

    var body: some View {
        Group {
            if supabaseManager.isSessionLoading {
                SplashView()
            } else if supabaseManager.session == nil {
                NavigationStack {
                    WelcomeView()
                }
            } else if !supabaseManager.hasProfile {
                MandatoryProfileSetupView()
            } else {
                MainTabView()
                    .onAppear { boopManager.start() }
            }
        }
    }
}

struct MandatoryProfileSetupView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager

    var body: some View {
        ProfileSetupView(
            buttonText: "Continue",
            requireAllFields: false,
            isEditMode: false,
            onSave: { _ in
                supabaseManager.hasProfile = true
            }
        )
    }
}
