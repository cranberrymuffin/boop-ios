import SwiftUI
import AuthenticationServices

struct RootView: View {
    @StateObject private var authViewModel = AppleAuthViewModel()

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .completed:
                MainTabView()
            case .profileSetup:
                ProfileSetupView(authViewModel: authViewModel, isSetupMode: true, onProfileUpdated: nil)
            case .authorizing:
                VStack(spacing: Spacing.md) {
                    ProgressView()
                    Text("Signing in...")
                        .subtitleStyle()
                }
            case .failed(let message):
                VStack(spacing: Spacing.lg) {
                    Text("Sign in failed")
                        .heading2Style()
                    Text(message)
                        .subtitleStyle()
                    signInButton
                }
                .padding()
            case .signedOut, .signedIn:
                VStack(spacing: Spacing.xl) {
                    Text("Welcome to Boop")
                        .heading1Style()
                    signInButton
                }
                .padding()
            }
        }.pageBackground()
    }

    private var signInButton: some View {
        Button(action: {
            authViewModel.signInWithApple()
        }) {
            HStack {
                Image(systemName: "applelogo")
                Text("Sign in with Apple")
            }
            .frame(maxWidth: .infinity)
            .frame(height: ComponentSize.buttonSize)
            .foregroundColor(.white)
            .background(Color.black)
            .cornerRadius(CornerRadius.md)
        }
    }
}

#Preview {
    RootView()
}
