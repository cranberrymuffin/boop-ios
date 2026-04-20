import SwiftUI
import SwiftData

struct ProfileView: View {
    
    enum ProfileState {
        case loadingProfile
        case editingProfile
        case noProfile
        case displayProfile
    }
    
    @Environment(\.modelContext) private var modelContext
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
        modelContext.insert(profile)
        try? modelContext.save()
        profileState = ProfileState.displayProfile
    }
    
    private func loadProfile() {
        profileState = ProfileState.loadingProfile
        let fetchDescriptor = FetchDescriptor<UserProfile>(
                        sortBy: [SortDescriptor(\UserProfile.createdAt, order: .reverse)]
                    )
        let userProfiles = (try? modelContext.fetch(fetchDescriptor)) ?? []
        if userProfiles.count > 0 {
            userProfile = userProfiles.first
        }
        profileState = userProfile != nil ?
            ProfileState.displayProfile : ProfileState.noProfile
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
