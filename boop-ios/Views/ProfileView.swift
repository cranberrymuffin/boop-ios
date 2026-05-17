import SwiftUI
import SwiftData

struct ProfileView: View {

    enum ProfileState {
        case loadingProfile
        case editingProfile
        case noProfile
        case displayProfile
    }

    @State private var path = NavigationPath()
    @Query private var allInteractions: [BoopInteraction]
    @State private var userProfile: UserProfile? = nil
    @State private var profileState = ProfileState.loadingProfile

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch profileState {
                case .loadingProfile:
                    loadingView
                case .editingProfile:
                    editModeView
                case .noProfile:
                    editModeView
                case .displayProfile:
                    if let profile = userProfile {
                        PersonDetailView(
                            displayName: profile.name,
                            birthday: profile.birthday,
                            bio: profile.bio,
                            avatarData: profile.avatarData,
                            gradientColors: profile.gradientColors,
                            boopCount: allInteractions.count,
                            isOwnProfile: true,
                            onEdit: { profileState = .editingProfile },
                            historyRoute: ProfileHistoryRoute()
                        )
                    } else {
                        noProfileFoundView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ProfileHistoryRoute.self) { _ in
                AllBoopsHistoryView()
            }
            .navigationDestination(for: BoopInteraction.self) { interaction in
                InteractionDetailView(interaction: interaction)
            }
            .onAppear(perform: loadProfile)
        }
        .pageBackground()
        .onAppear { path = NavigationPath() }
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading profile...")
                .subtitleStyle()
        }
    }

    private var noProfileFoundView: some View {
        ZStack {
            Spacer()
            Text("No Profile Found")
            Spacer()
        }
    }

    private var editModeView: some View {
        ProfileSetupView(
            initialName: userProfile?.name ?? "",
            initialBirthday: userProfile?.birthday,
            initialBio: userProfile?.bio ?? "",
            buttonText: "Save",
            requireAllFields: false,
            isEditMode: true,
            gradientColors: userProfile?.gradientColors,
            initialAvatarData: userProfile?.avatarData,
            onSave: { profile in
                saveProfile(profile: profile)
                loadProfile()
            }
        )
    }

    private func saveProfile(profile: UserProfile) {
        UserProfileRepository.shared.save(profile)
        profileState = .displayProfile
    }

    private func loadProfile() {
        profileState = .loadingProfile
        userProfile = UserProfileRepository.shared.getCurrent()
        profileState = userProfile != nil ? .displayProfile : .noProfile
    }
}

struct AllBoopsHistoryView: View {
    @Query(sort: \BoopInteraction.timestamp, order: .reverse)
    private var allInteractions: [BoopInteraction]

    var body: some View {
        BoopHistoryView(interactions: allInteractions, title: "Boop History")
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
