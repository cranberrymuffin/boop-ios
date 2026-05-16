import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var birthday: Date?
    @State private var bio: String

    @State private var isLoading = false
    @State private var gradientColors: [Color] = []
    @State private var showColorPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var avatarData: Data?

    let buttonText: String
    let requireAllFields: Bool
    let isEditMode: Bool
    let onSave: (UserProfile) -> Void

    init(
        initialName: String = "",
        initialBirthday: Date? = nil,
        initialBio: String = "",
        buttonText: String = "Continue",
        requireAllFields: Bool = true,
        isEditMode: Bool = false,
        gradientColors: [Color]? = nil,
        initialAvatarData: Data? = nil,
        onSave: @escaping (UserProfile) -> Void
    ) {
        self.name = initialName
        self.birthday = initialBirthday
        self.bio = initialBio
        self.gradientColors = gradientColors ?? ProfileSetupView.generateRandomGradient()
        self.avatarData = initialAvatarData
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
                VStack(spacing: 0) {
                    // Avatar picker
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if avatarData != nil
                            {
                                let uiImage = UIImage(data: avatarData!)
                                Image(uiImage: uiImage!)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 2))
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 88, height: 88)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentPrimary)
                                .background(Color.white, in: Circle())
                                .font(.system(size: 22))
                        }
                    }
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)

                    Form {
                        Section {
                            StyledTextField(placeholder:
                                                name != "" ? name : "Name", text: $name)
                                .listRowSeparator(.hidden)
                            DatePickerField(
                                title: "Set birthday",
                                placeholder: birthday != nil ? birthday!.formatted() : "Add Birthday",
                                info: "Your birth year is kept private",
                                selectedDate: $birthday
                            )
                                .listRowSeparator(.hidden)
                            StyledTextField(placeholder: bio != "" ? bio : "Bio", text: $bio)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }

                    Button(action: { showColorPicker = true }) {
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
                    .padding(.bottom)
                }

            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showColorPicker) {
                DisplayColorPickerSheet(gradientColors: $gradientColors)
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
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let newItem,
                       let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run { avatarData = data }
                    }
                }
            }
        }
    }
}

    private func saveProfile() {
        isLoading = true

        let profile = UserProfile(
            name: name.sanitize(),
            birthday: birthday,
            bio: bio.isEmpty ? nil : bio.sanitize(),
            gradientColors: gradientColors,
            avatarData: avatarData
        )

        onSave(profile)

        isLoading = false
    }

}

#Preview {
    ProfileSetupView(onSave: { _ in })
        .modelContainer(for: UserProfile.self, inMemory: true)
}
