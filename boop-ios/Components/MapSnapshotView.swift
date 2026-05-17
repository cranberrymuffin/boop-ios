import MapKit
import SwiftUI

nonisolated(unsafe) private let snapshotCache = NSCache<NSString, UIImage>()

struct MapSnapshotView: View {
    let coordinates: [CLLocationCoordinate2D]
    let interactionID: UUID

    @State private var snapshot: UIImage?

    private var cacheKey: NSString {
        "\(interactionID.uuidString)-\(coordinates.count)-\(coordinates.first?.latitude ?? 0)-\(coordinates.last?.latitude ?? 0)" as NSString
    }

    var body: some View {
        Group {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(height: MapSize.cardMapHeight)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.formBackgroundInactive)
                    .frame(height: MapSize.cardMapHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .allowsHitTesting(false)
        .task(id: cacheKey) {
            if let cached = snapshotCache.object(forKey: cacheKey) {
                snapshot = cached
                return
            }
            snapshot = await renderSnapshot()
        }
    }

    @MainActor
    private func renderSnapshot() async -> UIImage? {
        guard !coordinates.isEmpty else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = snapshotRegion(for: coordinates)
        options.size = CGSize(
            width: UIScreen.main.bounds.width - Spacing.lg * 2,
            height: MapSize.cardMapHeight
        )
        options.scale = UIScreen.main.scale
        guard let result = try? await MKMapSnapshotter(options: options).start() else { return nil }
        snapshotCache.setObject(result.image, forKey: cacheKey)
        return result.image
    }

    private func snapshotRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        if coords.count == 1 {
            return MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.002),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.002)
            )
        )
    }
}
