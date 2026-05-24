//
//  BoopRangingView.swift
//  boop-ios
//
//  Handles Bluetooth ranging/scanning UI overlay for boops.
//  All persistence is handled by BoopManager.
//

import SwiftUI

struct BoopRangingView: View {
    var isPresented: Binding<Bool>?
    @EnvironmentObject var boopManager: BoopManager

    @State private var showBoop = false
    @State private var currentBoopDisplayName: String = ""

    private let animationDuration: TimeInterval = 2

    // MARK: - Nearby device row model

    private struct NearbyDeviceRowData: Identifiable {
        let id: UUID
        let displayName: String
        let distanceText: String
        let zoneLabel: String
        let isUWBActive: Bool
    }

    private func makeRows() -> [NearbyDeviceRowData] {
        // Seed all BLE-connected devices as Unknown, then override with UWB data
        var devices: [UUID: DevicePositionCategory] = [:]
        for id in boopManager.connectedPeripheralIDs {
            devices[id] = .Unknown
        }
        for (uuid, category) in boopManager.nearbyDevicePositions {
            devices[uuid] = category
        }
        return devices.map { (uuid, category) in
            let name = boopManager.nearbyDeviceNames[uuid] ?? "Unknown (\(uuid.uuidString.prefix(4)))"
            let distance = boopManager.nearbyDistances[uuid]
            let distanceText: String
            if let d = distance, category != .Unknown {
                distanceText = String(format: "%.2fm", d)
            } else {
                distanceText = "—"
            }
            let zone: String = {
                switch category {
                case .ApproxTouching: return "Touching"
                case .InRange:        return "Nearby"
                case .OutOfRange:     return "Out of range"
                case .Unknown:        return "Connecting…"
                }
            }()
            let uwbActive = distance != nil && category != .Unknown
            return NearbyDeviceRowData(
                id: uuid,
                displayName: name,
                distanceText: distanceText,
                zoneLabel: zone,
                isUWBActive: uwbActive
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                let rows = makeRows()
                if rows.isEmpty {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.accentPrimary)
                    Text("Tap to boop")
                        .subtitleStyle()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(rows) { row in
                                nearbyDeviceRow(row)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.md)
                    }
                }

                #if DEBUG
                debugControls
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground()
            .ignoresSafeArea(edges: .horizontal)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Boop")
                        .heading1Style()
                }
                if isPresented != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            isPresented?.wrappedValue = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: IconSize.standard, weight: .semibold))
                                .foregroundColor(.accentPrimary)
                        }
                    }
                }
            }
            .overlay {
                if showBoop {
                    ZStack {
                        Color.backgroundPrimary.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: Spacing.xl) {
                            Text("Boop!")
                                .heading1Style()
                            Text(currentBoopDisplayName)
                                .heading2Style()
                        }
                        .cardStyle()
                        .padding(Spacing.lg)
                    }
                }
            }
            .animation(.easeInOut(duration: animationDuration), value: showBoop)
            .onAppear { boopManager.enableBoopDetection() }
            .onDisappear { boopManager.disableBoopDetection() }
            .onChange(of: boopManager.latestBoopEvent) { _, newValue in
                guard let event = newValue, !showBoop else { return }
                showBoopOverlay(displayName: event.boop.displayName)
            }
        }
    }

    // MARK: - Device row

    @ViewBuilder
    private func nearbyDeviceRow(_ row: NearbyDeviceRowData) -> some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(row.displayName)
                    .heading3Style()
                Text(row.zoneLabel)
                    .subtitleStyle()
                    .foregroundColor(.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(row.distanceText)
                    .heading3Style()
                    .foregroundColor(.accentPrimary)
                Text(row.isUWBActive ? "UWB active" : "BLE only")
                    .subtitleStyle()
                    .foregroundColor(row.isUWBActive ? .accentPrimary : .textMuted)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: - Boop overlay

    private func showBoopOverlay(displayName: String) {
        currentBoopDisplayName = displayName
        showBoop = true

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            showBoop = false
            isPresented?.wrappedValue = false
        }
    }

    // MARK: - Debug Controls

    #if DEBUG
    private var debugControls: some View {
        VStack(spacing: Spacing.sm) {
            Text("Debug")
                .font(.caption)
                .foregroundColor(.textMuted)

            if boopManager.simulatedPeripheralUUID != nil {
                Button("Disconnect Simulated Device") {
                    boopManager.simulateDisconnect()
                }
                .primaryButtonStyle()
            } else {
                Button("Simulate 5 min Session") {
                    boopManager.simulateDeviceConnect(
                        displayName: "Simulated Friend",
                        autoDisconnectAfter: 5 * 60
                    )
                }
                .primaryButtonStyle()

                Button("Simulate Connect (manual disconnect)") {
                    boopManager.simulateDeviceConnect(displayName: "Simulated Friend")
                }
                .primaryButtonStyle()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }
    #endif
}
