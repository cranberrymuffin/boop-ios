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
    @State private var ownProfile: Contact? = nil
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
                    if let profile = ownProfile {
                        PersonDetailView(
                            displayName: profile.displayName,
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
            initialName: ownProfile?.displayName ?? "",
            initialBirthday: ownProfile?.birthday,
            initialBio: ownProfile?.bio ?? "",
            buttonText: "Save",
            requireAllFields: false,
            isEditMode: true,
            gradientColors: ownProfile?.gradientColors,
            initialAvatarData: ownProfile?.avatarData,
            onSave: { contact in
                ownProfile = contact
                profileState = .displayProfile
            }
        )
    }

    private func loadProfile() {
        profileState = .loadingProfile
        ownProfile = ContactRepository.shared.getOwnProfile()
        profileState = ownProfile != nil ? .displayProfile : .noProfile
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
        .modelContainer(for: Contact.self, inMemory: true)
}
