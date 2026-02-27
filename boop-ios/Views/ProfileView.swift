import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var birthday: Date?
    @State private var bio = ""
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var isEditingDisplay = false

    @State private var imageSelection: PhotosPickerItem?
    @State private var avatarImage: AvatarImage?
    @State private var gradientColors: [Color] = []
    @State private var showColorPicker = false

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
                    } else if isEditingDisplay {
                        editDisplayModeView
                    } else {
                        displayModeView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEditing && !isEditingDisplay && !isLoading {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Customize") {
                            isEditingDisplay = true
                        }
                    }
                } else if isEditingDisplay {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            saveDisplayChanges()
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            cancelDisplayChanges()
                        }
                    }
                }
            }
            .onChange(of: imageSelection) { _, newValue in
                guard let newValue else { return }
                loadTransferable(from: newValue)
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
                            avatarImage: avatarImage?.image,
                            displayName: name,
                            birthday: birthday,
                            bio: bio.isEmpty ? nil : bio
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
            initialAvatarImage: avatarImage,
            buttonText: "Save",
            requireAllFields: false,
            isEditMode: true,
            gradientColors: gradientColors,
            onSave: { profile, avatar in
                saveProfile(profile: profile, avatar: avatar)
            }
        )
    }
    
    private var editDisplayModeView: some View {
        NavigationView {
            ZStack {
                AnimatedMeshGradient(
                    colors: gradientColors,
                    animationStyle: .horizontalWave,
                    duration: 3.0
                )
                .ignoresSafeArea()
                
                VStack {
                    Form {
                        Section {
                            ProfileDisplayCard(
                                avatarImage: avatarImage?.image,
                                displayName: name,
                                birthday: birthday,
                                bio: bio.isEmpty ? nil : bio
                            )
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    .scrollContentBackground(.hidden)
                    
                    // Display customization controls
                    VStack(spacing: Spacing.lg) {
                        Button(action: {
                            showColorPicker = true
                        }) {
                            HStack {
                                Text("Gradient Colors")
                                    .foregroundColor(.textPrimary)
                                    .font(.headline)
                                Spacer()
                                HStack(spacing: Spacing.xs) {
                                    ForEach(Array(Set(gradientColors)).prefix(2), id: \.self) { color in
                                        Circle()
                                            .fill(color)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(CornerRadius.lg)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                }
            }
            .sheet(isPresented: $showColorPicker) {
                DisplayColorPickerSheet(gradientColors: $gradientColors)
            }
        }
    }
    
    private func saveDisplayChanges() {
        Task {
            if var profileData = await DataStore.shared.getUserProfile() {
                let profile = UserProfile(
                    name: profileData.name,
                    avatarData: profileData.avatarData,
                    birthday: profileData.birthday,
                    bio: profileData.bio,
                    gradientColors: gradientColors
                )
                await DataStore.shared.setUserProfile(profile)
                modelContext.insert(profile)
            }
            await MainActor.run {
                isEditingDisplay = false
            }
        }
    }
    
    private func cancelDisplayChanges() {
        // Reload original gradient colors
        Task {
            await loadProfile()
            await MainActor.run {
                isEditingDisplay = false
            }
        }
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

    private func saveProfile(profile: UserProfile, avatar: AvatarImage?) {
        isLoading = true

        Task {
            await DataStore.shared.setUserProfile(profile)
            modelContext.insert(profile)

            await MainActor.run {
                // Update local state
                self.name = profile.name
                self.birthday = profile.birthday
                self.bio = profile.bio ?? ""
                self.avatarImage = avatar
                self.gradientColors = profile.gradientColors
                
                self.isLoading = false
                self.isEditing = false
            }
        }
    }

    private func loadProfile() async {
        await MainActor.run { isLoading = true }

        if let profileData = await DataStore.shared.getUserProfile() {
            print("✅ [Profile] Local profile loaded")

            if let avatarData = profileData.avatarData,
               let uiImage = UIImage(data: avatarData) {
                let image = Image(uiImage: uiImage)
                await MainActor.run {
                    self.avatarImage = AvatarImage(image: image, data: avatarData)
                }
            }

            await MainActor.run {
                self.name = profileData.name
                self.birthday = profileData.birthday
                self.bio = profileData.bio ?? ""
                self.gradientColors = profileData.gradientColors
                self.isLoading = false
                print("✅ [Profile] Profile state updated")
            }
        } else {
            print("⚠️ [Profile] No local profile found")
            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Display Color Picker Sheet

private struct DisplayColorPickerSheet: View {
    @Binding var gradientColors: [Color]
    @State private var selectedColors: [Color] = []
    
    @Environment(\.dismiss) private var dismiss
    
    private let availableColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .indigo, .purple, .pink,
        .mint, .teal, .brown, .white, .black, .gray
    ]
    
    init(gradientColors: Binding<[Color]>) {
        self._gradientColors = gradientColors
        // Extract the two unique colors from the gradient
        _selectedColors = State(initialValue: Array(Set(gradientColors.wrappedValue)).prefix(2).map { $0 })
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.xl) {
                Text("Select 2 Colors")
                    .font(.headline)
                    .padding(.top)
                
                Text("Choose two colors for your gradient")
                    .font(.subheadline)
                    .foregroundColor(.textMuted)
                
                // Live preview
                ZStack {
                    AnimatedMeshGradient(
                        colors: selectedColors.count == 2 ? (0..<9).map { selectedColors[$0 % 2] } : gradientColors,
                        animationStyle: .horizontalWave,
                        duration: 3.0
                    )
                    .frame(height: 120)
                    .cornerRadius(CornerRadius.lg)
                }
                .padding(.horizontal)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: Spacing.lg) {
                    ForEach(availableColors, id: \.self) { color in
                        Button(action: {
                            toggleColorSelection(color)
                        }) {
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 60, height: 60)
                                
                                if selectedColors.contains(color) {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 60, height: 60)
                                    
                                    if let index = selectedColors.firstIndex(of: color) {
                                        Text("\(index + 1)")
                                            .font(.heading2)
                                            .foregroundColor(.textPrimary)
                                            .shadow(radius: 2)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                
                Spacer()
                
                Button(action: {
                    applyColors()
                }) {
                    Text("Apply")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedColors.count == 2 ? Color.accentPrimary : Color.formBackgroundInactive)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(CornerRadius.lg)
                }
                .disabled(selectedColors.count != 2)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func toggleColorSelection(_ color: Color) {
        if let index = selectedColors.firstIndex(of: color) {
            selectedColors.remove(at: index)
        } else if selectedColors.count < 2 {
            selectedColors.append(color)
        } else {
            // Replace the first color if already have 2 selected
            selectedColors[0] = selectedColors[1]
            selectedColors[1] = color
        }
    }
    
    private func applyColors() {
        gradientColors = (0..<9).map { selectedColors[$0 % 2] }
        dismiss()
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
}
