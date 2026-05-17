import SwiftUI

/// Shared read-only header + map block for both feed cards and the detail view.
/// Callers supply their own map content (snapshot for feed, live Map for detail).
struct InteractionContentView<MapContent: View>: View {
    let interaction: BoopInteraction
    @ViewBuilder let mapContent: () -> MapContent

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Boop with \(interaction.displayTitle)")
                    .primaryTextStyle()

                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "clock")
                            .font(.subtitle)
                            .foregroundColor(.textMuted)
                        Text(interaction.timestamp.relativeString())
                            .subtitleStyle()
                    }
                }

                if !interaction.location.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subtitle)
                            .foregroundColor(.textMuted)
                        Text(interaction.location)
                            .subtitleStyle()
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)

            if !interaction.pathCoordinates.isEmpty {
                mapContent()
                    .padding(.horizontal, Spacing.lg)
            }
        }
    }
}
