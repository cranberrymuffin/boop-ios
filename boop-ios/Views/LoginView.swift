import SwiftUI
import AuthenticationServices

enum LoginMode {
    case signUp, login
}

struct LoginView: View {
    let mode: LoginMode

    @EnvironmentObject private var supabaseManager: SupabaseManager

    private enum FormViewState {
        case input
        case awaitingVerification(email: String)
        case resetEmailSent
    }

    @State private var viewState: FormViewState = .input
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var fieldError: String?

    private var title: String {
        mode == .signUp ? "Create Account" : "Sign In"
    }

    private var subtitle: String {
        mode == .signUp
            ? "Sign up to back up your profile and interactions."
            : "Welcome back."
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.accentPrimary)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.heading1)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
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
                    }
                })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(CornerRadius.md)

                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.textMuted)
                    Text("or")
                        .font(.subtitle)
                        .foregroundColor(.textMuted)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.textMuted)
                }

                switch viewState {
                case .input:
                    inputFormView
                case .awaitingVerification(let verifiedEmail):
                    awaitingVerificationView(verifiedEmail: verifiedEmail)
                case .resetEmailSent:
                    resetEmailSentView
                }

                if let fieldError {
                    Text(fieldError)
                        .font(.subtitle)
                        .foregroundColor(.statusError)
                        .multilineTextAlignment(.center)
                }
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
        .pageBackground()
        .overlay {
            if supabaseManager.isLoading {
                ProgressView()
                    .tint(.accentPrimary)
            }
        }
    }

    // MARK: - Form Sections

    @ViewBuilder
    private var inputFormView: some View {
        VStack(spacing: Spacing.md) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(Spacing.md)
                .background(Color.formBackgroundInactive)
                .cornerRadius(CornerRadius.md)
                .onChange(of: email) { _, _ in
                    fieldError = nil
                    supabaseManager.authError = nil
                }

            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(Spacing.md)
                .background(Color.formBackgroundInactive)
                .cornerRadius(CornerRadius.md)
                .onChange(of: password) { _, _ in
                    fieldError = nil
                    supabaseManager.authError = nil
                }

            if mode == .signUp {
                Button("Create Account") {
                    Task {
                        guard validateInput(requirePassword: true) else { return }
                        let result = await supabaseManager.signUpWithEmail(email, password: password)
                        if case .verificationRequired(let e) = result {
                            viewState = .awaitingVerification(email: e)
                        }
                        // No dismiss() — RootView reactive routing handles transition on session change
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
                .background(Color.accentPrimary)
                .foregroundColor(.textOnAccent)
                .cornerRadius(CornerRadius.md)
                .disabled(supabaseManager.isLoading)
            }

            if mode == .login {
                Button("Sign In") {
                    Task {
                        guard validateInput(requirePassword: true) else { return }
                        await supabaseManager.signInWithEmail(email, password: password)
                        // No dismiss() — RootView reactive routing handles transition on session change
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
                .background(Color.accentPrimary)
                .foregroundColor(.textOnAccent)
                .cornerRadius(CornerRadius.md)
                .disabled(supabaseManager.isLoading)

                Button("Forgot password?") {
                    Task {
                        guard validateInput(requirePassword: false) else { return }
                        await supabaseManager.sendPasswordReset(for: email)
                        viewState = .resetEmailSent
                    }
                }
                .font(.subtitle)
                .foregroundColor(.textMuted)
                .disabled(supabaseManager.isLoading)
            }
        }
    }

    @ViewBuilder
    private func awaitingVerificationView(verifiedEmail: String) -> some View {
        VStack(spacing: Spacing.md) {
            Text("Check your inbox")
                .font(.heading2)
                .foregroundColor(.textPrimary)

            Text("We sent a verification link to \(verifiedEmail). Tap the link, then come back and sign in.")
                .font(.subtitle)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            Button("I've verified — sign in") {
                Task {
                    await supabaseManager.signInWithEmail(verifiedEmail, password: password)
                    // No dismiss() — RootView reactive routing handles transition on session change
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(Color.accentPrimary)
            .foregroundColor(.textOnAccent)
            .cornerRadius(CornerRadius.md)
            .disabled(supabaseManager.isLoading)

            Button("Use a different email") {
                viewState = .input
                email = ""
                password = ""
                fieldError = nil
                supabaseManager.authError = nil
            }
            .font(.subtitle)
            .foregroundColor(.textMuted)
        }
    }

    @ViewBuilder
    private var resetEmailSentView: some View {
        VStack(spacing: Spacing.md) {
            Text("Reset email sent")
                .font(.heading2)
                .foregroundColor(.textPrimary)

            Text("If an account exists for \(email), you'll receive a reset link. After resetting your password in the browser, come back here and sign in with your new password.")
                .font(.subtitle)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            Button("Back to sign in") {
                viewState = .input
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(Color.accentPrimary)
            .foregroundColor(.textOnAccent)
            .cornerRadius(CornerRadius.md)
        }
    }

    // MARK: - Validation

    private func validateInput(requirePassword: Bool) -> Bool {
        fieldError = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            fieldError = "Email is required."
            return false
        }
        let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        guard email.range(of: emailRegex, options: .regularExpression) != nil else {
            fieldError = "Enter a valid email."
            return false
        }
        if requirePassword {
            guard password.count >= 8 else {
                fieldError = "Password must be at least 8 characters."
                return false
            }
        }
        return true
    }
}
