//
//  BoopInteractionCard.swift
//  boop-ios
//
//  SwiftUI component for displaying Boop interactions.
//  When path coordinates are available, a map showing the traveled path is
//  rendered above the card content row (similar to PathRecorder's card style).
//

import MapKit
import SwiftUI

struct BoopInteractionCard: View {
    let interaction: BoopInteraction
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(spacing: 0) {
            
                // Content row
                HStack(spacing: Spacing.md) {
                    // Thumbnail(s)
                    thumbnailView
                        .frame(width: thumbnailWidth, height: ThumbnailSize.single)

                    // Content
                    VStack(alignment: .leading, spacing: LayoutConstant.cardContentGap) {
                        // Title
                        Text(interaction.title)
                            .font(.heading2)
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Subtitle: location • date • time
                        // TimelineView updates automatically as time passes
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            HStack(spacing: 0) {
                                if !interaction.location.isEmpty {
                                    subtitleText(interaction.location)
                                    bullet
                                }
                                subtitleText(relativeTimeString(for: interaction.timestamp))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: IconSize.standard, weight: .semibold))
                        .foregroundColor(.accentPrimary)
                        .frame(width: IconSize.xsmall)
                }
                .padding(.horizontal, Spacing.lg)
                .frame(height: ComponentSize.cardHeight)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .cardStyle()
    }

    // MARK: - Thumbnail Views

    @ViewBuilder
    private var thumbnailView: some View {
        switch interaction.thumbnailCount {
        case 1:
            singleThumbnail
        case 2:
            doubleThumbnail
        case 3...:
            tripleThumbnail
        default:
            EmptyView()
        }
    }

    private var thumbnailWidth: CGFloat {
        switch interaction.thumbnailCount {
        case 1: return ThumbnailSize.single
        case 2: return ThumbnailSize.doubleWidth
        case 3...: return ThumbnailSize.tripleWidth
        default: return 0
        }
    }

    // Single circular thumbnail
    private var singleThumbnail: some View {
        Circle()
            .fill(Color.formBackgroundInactive)
            .overlay(
                Circle()
                    .strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth)
            )
            .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
    }

    // Two thumbnails slightly overlapping
    private var doubleThumbnail: some View {
        ZStack(alignment: .topLeading) {
            // Left thumbnail (back)
            Circle()
                .fill(Color.formBackgroundInactive)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth)
                )
                .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
                .position(x: ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)

            // Right thumbnail (front)
            Circle()
                .fill(Color.formBackgroundInactive)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth)
                )
                .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
                .position(x: ThumbnailOffset.double + ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)
        }
        .frame(width: ThumbnailSize.doubleWidth, height: ThumbnailSize.single, alignment: .leading)
    }

    // Three overlapping thumbnails
    private var tripleThumbnail: some View {
        ZStack(alignment: .topLeading) {
            // Front thumbnail (leftmost)
            Circle()
                .fill(Color.formBackgroundInactive)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth)
                )
                .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
                .position(x: ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)

            // Middle thumbnail
            Circle()
                .fill(Color.formBackgroundInactive)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth)
                )
                .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
                .position(x: ThumbnailOffset.middle + ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)

            // Back thumbnail (rightmost)
            Circle()
                .fill(Color.formBackgroundInactive)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth)
                )
                .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
                .position(x: ThumbnailOffset.back + ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)
        }
        .frame(width: ThumbnailSize.tripleWidth, height: ThumbnailSize.single, alignment: .leading)
    }

    // MARK: - Helper Views

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(.subtitle)
            .foregroundColor(.textMuted)
            .lineLimit(1)
    }

    private var bullet: some View {
        Text(" • ")
            .font(.subtitle)
            .foregroundColor(.textMuted)
    }

    // MARK: - Helper Functions

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date.now)
    }
}

// MARK: - Preview

#Preview("No Map (legacy)") {
    VStack(spacing: Spacing.lg) {
        BoopInteractionCard(
            interaction: BoopInteraction(
                title: "Hang with Aparna",
                location: "Stuytown, NYC",
                timestamp: Date().addingTimeInterval(-86400),
                imageData: [Data()]
            )
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}

#Preview("Single Pin Map") {
    VStack(spacing: Spacing.lg) {
        BoopInteractionCard(
            interaction: {
                let i = BoopInteraction(
                    title: "Bumped into Sarem",
                    location: "John St, NYC",
                    timestamp: Date().addingTimeInterval(-3600),
                    imageData: [],
                    pathCoordinates: [CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)]
                )
                return i
            }()
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}

#Preview("Path Map") {
    VStack(spacing: Spacing.lg) {
        BoopInteractionCard(
            interaction: {
                let coords: [CLLocationCoordinate2D] = [
                    CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                    CLLocationCoordinate2D(latitude: 40.7135, longitude: -74.0055),
                    CLLocationCoordinate2D(latitude: 40.7140, longitude: -74.0045),
                    CLLocationCoordinate2D(latitude: 40.7145, longitude: -74.0035),
                ]
                let i = BoopInteraction(
                    title: "Anu, Jesse, Sarem",
                    location: "Joyface, NYC",
                    timestamp: Date().addingTimeInterval(-31536000),
                    imageData: [Data(), Data()],
                    pathCoordinates: coords
                )
                return i
            }()
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}
