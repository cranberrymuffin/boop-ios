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

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.accentPrimary)

                Text("Tap to boop")
                    .subtitleStyle()
                Spacer()

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
            .onChange(of: boopManager.latestBoopEvent) { _, newValue in
                guard let event = newValue, !showBoop else { return }
                showBoopOverlay(displayName: event.boop.displayName)
            }
        }
    }

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
