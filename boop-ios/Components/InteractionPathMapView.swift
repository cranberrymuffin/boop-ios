import MapKit
import SwiftUI

struct InteractionPathMapView: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        Map(initialPosition: cameraPosition(for: coordinates), interactionModes: []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.accentPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            if let start = coordinates.first { pin(at: start) }
            if coordinates.count > 1, let end = coordinates.last { pin(at: end) }
        }
        .frame(height: MapSize.cardMapHeight)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .allowsHitTesting(false)
    }

    private func pin(at coordinate: CLLocationCoordinate2D) -> some MapContent {
        Annotation("", coordinate: coordinate) {
            Circle()
                .fill(.accentPrimary)
                .frame(width: MapSize.pinRadius, height: MapSize.pinRadius)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: MapSize.pinBorderWidth))
        }
    }

    private func cameraPosition(for coords: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coords.isEmpty else { return .automatic }
        if coords.count == 1 {
            return .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.002),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.002)
            )
        ))
    }
}
