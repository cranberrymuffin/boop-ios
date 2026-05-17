//
//  BoopInteractionTimelineBody.swift
//  boop-ios
//
//  Compact time-grouped interaction list (used by contact history views).
//  For the full-detail home feed, see HomeFeedBody.
//

import PhotosUI
import SwiftUI

// MARK: - Compact List Body (used by ContactDetailView / BoopHistoryView)

struct BoopInteractionTimelineBody: View {
    let interactions: [BoopInteraction]

    var body: some View {
        LazyVStack(spacing: Spacing.sm) {
            ForEach(Array(interactions.enumerated()), id: \.element.id) { index, interaction in
                let currentHeader = interaction.timestamp.relativeGroupHeader()
                let previousHeader = index > 0 ? interactions[index - 1].timestamp.relativeGroupHeader() : nil

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

// MARK: - Full Detail View (used by navigation destinations)

struct InteractionDetailView: View {
    @Bindable var interaction: BoopInteraction
    @State private var isEditing = false
    @State private var editEndDate: Date?
    @State private var editNotes: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                InteractionContentView(interaction: interaction) {
                    InteractionPathMapView(coordinates: interaction.pathCoordinates)
                }

                if isEditing {
                    DatePickerField(
                        title: "End",
                        placeholder: "When did this boop end?",
                        showTimePicker: true,
                        selectedDate: $editEndDate
                    )
                    .padding(.horizontal, Spacing.lg)
                }

                photosSection
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
}
