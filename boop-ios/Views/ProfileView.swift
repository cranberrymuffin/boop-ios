import SwiftUI
import SwiftData

struct ProfileView: View {

    enum ProfileState {
        case loadingProfile
        case editingProfile
        case noProfile
        case displayProfile
    }

    @State private var userProfile: UserProfile? = nil
    @State private var profileState = ProfileState.loadingProfile

    var body: some View {
        NavigationView {
            Group {
                switch profileState {
                case .loadingProfile:
                    loadingView
                case .editingProfile:
                    editModeView
                case .noProfile:
                    editModeView
                case .displayProfile:
                    displayModeView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if profileState != ProfileState.editingProfile &&
                    profileState != ProfileState.loadingProfile {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") {
                            profileState = ProfileState.editingProfile
                        }
                    }
                }
            }
            .onAppear(perform: loadProfile)
        }
        .pageBackground()
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading profile...")
                .subtitleStyle()
        }
    }
    
    private var displayModeView: some View {
        NavigationView {
            if userProfile != nil {
                readOnlyProfileView
            } else {
                noProfileFoundView
            }
        }
    }
    
    private var readOnlyProfileView: some View {
        ZStack {
            AnimatedMeshGradient(
                colors: userProfile!.gradientColors,
                animationStyle: .horizontalWave,
                duration: 3.0
            )
            .ignoresSafeArea()
            
            Form {
                Section {
                    ProfileDisplayCard(
                        displayName: userProfile!.name,
                        birthday: userProfile!.birthday,
                        bio: userProfile!.bio,
                        avatarData: userProfile!.avatarData
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .scrollContentBackground(.hidden)
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

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
