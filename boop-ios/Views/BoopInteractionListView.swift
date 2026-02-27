//
//  BoopInteractionListView.swift
//  boop-ios
//
//  Example view showing BoopInteractionCard usage
//

import SwiftUI

struct BoopInteractionListView: View {
    let interactions: [BoopInteraction] = [
        BoopInteraction(
            title: "Hang with Aparna",
            location: "Stuytown, NYC",
            timestamp: Date().addingTimeInterval(-86400),
            imageData: [Data()]
        ),
        BoopInteraction(
            title: "Anish, Sarem...",
            location: "John St, NYC",
            timestamp: Date().addingTimeInterval(-604800),
            imageData: [Data(), Data()]
        ),
        BoopInteraction(
            title: "Anu, Jesse, Sarem",
            location: "Joyface, NYC",
            timestamp: Date().addingTimeInterval(-31536000),
            imageData: [Data(), Data(), Data()]
        )
    ]

    var body: some View {
        ZStack {
            Color.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page Header
                HStack {
                    Button(action: {}) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: IconSize.standard, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .frame(width: ComponentSize.buttonSize, height: ComponentSize.buttonSize)
                            .background(Color.backgroundSecondary)
                            .clipShape(Circle())
                    }
                    .padding(.leading, Spacing.lg)

                    Spacer()

                    Text("Diary")
                        .font(.primary)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    // Spacer for symmetry
                    Color.clear
                        .frame(width: ComponentSize.buttonSize + Spacing.lg)
                }
                .padding(.vertical, Spacing.sm + 2)

                // Section Title
                HStack {
                    Text("This Week")
                        .font(.heading1)
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, Spacing.lg)

                    Spacer()
                }
                .padding(.top, Spacing.xl)

                // Cards List
                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        ForEach(interactions) { interaction in
                            BoopInteractionCard(
                                interaction: interaction,
                                onTap: {
                                    print("Tapped: \(interaction.title)")
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.sm + 2)
                    .padding(.top, Spacing.xl)
                }

                // Page Control
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Color.textPrimary)
                        .frame(width: IconSize.dot, height: IconSize.dot)

                    Circle()
                        .fill(Color.textPrimary.opacity(0.3))
                        .frame(width: IconSize.dot, height: IconSize.dot)
                }
                .padding(.vertical, Spacing.lg)
            }
        }
    }
}

#Preview {
    BoopInteractionListView()
}
