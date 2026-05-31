import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ZStack {
            AnimatedMeshGradient(
                colors: WelcomeView.welcomeGradient,
                animationStyle: .horizontalWave,
                duration: 4.0
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer()

                VStack(spacing: Spacing.sm) {
                    Text("Boop")
                        .primaryTextStyle()
                        .foregroundColor(.white)

                    Text("Meet friends IRL")
                        .subtitleStyle()
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                VStack(spacing: Spacing.md) {
                    NavigationLink(destination: LoginView(mode: .signUp)) {
                        Text("Sign Up")
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.md)
                            .background(Color.accentPrimary)
                            .foregroundColor(.textOnAccent)
                            .cornerRadius(CornerRadius.md)
                    }

                    NavigationLink(destination: LoginView(mode: .login)) {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.md)
                            .background(Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .cornerRadius(CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
        }
        .navigationBarHidden(true)
    }

    private static let welcomeGradient: [Color] = [
        .purple, .pink, .purple, .pink, .purple, .purple, .pink, .purple, .pink
    ]
}
