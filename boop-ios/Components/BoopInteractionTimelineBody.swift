//
//  BoopInteractionTimelineBody.swift
//  boop-ios
//
//  Reusable time-grouped interaction list and detail view.
//  Place BoopInteractionTimelineBody inside a ScrollView that lives
//  within a NavigationStack or NavigationView.
//

import PhotosUI
import SwiftUI
import _MapKit_SwiftUI

// MARK: - Shared List Body

struct BoopInteractionTimelineBody: View {
    let interactions: [BoopInteraction]

    private func headerText(for date: Date) -> String {
        let text = date.relativeString().capitalized
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
                    BoopListRow(
                        avatarImages: [interaction.contact?.avatarData],
                        title: interaction.title,
                        staticLabel: interaction.location.isEmpty ? nil : interaction.location,
                        timestamp: interaction.timestamp
                    )
                }
                .id(interaction.id)
            }
        }
    }
}

// MARK: - Shared Detail View

struct BoopInteractionDetailView: View {
    @Bindable var interaction: BoopInteraction
    @State private var isEditing = false
    @State private var editEndDate: Date?
    @State private var editNotes: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {

                // MARK: - Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Boop with \(interaction.title)")
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

                // MARK: - Map
                if !interaction.pathCoordinates.isEmpty {
                    pathMapView(coordinates: interaction.pathCoordinates)
                        .padding(.horizontal, Spacing.lg)
                }

                // MARK: - Edit End Time (edit mode only)
                if isEditing {
                    DatePickerField(
                        title: "End",
                        placeholder: "When did this boop end?",
                        showTimePicker: true,
                        selectedDate: $editEndDate
                    )
                    .padding(.horizontal, Spacing.lg)
                }

                // MARK: - Photos
                photosSection

                // MARK: - Notes
                notesSection
            }
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        interaction.endTimestamp = editEndDate
                        interaction.notes = editNotes
                    } else {
                        editEndDate = interaction.endTimestamp
                        editNotes = interaction.notes ?? ""
                    }
                    isEditing.toggle()
                }
                .foregroundColor(.accentPrimary)
            }
        }
        .task(id: selectedPhotoItems) {
            let items = selectedPhotoItems
            guard !items.isEmpty else { return }
            await withTaskGroup(of: Data?.self) { group in
                for item in items {
                    group.addTask { try? await item.loadTransferable(type: Data.self) }
                }
                for await data in group {
                    if let data { interaction.imageData.append(data) }
                }
            }
            selectedPhotoItems = []
        }
    }

    // MARK: - Photos Section

    @ViewBuilder
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Photos")
                    .heading3Style()
                Spacer()
                if isEditing {
                    PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                        Image(systemName: "plus")
                            .foregroundColor(.accentPrimary)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)

            if interaction.imageData.isEmpty {
                Text("No photos yet")
                    .subtitleStyle()
                    .padding(.horizontal, Spacing.lg)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(Array(interaction.imageData.enumerated()), id: \.offset) { index, data in
                            if let uiImage = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))

                                    if isEditing {
                                        Button {
                                            guard index < interaction.imageData.count else { return }
                                            interaction.imageData.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.statusError)
                                                .background(Circle().fill(Color.white))
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Notes")
                .heading3Style()
                .padding(.horizontal, Spacing.lg)

            if isEditing {
                TextEditor(text: $editNotes)
                    .font(.body)
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(Spacing.sm)
                    .background(Color.formBackgroundInactive)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                    .padding(.horizontal, Spacing.lg)
            } else {
                Text(interaction.notes?.isEmpty == false ? interaction.notes! : "No notes yet")
                    .subtitleStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
            }
        }
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
