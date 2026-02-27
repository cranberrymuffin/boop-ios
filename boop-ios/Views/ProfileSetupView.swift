import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var birthday: Date?
    @State private var bio: String

    @State private var imageSelection: PhotosPickerItem?
    @State private var avatarImage: AvatarImage?
    
    @State private var isLoading = false
    @State private var gradientColors: [Color] = []
    @State private var selectedColors: [Color] = []
    @State private var showColorPicker = false

    let buttonText: String
    let requireAllFields: Bool
    let isEditMode: Bool
    let onSave: (UserProfile, AvatarImage?) -> Void
    
    init(
        initialName: String = "",
        initialBirthday: Date? = nil,
        initialBio: String = "",
        initialAvatarImage: AvatarImage? = nil,
        buttonText: String = "Continue",
        requireAllFields: Bool = true,
        isEditMode: Bool = false,
        gradientColors: [Color]? = nil,
        onSave: @escaping (UserProfile, AvatarImage?) -> Void
    ) {
        _name = State(initialValue: initialName)
        _birthday = State(initialValue: initialBirthday)
        _bio = State(initialValue: initialBio)
        _avatarImage = State(initialValue: initialAvatarImage)
        let colors = gradientColors ?? ProfileSetupView.generateRandomGradient()
        _gradientColors = State(initialValue: colors)
        // Extract the two unique colors from the gradient pattern
        _selectedColors = State(initialValue: Array(Set(colors)).sorted(by: { colors.firstIndex(of: $0)! < colors.firstIndex(of: $1)! }))
        self.buttonText = buttonText
        self.requireAllFields = requireAllFields
        self.isEditMode = isEditMode
        self.onSave = onSave
    }

    var canSubmit: Bool {
        if requireAllFields {
            return !name.isEmptyAfterSanitizing && birthday != nil && !bio.isEmptyAfterSanitizing
        } else {
            return !name.isEmptyAfterSanitizing
        }
    }
    
    private static func generateRandomGradient() -> [Color] {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .cyan, .blue, .indigo, .purple, .pink,
            .mint, .teal, .brown, .white, .black, .gray
        ]
        let firstColor = colors.randomElement()!
        let secondColor = colors.filter { $0 != firstColor }.randomElement()!
        let selectedColors = [firstColor, secondColor]
        return (0..<9).map { selectedColors[$0 % 2] }
    }

    var body: some View {
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
                    ProfilePhotoSelector(
                        imageSelection: $imageSelection,
                        avatarImage: avatarImage
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    StyledTextField(placeholder: "Name", text: $name)
                        .listRowSeparator(.hidden)
                    DatePickerField(
                        title: "Set birthday",
                        placeholder: "Add birthday",
                        info: "Your birth year is kept private",
                        selectedDate: $birthday
                    )
                        .listRowSeparator(.hidden)
                    StyledTextField(placeholder: "Bio", text: $bio)
                        .listRowSeparator(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showColorPicker) {
                ColorPickerSheet(selectedColors: $selectedColors, onApply: {
                    updateGradient()
                    showColorPicker = false
                })
            }
            .toolbar {
                Button {
                    saveProfile()
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(buttonText)
                    }
                }
                .disabled(!canSubmit || isLoading)
            }
            .onChange(of: imageSelection) { _, newValue in
                guard let newValue else { return }
                loadTransferable(from: newValue)
            }
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

    private func saveProfile() {
        isLoading = true
        
        let profile = UserProfile(
            name: name.sanitize(),
            avatarData: avatarImage?.data,
            birthday: birthday,
            bio: bio.isEmpty ? nil : bio.sanitize(),
            gradientColors: gradientColors
        )
        
        onSave(profile, avatarImage)
        
        isLoading = false
    }
    
    private func updateGradient() {
        guard selectedColors.count == 2 else { return }
        gradientColors = (0..<9).map { selectedColors[$0 % 2] }
    }
}

// MARK: - Color Picker Sheet

private struct ColorPickerSheet: View {
    @Binding var selectedColors: [Color]
    let onApply: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private let availableColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .indigo, .purple, .pink,
        .mint, .teal, .brown, .white, .black, .gray
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.xl) {
                Text("Select 2 Colors")
                    .font(.headline)
                    .padding(.top)
                
                Text("Choose two colors for your gradient")
                    .font(.subheadline)
                    .foregroundColor(.textMuted)
                
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
                    onApply()
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
}

#Preview {
    ProfileSetupView(onSave: { _, _ in })
        .modelContainer(for: UserProfile.self, inMemory: true)
}
