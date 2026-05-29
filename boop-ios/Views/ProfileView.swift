import SwiftUI
import SwiftData

struct ProfileView: View {

    enum ProfileState {
        case loadingProfile
        case editingProfile
        case noProfile
        case displayProfile
    }

    @EnvironmentObject private var supabaseManager: SupabaseManager
    @State private var path = NavigationPath()
    @State private var showingLogin = false
    @Query private var allInteractions: [BoopInteraction]
    @Query private var allContacts: [Contact]
    @State private var profileState = ProfileState.loadingProfile

    private var ownProfile: Contact? {
        guard let uuidString = UserDefaults.standard.string(forKey: UserDefaultsKeys.localDeviceUUID),
              let uuid = UUID(uuidString: uuidString) else { return nil }
        return allContacts.first(where: { $0.uuid == uuid })
    }

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
            .toolbar {
                if profileState == .noProfile {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Log In") { showingLogin = true }
                            .foregroundColor(.accentPrimary)
                    }
                }
            }
            .navigationDestination(for: ProfileHistoryRoute.self) { _ in
                AllBoopsHistoryView()
            }
            .navigationDestination(for: BoopInteraction.self) { interaction in
                InteractionDetailView(interaction: interaction)
            }
            .onAppear {
                guard profileState == .loadingProfile else { return }
                profileState = ownProfile != nil ? .displayProfile : .noProfile
            }
            .onChange(of: ownProfile?.uuid) { _, uuid in
                switch (uuid, profileState) {
                case (.some, .noProfile):
                    profileState = .displayProfile
                case (.none, .displayProfile):
                    profileState = .noProfile
                default:
                    break
                }
            }
            .sheet(isPresented: $showingLogin, onDismiss: loadProfile) {
                LoginView()
            }
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
                profileState = .displayProfile
                Task { await supabaseManager.syncProfile(contact) }
            }
        )
    }

    private func loadProfile() {
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
