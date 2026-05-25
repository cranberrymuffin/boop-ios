import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Spacer()

                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 60))
                    .foregroundColor(.accentPrimary)

                VStack(spacing: Spacing.sm) {
                    Text("Login or Create Account")
                        .font(.heading1)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Back up your profile and interactions.")
                        .font(.subtitle)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: Spacing.md) {
                    SignInWithAppleButton(.continue, onRequest: { request in
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = supabaseManager.prepareSignIn()
                    }, onCompletion: { result in
                        Task {
                            await supabaseManager.handleAppleCompletion(result)
                            if supabaseManager.session != nil {
                                dismiss()
                            }
                        }
                    })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(CornerRadius.md)

                    if let error = supabaseManager.authError {
                        Text(error)
                            .font(.subtitle)
                            .foregroundColor(.statusError)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
            .padding(.horizontal, Spacing.lg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.accentPrimary)
                }
            }
        }
        .pageBackground()
        .overlay {
            if supabaseManager.isLoading {
                ProgressView()
                    .tint(.accentPrimary)
            }
        }
    }
}
