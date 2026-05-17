import MapKit
import SwiftUI

// MARK: - Shared Row

struct BoopListRow: View {
    let avatarImages: [Data?]
    let title: String
    let staticLabel: String?
    let timestamp: Date?

    var body: some View {
        HStack(spacing: Spacing.md) {
            OverlappingThumbnails(avatarImages: avatarImages)
                .frame(width: thumbnailFrameWidth, height: ThumbnailSize.single)

            VStack(alignment: .leading, spacing: LayoutConstant.cardContentGap) {
                Text(title)
                    .font(.heading2)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                subtitleView
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: IconSize.standard, weight: .semibold))
                .foregroundColor(.accentPrimary)
                .frame(width: IconSize.xsmall)
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: ComponentSize.cardHeight)
        .cardStyle()
    }

    @ViewBuilder
    private var subtitleView: some View {
        if let timestamp {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                HStack(spacing: 0) {
                    if let label = staticLabel, !label.isEmpty {
                        Text(label)
                            .font(.subtitle)
                            .foregroundColor(.textMuted)
                            .lineLimit(1)
                        Text(" • ")
                            .font(.subtitle)
                            .foregroundColor(.textMuted)
                    }
                    Text(timestamp.relativeString(abbreviated: true))
                        .font(.subtitle)
                        .foregroundColor(.textMuted)
                }
            }
        } else if let staticLabel {
            Text(staticLabel)
                .font(.subtitle)
                .foregroundColor(.textMuted)
                .lineLimit(1)
        }
    }

    private var thumbnailFrameWidth: CGFloat {
        switch max(avatarImages.count, 1) {
        case 1: return ThumbnailSize.single
        case 2: return ThumbnailSize.doubleWidth
        default: return ThumbnailSize.tripleWidth
        }
    }

}

// MARK: - Overlapping Thumbnails

struct OverlappingThumbnails: View {
    let avatarImages: [Data?]

    private var count: Int { max(avatarImages.count, 1) }

    var body: some View {
        switch count {
        case 1:
            avatar(at: 0)
        case 2:
            ZStack(alignment: .topLeading) {
                avatar(at: 0)
                    .position(x: ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)
                avatar(at: 1)
                    .position(x: ThumbnailOffset.double + ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)
            }
            .frame(width: ThumbnailSize.doubleWidth, height: ThumbnailSize.single)
        default:
            ZStack(alignment: .topLeading) {
                avatar(at: 0)
                    .position(x: ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)
                avatar(at: 1)
                    .position(x: ThumbnailOffset.middle + ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)
                avatar(at: 2)
                    .position(x: ThumbnailOffset.back + ThumbnailSize.single / 2, y: ThumbnailSize.single / 2)
            }
            .frame(width: ThumbnailSize.tripleWidth, height: ThumbnailSize.single)
        }
    }

    @ViewBuilder
    private func avatar(at index: Int) -> some View {
        if index < avatarImages.count,
           let data = avatarImages[index],
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth))
        } else {
            Circle()
                .fill(Color.formBackgroundInactive)
                .overlay(Circle().strokeBorder(Color.accentPrimary, lineWidth: ThumbnailSize.borderWidth))
                .frame(width: ThumbnailSize.single, height: ThumbnailSize.single)
        }
    }
}

