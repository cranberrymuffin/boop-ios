import SwiftUI

struct HomeFeedBody: View {
    let interactions: [BoopInteraction]

    var body: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(Array(interactions.enumerated()), id: \.element.id) { index, interaction in
                let currentHeader = interaction.timestamp.relativeGroupHeader()
                let previousHeader = index > 0 ? interactions[index - 1].timestamp.relativeGroupHeader() : nil

                if previousHeader != currentHeader {
                    Text(currentHeader)
                        .heading1Style()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, index == 0 ? 0 : Spacing.md)
                }

                NavigationLink(value: interaction) {
                    feedCard(for: interaction)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.lg)
                .id(interaction.id)
            }
        }
        .padding(.bottom, Spacing.xl)
    }

    @ViewBuilder
    private func feedCard(for interaction: BoopInteraction) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            InteractionContentView(interaction: interaction) {
                MapSnapshotView(
                    coordinates: interaction.pathCoordinates,
                    interactionID: interaction.id
                )
            }

            if !interaction.imageData.isEmpty {
                feedPhotosRow(imageData: interaction.imageData)
            }

            feedNotesSection(notes: interaction.notes)
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
    }

    @ViewBuilder
    private func feedPhotosRow(imageData: [Data]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Photos")
                .heading3Style()
                .padding(.horizontal, Spacing.lg)

            HStack(spacing: Spacing.sm) {
                ForEach(Array(imageData.prefix(4).enumerated()), id: \.offset) { index, data in
                    if let uiImage = UIImage(data: data) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))

                            if index == 3, imageData.count > 4 {
                                Text("+\(imageData.count - 4)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                                    .padding(Spacing.xs)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    @ViewBuilder
    private func feedNotesSection(notes: String?) -> some View {
        if let notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Notes")
                    .heading3Style()
                    .padding(.horizontal, Spacing.lg)
                Text(notes)
                    .subtitleStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
            }
        }
    }
}
