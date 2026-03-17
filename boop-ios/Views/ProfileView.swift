import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var birthday: Date?
    @State private var bio = ""
    @State private var isLoading = false
    @State private var isEditing = false

    @State private var gradientColors: [Color] = []
    @State private var avatarData: Data?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading profile...")
                            .subtitleStyle()
                    }
                } else {
                    if isEditing {
                        editModeView
                    } else {
                        displayModeView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEditing && !isLoading {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
            .task {
                await loadProfile()
            }
        }
        .pageBackground()
    }
    
    private var displayModeView: some View {
        NavigationView {
            ZStack {
                AnimatedMeshGradient(
                    colors: gradientColors,
                    animationStyle: .horizontalWave,
                    duration: 3.0
                )
                .ignoresSafeArea()
                
                Form {
                    Section {
                        ProfileDisplayCard(
                            displayName: name,
                            birthday: birthday,
                            bio: bio.isEmpty ? nil : bio,
                            avatarData: avatarData
                        )
                    }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
    
    private var editModeView: some View {
        ProfileSetupView(
            initialName: name,
            initialBirthday: birthday,
            initialBio: bio,
            buttonText: "Save",
            requireAllFields: false,
            isEditMode: true,
            gradientColors: gradientColors,
            initialAvatarData: avatarData,
            onSave: { profile in
                saveProfile(profile: profile)
            }
        )
    }
    
    private func saveProfile(profile: UserProfile) {
        isLoading = true

        Task {
            await DataStore.shared.setUserProfile(profile)
            modelContext.insert(profile)

            await MainActor.run {
                // Update local state
                self.name = profile.name
                self.birthday = profile.birthday
                self.bio = profile.bio ?? ""
                self.gradientColors = profile.gradientColors
                self.avatarData = profile.avatarData
                
                self.isLoading = false
                self.isEditing = false
            }
        }
    }

    private func loadProfile() async {
        await MainActor.run { isLoading = true }

        if let profileData = await DataStore.shared.getUserProfile() {
            print("✅ [Profile] Local profile loaded")

            await MainActor.run {
                self.name = profileData.name
                self.birthday = profileData.birthday
                self.bio = profileData.bio ?? ""
                self.gradientColors = profileData.gradientColors
                self.avatarData = profileData.avatarData
                self.isLoading = false
                print("✅ [Profile] Profile state updated")
            }
        } else {
            print("⚠️ [Profile] No local profile found")
            await MainActor.run { isLoading = false }
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
