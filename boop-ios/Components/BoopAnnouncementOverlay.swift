import SwiftUI

/// Full-screen reveal shown when a boop is received. Wraps `AnimatedMeshGradient`
/// with the "Boop!" + sender's display name overlay so the moment uses the
/// user's own profile gradient instead of a generic dimmed card.
struct BoopAnnouncementOverlay: View {
    let gradientColors: [Color]
    let displayName: String

    var body: some View {
        ZStack {
            AnimatedMeshGradient(
                colors: gradientColors,
                animationStyle: .verticalWave,
                duration: 2.0
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                Text("Boop!")
                    .font(.primary)
                    .foregroundColor(.staticWhite)
                Text(displayName)
                    .font(.heading2)
                    .foregroundColor(.staticWhite)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
        }
    }
}
