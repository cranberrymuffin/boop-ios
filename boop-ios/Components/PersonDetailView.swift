import SwiftUI

struct PersonDetailView<Route: Hashable>: View {
    let displayName: String
    let birthday: Date?
    let bio: String?
    let avatarData: Data?
    let gradientColors: [Color]
    let boopCount: Int
    let isOwnProfile: Bool
    var onEdit: (() -> Void)? = nil
    let historyRoute: Route

    @EnvironmentObject private var supabaseManager: SupabaseManager

    var body: some View {
        ZStack {
            AnimatedMeshGradient(
                colors: gradientColors,
                animationStyle: .horizontalWave,
                duration: 3.0
            )
            .ignoresSafeArea()

            Form {
                Section {
                    VStack(spacing: Spacing.lg) {
                        if let avatarData, let uiImage = UIImage(data: avatarData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.staticWhite.opacity(0.4), lineWidth: 2))
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.staticWhite.opacity(0.6))
                        }

                        Text(displayName)
                            .font(.heading1)
                            .foregroundColor(.staticWhite)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        if let birthday {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "birthday.cake")
                                    .foregroundColor(.staticWhite)
                                Text(birthday.formatted(.dateTime.month().day()))
                                    .font(.subtitle)
                                    .foregroundColor(.staticWhite)
                            }
                        }

                        if let bio, !bio.isEmpty {
                            Text(bio)
                                .foregroundColor(.staticWhite)
                                .multilineTextAlignment(.center)
                                .padding(.top, Spacing.sm)
                        }
                    }
                    .padding(.vertical, Spacing.lg)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if isOwnProfile {
                    accountSection
                }

                BoopHistoryRow(count: boopCount, route: historyRoute)
            }
            .scrollContentBackground(.hidden)
        }
        .toolbar {
            if isOwnProfile {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { onEdit?() }
                }
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if let session = supabaseManager.session {
            Section {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.statusSuccess)
                    Text(session.user.email ?? "Signed in with Apple")
                        .font(.subtitle)
                        .foregroundColor(.staticWhite)
                }
                .padding(.vertical, Spacing.xs)

                Button {
                    Task { await supabaseManager.signOut() }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Log out")
                    }
                    .foregroundColor(.statusError)
                }
            }
            .listRowBackground(Color.clear)
        }
    }
}
