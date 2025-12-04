//
//  BoopInteractionListView.swift
//  boop-ios
//
//  Example view showing BoopInteractionCard usage
//

import SwiftUI

struct BoopInteractionListView: View {
    let interactions = BoopInteraction.samples

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
                            .foregroundColor(.primary)
                            .frame(width: ComponentSize.buttonSize, height: ComponentSize.buttonSize)
                            .background(Color.white.opacity(0.9))
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
                        ForEach(Array(interactions.enumerated()), id: \.element.id) { index, interaction in
                            BoopInteractionCard(
                                interaction: BoopInteraction(
                                    title: interaction.title,
                                    location: interaction.location,
                                    date: interaction.date,
                                    time: interaction.time,
                                    thumbnails: Array(repeating: UIImage(), count: index + 1)
                                ),
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
                        .fill(Color.white)
                        .frame(width: IconSize.dot, height: IconSize.dot)

                    Circle()
                        .fill(Color.white.opacity(0.3))
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
