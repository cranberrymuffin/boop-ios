import SwiftUI
import PhotosUI
import Supabase

struct ProfileSetupView: View {
    var authViewModel: AppleAuthViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = Date()
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    // Photo picker state
    @State private var imageSelection: PhotosPickerItem?
    @State private var avatarImage: AvatarImage?
    @State private var currentAvatarURL: String?
    
    // Mode control
    let isSetupMode: Bool
    let onProfileUpdated: (() -> Void)?

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
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading profile...")
                            .subtitleStyle()
                    }
                } else {
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

                        if isSetupMode {
                            Section(header: Text("Date of Birth")) {
                                DatePicker(
                                    "Select date",
                                    selection: $dateOfBirth,
                                    displayedComponents: [.date]
                                )
                            }
                        } else {
                            Section(header: Text("Date of Birth")) {
                                Text(formattedDate(dateOfBirth) ?? "Unknown")
                                    .primaryTextStyle()
                            }
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
                                    Text(isSetupMode ? "Continue" : "Save")
                                }
                            }
                            .disabled(!canSubmit || isLoading)
                        }
                    }
                }
            }
            .navigationTitle(isSetupMode ? "Your Profile" : "You")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: imageSelection) { _, newValue in
                guard let newValue else { return }
                loadTransferable(from: newValue)
            }
            .task {
                if !isSetupMode {
                    await loadProfileFromSupabase()
                }
            }
        }
        .pageBackground()
    }
    
    private func formattedDate(_ date: Date) -> String? {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return "\(month)/\(day)/\(year)"
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
        if isSetupMode {
            saveProfileSetup()
        } else {
            saveProfileEdit()
        }
    }

    private func saveProfileSetup() {
        guard let authVM = authViewModel else {
            errorMessage = "Auth view model not available."
            return
        }
        
        guard isAdult else {
            errorMessage = "You must be 18 or older."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let userID = authVM.userID else {
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
                    authVM.completeProfileSetup(userProfile: profile)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save profile: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func saveProfileEdit() {
        isLoading = true
        errorMessage = nil

        Task {
            #if canImport(Supabase)
            guard let client = SupabaseClientProvider.shared.client else {
                await MainActor.run { errorMessage = "Supabase client unavailable"; isLoading = false }
                return
            }
            do {
                let session = try await client.auth.session
                var avatarURL = currentAvatarURL
                
                // Step 1: Handle avatar changes - upload if new image was selected
                if let data = avatarImage?.data {
                    do {
                        // Delete old avatar before uploading new one
                        if let oldURL = currentAvatarURL {
                            do {
                                // Extract storage path from URL
                                if let pathComponent = oldURL.split(separator: "/avatars/").last {
                                    let storagePath = String(pathComponent)
                                    try await SupabaseClientProvider.shared.deleteAvatar(path: storagePath)
                                    print("✅ Old avatar deleted")
                                }
                            } catch {
                                print("⚠️ Failed to delete old avatar: \(error)")
                            }
                        }
                        
                        avatarURL = try await SupabaseClientProvider.shared.uploadAvatar(userId: session.user.id, imageData: data)
                        print("✅ Avatar uploaded: \(avatarURL ?? "nil")")
                    } catch {
                        print("⚠️ Avatar upload failed: \(error)")
                        await MainActor.run { errorMessage = "Avatar upload failed"; isLoading = false }
                        return
                    }
                }

                // Step 2: Upsert profile
                let supabaseProfile = SupabaseProfile(
                    id: session.user.id,
                    firstName: firstName.sanitize(),
                    lastName: lastName.sanitize(),
                    dateOfBirth: dateOfBirth,
                    avatarURL: avatarURL
                )

                try await SupabaseClientProvider.shared.upsertProfile(supabaseProfile)
                print("✅ Profile upserted")

                // Step 3: Update state and dismiss
                await MainActor.run {
                    currentAvatarURL = avatarURL
                    errorMessage = nil
                    isLoading = false
                    onProfileUpdated?()
                    dismiss()
                }
            } catch {
                print("❌ Save error: \(error)")
                await MainActor.run { errorMessage = "Failed to save"; isLoading = false }
            }
            #endif
        }
    }
    
    private func loadProfileFromSupabase() async {
        #if canImport(Supabase)
        guard let client = SupabaseClientProvider.shared.client else { return }
        await MainActor.run { isLoading = true }
        do {
            let session = try await client.auth.session
            let remoteProfile = try await SupabaseClientProvider.shared.getProfile(userId: session.user.id)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]

            let dob: Date? = {
                if let dobString = remoteProfile.dateOfBirth {
                    return formatter.date(from: dobString)
                }
                return nil
            }()

            if let avatarURL = remoteProfile.avatarURL, let url = URL(string: avatarURL) {
                let (data, _) = try await URLSession.shared.data(from: url)
                #if canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    let image = Image(uiImage: uiImage)
                    await MainActor.run {
                        self.avatarImage = AvatarImage(image: image, data: data)
                        self.currentAvatarURL = avatarURL
                    }
                }
                #endif
            }

            await MainActor.run {
                self.firstName = remoteProfile.firstName ?? ""
                self.lastName = remoteProfile.lastName ?? ""
                self.dateOfBirth = dob ?? Date()
                self.currentAvatarURL = remoteProfile.avatarURL
                self.isLoading = false
            }
        } catch {
            await MainActor.run { errorMessage = "Failed to load profile"; isLoading = false }
        }
        #endif
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
    ProfileSetupView(authViewModel: AppleAuthViewModel(), isSetupMode: true, onProfileUpdated: {})
        .modelContainer(for: UserProfile.self, inMemory: true)
}
