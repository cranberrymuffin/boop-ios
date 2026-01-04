import SwiftUI
import PhotosUI
import Supabase

struct ProfileSetupView: View {
    @ObservedObject var authViewModel: AppleAuthViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = Date()
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    // Photo picker state
    @State private var imageSelection: PhotosPickerItem?
    @State private var avatarImage: AvatarImage?

    var age: Int {
        let calendar = Calendar.current
        let birthComponents = calendar.dateComponents([.year], from: dateOfBirth)
        let todayComponents = calendar.dateComponents([.year], from: Date())
        return (todayComponents.year ?? 0) - (birthComponents.year ?? 0)
    }

    var isAdult: Bool {
        age >= 18
    }

    var canSubmit: Bool {
        !firstName.isEmptyAfterSanitizing
            && !lastName.isEmptyAfterSanitizing
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Photo")) {
                    HStack {
                        Group {
                            if let avatarImage {
                                avatarImage.image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        
                        Spacer()
                        
                        PhotosPicker(selection: $imageSelection, matching: .images) {
                            Label("Select Photo", systemImage: "photo")
                        }
                    }
                }
                
                Section(header: Text("Profile Information")) {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }

                Section(header: Text("Date of Birth")) {
                    DatePicker(
                        "Select date",
                        selection: $dateOfBirth,
                        displayedComponents: [.date]
                    )
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .errorTextStyle()
                    }
                }

                Section {
                    Button(action: saveProfile) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Continue")
                        }
                    }
                    .disabled(!canSubmit || isLoading)
                }
            }
            .navigationTitle("Your Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: imageSelection) { _, newValue in
                guard let newValue else { return }
                loadTransferable(from: newValue)
            }
        }.pageBackground()
    }
    
    private func loadTransferable(from imageSelection: PhotosPickerItem) {
        Task {
            do {
                avatarImage = try await imageSelection.loadTransferable(type: AvatarImage.self)
            } catch {
                print("⚠️ Failed to load image: \(error.localizedDescription)")
            }
        }
    }

    private func saveProfile() {
        guard isAdult else {
            errorMessage = "You must be 18 or older."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let userID = authViewModel.userID else {
                    errorMessage = "User ID not available."
                    isLoading = false
                    return
                }
                
                // Create local profile
                let profile = UserProfile(
                    appleUserID: userID,
                    firstName: firstName.sanitize(),
                    lastName: lastName.sanitize(),
                    dateOfBirth: dateOfBirth
                )
                
                // Save to Supabase (with photo upload)
                try await saveToSupabase(profile: profile)
                
                // Save locally
                modelContext.insert(profile)
                
                // Complete setup
                await MainActor.run {
                    authViewModel.completeProfileSetup(userProfile: profile)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save profile: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func saveToSupabase(profile: UserProfile) async throws {
        #if canImport(Supabase)
        // Get current user from Supabase auth
        guard let client = SupabaseClientProvider.shared.client else {
            print("⚠️ Supabase client not available, skipping remote save")
            return
        }
        
        let currentUser = try await client.auth.session.user
        
        // Upload avatar if selected
        var avatarURL: String? = nil
        if let imageData = avatarImage?.data {
            do {
                avatarURL = try await SupabaseClientProvider.shared.uploadAvatar(
                    userId: currentUser.id,
                    imageData: imageData
                )
            } catch {
                print("⚠️ Failed to upload avatar: \(error.localizedDescription)")
                // Continue without avatar - don't fail the whole operation
            }
        }
        
        // Create Supabase profile
        let supabaseProfile = SupabaseProfile(
            id: currentUser.id,
            firstName: profile.firstName,
            lastName: profile.lastName,
            dateOfBirth: profile.dateOfBirth,
            avatarURL: avatarURL
        )
        
        // Save to Supabase using helper method
        try await SupabaseClientProvider.shared.upsertProfile(supabaseProfile)
        #else
        print("⚠️ Supabase not available, skipping remote save")
        #endif
    }
}

#Preview {
    ProfileSetupView(authViewModel: AppleAuthViewModel())
        .modelContainer(for: UserProfile.self, inMemory: true)
}
