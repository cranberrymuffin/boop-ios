//
//  BoopInteractionTimelineBody.swift
//  boop-ios
//
//  Reusable time-grouped interaction list and detail view.
//  Place BoopInteractionTimelineBody inside a ScrollView that lives
//  within a NavigationStack or NavigationView.
//

import SwiftUI
import _MapKit_SwiftUI

// MARK: - Shared List Body

struct BoopInteractionTimelineBody: View {
    let interactions: [BoopInteraction]

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    private func getFormattedTimestamp(for date: Date) -> String {
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date()).capitalized
    }
    
    private func headerText(for date: Date) -> String {
        let text = getFormattedTimestamp(for: date)
        let sanitized = text.trimmingCharacters(in: .whitespaces).lowercased()
        let words = sanitized.components(separatedBy: .whitespaces)
        if words.contains(where: {$0.contains("minute")})
        {
            return "Last Hour"
        }
        if words.contains(where: {$0.contains("hour") }) {
            return "Today"
        }
        return text.capitalized
    }

    var body: some View {
        LazyVStack(spacing: Spacing.sm) {
            ForEach(Array(interactions.enumerated()), id: \.element.id) { index, interaction in
                let currentHeader = headerText(for: interaction.timestamp)
                let previousHeader = index > 0 ? headerText(for: interactions[index - 1].timestamp) : nil

                if previousHeader != currentHeader {
                    Text(currentHeader)
                        .heading1Style()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                }

                NavigationLink(value: interaction) {
                    BoopInteractionCard(interaction: interaction)
                }
                .padding(.horizontal, Spacing.lg)
                .id(interaction.id)
            }
        }
    }
}

// MARK: - Shared Detail View

struct BoopInteractionDetailView: View {
    let interaction: BoopInteraction
    
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    private func getFormattedTimestamp(for date: Date) -> String {
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date()).capitalized
    }
    
    private func getInteractionSubtitleText() -> String {
        var interactionSubtitleArr: [String] = []
        let formattedStart = getFormattedTimestamp(for: interaction.timestamp)
        interactionSubtitleArr.append(formattedStart)
        
        let formattedEnd = interaction.endTimestamp != nil ?
        getFormattedTimestamp(for: interaction.endTimestamp ?? Date()) : nil
        
        if formattedEnd != nil && formattedEnd != formattedStart {
            interactionSubtitleArr.append("-")
            interactionSubtitleArr.append(formattedEnd!)
        }
        
        if !interaction.location.isEmpty {
            interactionSubtitleArr.append("•")
            interactionSubtitleArr.append(interaction.location)
        }
        return interactionSubtitleArr.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(interaction.title)
                .heading2Style()

            Text(getInteractionSubtitleText())
                .heading3Style()
            
            if !interaction.pathCoordinates.isEmpty {
                pathMapView(coordinates: interaction.pathCoordinates)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .navigationTitle("Boop Detail")
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
    }
    
    // MARK: - Map View

    fileprivate func mapPin(_ pinPoint: CLLocationCoordinate2D) -> Annotation<Text, some View> {
        return Annotation("", coordinate: pinPoint) {
            Circle()
                .fill(.accentPrimary)
                .frame(width: MapSize.pinRadius, height: MapSize.pinRadius)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: MapSize.pinBorderWidth)
                )
        }
    }
    
    @ViewBuilder
    private func pathMapView(coordinates: [CLLocationCoordinate2D]) -> some View {
        Map(initialPosition: mapCameraPosition(for: coordinates), interactionModes: []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.accentPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            
            if let startPoint = coordinates.first {
                mapPin(startPoint)
            }
            
            if let endPoint = coordinates.last {
                mapPin(endPoint)
            }
            
        }
        .frame(height: MapSize.cardMapHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: CornerRadius.md,
                bottomLeadingRadius: CornerRadius.md,
                bottomTrailingRadius: CornerRadius.md,
                topTrailingRadius: CornerRadius.md
            )
        )
        .allowsHitTesting(false)
    }
    
    private func mapCameraPosition(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coordinates.isEmpty else { return .automatic }

        if coordinates.count == 1 {
            return .region(MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }

        let minLat = coordinates.map(\.latitude).min()!
        let maxLat = coordinates.map(\.latitude).max()!
        let minLon = coordinates.map(\.longitude).min()!
        let maxLon = coordinates.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.002),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.002)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}
