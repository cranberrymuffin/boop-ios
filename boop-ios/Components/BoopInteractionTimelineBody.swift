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
                        title: interaction.displayTitle,
                        staticLabel: interaction.location.isEmpty ? nil : interaction.location,
                        timestamp: interaction.timestamp,
                        boopCount: interaction.boopCount
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
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var remotePhotos: [RemotePhoto] = []
    @State private var isLoadingRemotePhotos = false
    @State private var isEditing = false
    @State private var editNotes: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoSourceSheet = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var photoViewerItem: PhotoViewerItem? = nil
    @State private var isGridExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                InteractionContentView(interaction: interaction) {
                    InteractionPathMapView(coordinates: interaction.pathCoordinates)
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
        .onAppear {
            if DeepLinkState.shared.pendingCameraInteractionID == interaction.id {
                DeepLinkState.shared.pendingCameraInteractionID = nil
                showCamera = true
            }
        }
        .task {
            print("[Detail] opened interaction \(interaction.id.uuidString.prefix(8)), supabaseInteractionID: \(interaction.supabaseInteractionID?.uuidString.prefix(8) ?? "nil")")
            await fetchRemotePhotos()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { interaction.notes = editNotes }
                    else { editNotes = interaction.notes ?? "" }
                    isEditing.toggle()
                }
                .foregroundColor(.accentPrimary)
            }
        }
        .sheet(isPresented: $showPhotoSourceSheet) {
            VStack(spacing: 0) {
                Button {
                    showPhotoSourceSheet = false
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.lg)
                        .foregroundColor(.textPrimary)
                }
                Divider()
                Button {
                    showPhotoSourceSheet = false
                    showPhotoPicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.lg)
                        .foregroundColor(.textPrimary)
                }
            }
            .background(Color.backgroundSecondary)
            .presentationDetents([.height(140)])
            .presentationDragIndicator(.visible)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { data in
                addPhoto(data: data)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $photoViewerItem) { item in
            PhotoViewerView(
                imageDataList: interaction.imageData + remotePhotos.map { $0.data },
                initialIndex: item.index
            )
        }
        .task(id: selectedPhotoItems) {
            let items = selectedPhotoItems
            guard !items.isEmpty else { return }
            await withTaskGroup(of: Data?.self) { group in
                for item in items {
                    group.addTask { try? await item.loadTransferable(type: Data.self) }
                }
                for await data in group {
                    if let data { addPhoto(data: data) }
                }
            }
            selectedPhotoItems = []
        }
    }

    // MARK: - Photos Section

    private let photoGridColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3)
    private let maxCollapsedPhotos = 9

    @ViewBuilder
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Photos")
                    .heading3Style()
                if isLoadingRemotePhotos {
                    ProgressView().scaleEffect(0.7)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)

            let localPhotos = interaction.imageData
            let localMeta = interaction.photoMetadata
            let totalCount = localPhotos.count + remotePhotos.count
            let maxVisible = maxCollapsedPhotos
            let localVisible = isGridExpanded ? localPhotos.count : min(localPhotos.count, maxVisible)
            let remoteVisible = isGridExpanded ? remotePhotos : Array(remotePhotos.prefix(max(0, maxVisible - localPhotos.count)))

            LazyVGrid(columns: photoGridColumns, spacing: Spacing.sm) {
                Button { showPhotoSourceSheet = true } label: {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.formBackgroundInactive)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundColor(.textMuted)
                        }
                }

                // Local photos (yours + restored from backup)
                ForEach(0..<localVisible, id: \.self) { index in
                    if index < localPhotos.count, let uiImage = UIImage(data: localPhotos[index]) {
                        let meta = index < localMeta.count ? localMeta[index] : nil
                        let isPending = meta?.storagePath == nil && meta != nil && supabase.session != nil
                        let isTheirPhoto = meta?.uploadedByUserID != supabase.session?.user.id.uuidString && meta != nil
                        ZStack(alignment: .topTrailing) {
                            Button {
                                photoViewerItem = PhotoViewerItem(index: index)
                            } label: {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minWidth: 0, maxWidth: .infinity,
                                           minHeight: 0, maxHeight: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                            }
                            .disabled(isEditing)

                            if isEditing {
                                Button { deleteLocalPhoto(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.statusError)
                                        .background(Circle().fill(Color.white))
                                }
                                .offset(x: 4, y: -4)
                            } else if isTheirPhoto {
                                contactInitialBadge
                            } else if isPending {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(.white, Color.accentPrimary)
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .aspectRatio(1, contentMode: .fill)
                    }
                }

                // Remote photos (theirs) — not deletable
                ForEach(remoteVisible) { photo in
                    if let uiImage = UIImage(data: photo.data) {
                        ZStack(alignment: .topTrailing) {
                            Button {
                                let remoteIndex = remotePhotos.firstIndex(where: { $0.id == photo.id }) ?? 0
                                photoViewerItem = PhotoViewerItem(index: localPhotos.count + remoteIndex)
                            } label: {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minWidth: 0, maxWidth: .infinity,
                                           minHeight: 0, maxHeight: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                            }
                            .disabled(isEditing)

                            contactInitialBadge
                        }
                        .aspectRatio(1, contentMode: .fill)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)

            if totalCount > maxVisible {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { isGridExpanded.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(isGridExpanded ? "Show less" : "Show \(totalCount - maxVisible) more")
                            .font(.subtitle)
                        Image(systemName: isGridExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private var contactInitialBadge: some View {
        if let contact = interaction.contact, let initial = contact.displayName.first {
            let color = contact.gradientColorsData.first.flatMap { Contact.stringToColor($0) } ?? Color.accentPrimary
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(
                    Text(String(initial))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
                .offset(x: 4, y: -4)
        }
    }

    private func addPhoto(data: Data) {
        let index = interaction.imageData.count
        interaction.imageData.append(data)
        var meta = interaction.photoMetadata
        meta.append(PhotoMeta(storagePath: nil, uploadedByUserID: supabase.session?.user.id.uuidString ?? "local"))
        interaction.photoMetadata = meta

        guard let bleUUID = interaction.contact?.uuid, supabase.session != nil else { return }
        Task {
            if let path = await SupabaseManager.shared.uploadInteractionPhoto(
                data: data,
                contactBLEUUID: bleUUID,
                interactionDate: interaction.timestamp,
                supabaseInteractionID: interaction.supabaseInteractionID
            ) {
                var updatedMeta = interaction.photoMetadata
                if index < updatedMeta.count {
                    updatedMeta[index].storagePath = path
                    interaction.photoMetadata = updatedMeta
                }
            }
        }
    }

    private func deleteLocalPhoto(at index: Int) {
        guard index < interaction.imageData.count else { return }
        var meta = interaction.photoMetadata
        let removedMeta = index < meta.count ? meta.remove(at: index) : nil
        interaction.photoMetadata = meta
        interaction.imageData.remove(at: index)

        if let path = removedMeta?.storagePath {
            Task { await SupabaseManager.shared.deleteInteractionPhoto(storagePath: path) }
        }
    }

    private func fetchRemotePhotos() async {
        guard let bleUUID = interaction.contact?.uuid, supabase.session != nil else { return }
        let myID = supabase.session?.user.id
        isLoadingRemotePhotos = true
        defer { isLoadingRemotePhotos = false }

        let rows = await SupabaseManager.shared.fetchInteractionPhotoRows(
            contactBLEUUID: bleUUID,
            interactionDate: interaction.timestamp,
            supabaseInteractionID: interaction.supabaseInteractionID
        )
        let localPaths = Set(interaction.photoMetadata.compactMap { $0.storagePath })
        let theirRows = rows.filter { $0.uploadedBy != myID && !localPaths.contains($0.storagePath) }
        let myMissingRows = rows.filter { $0.uploadedBy == myID && !localPaths.contains($0.storagePath) }
        print("[Detail] photo split — total: \(rows.count), localPaths: \(localPaths.count), theirRows: \(theirRows.count), myMissing: \(myMissingRows.count)")

        var fetched: [RemotePhoto] = []
        await withTaskGroup(of: RemotePhoto?.self) { group in
            for row in theirRows {
                group.addTask {
                    guard let data = await SupabaseManager.shared.downloadPhoto(storagePath: row.storagePath) else { return nil }
                    return RemotePhoto(id: row.id, data: data, storagePath: row.storagePath)
                }
            }
            for await photo in group {
                if let photo { fetched.append(photo) }
            }
        }
        print("[Detail] photo fetch done — fetched: \(fetched.count), localImageData: \(interaction.imageData.count)")
        remotePhotos = fetched

        // Restore own photos that are in Supabase but missing locally (e.g. after reinstall).
        for row in myMissingRows {
            guard let data = await SupabaseManager.shared.downloadPhoto(storagePath: row.storagePath) else { continue }
            interaction.imageData.append(data)
            var meta = interaction.photoMetadata
            meta.append(PhotoMeta(storagePath: row.storagePath, uploadedByUserID: row.uploadedBy.uuidString))
            interaction.photoMetadata = meta
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

private struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let index: Int
}

private struct RemotePhoto: Identifiable {
    let id: UUID
    let data: Data
    let storagePath: String
}

// MARK: - Camera Picker

private struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.showsCameraControls = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo Viewer

private struct PhotoViewerView: View {
    let imageDataList: [Data]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(imageDataList: [Data], initialIndex: Int) {
        self.imageDataList = imageDataList
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(imageDataList.enumerated()), id: \.offset) { index, data in
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: imageDataList.count > 1 ? .always : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, Color.black.opacity(0.4))
                    .padding(.top, Spacing.xl)
                    .padding(.trailing, Spacing.lg)
            }
        }
    }
}
