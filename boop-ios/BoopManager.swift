import Foundation
import CoreBluetooth
import CoreLocation
import Combine
import UIKit
import SwiftUI

// MARK: - Boop Manager
/// Manages the queue of devices that are in "boop" range (touching distance)
/// Automatically tracks devices that are ≤10cm away with aligned angles
/// Handles all boop persistence (contact creation, interaction creation, session tracking)
@MainActor
class BoopManager: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var latestBoopEvent: BoopEvent? = nil

    /// Map peripheral UUIDs to sender's local UUIDs
    private var peripheralToSenderUUID: [UUID: UUID] = [:]

    // MARK: - Session Tracking
    /// When each peripheral's BLE session started
    private var deviceSessionStart: [UUID: Date] = [:]
    /// Minimum session duration (seconds) to auto-create a boop on disconnect
    private let minimumSessionDuration: TimeInterval = 60 // 1 minute

    // MARK: - Dependencies
    private var bluetoothManager: BluetoothManager?
    private var locationManager: LocationManager?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var lastBoopTime: [UUID: Date] = [:]
    private let boopCooldown: TimeInterval = 5.0
    private let duplicateWindow: TimeInterval = 3

    private lazy var displayName: Task<String, Error> = {
        Task {
            if let profile = UserProfileRepository.shared.getCurrent() {
                return profile.name
            }
            return ""
        }
    }()

    // MARK: - Init
    override init() {
        super.init()
    }

    // MARK: - Configuration

    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
    }

    private func getOrCreateBluetoothManager() -> BluetoothManager {
        if let manager = bluetoothManager {
            return manager
        }

        let manager = BluetoothManager()
        manager.setBoopDelegate(self)
        bluetoothManager = manager
        return manager
    }

    // MARK: - Setup
    private var previousDevices = Set<UUID>()
    private var previousPositions: [UUID: DevicePositionCategory] = [:]

    private func setupObservers() {
        getOrCreateBluetoothManager().nearbyDevices
            .sink { [weak self] devices in
                guard let self = self else { return }
                self.processNearbyDevicesUpdate(devices)
            }
            .store(in: &cancellables)
    }

    // MARK: - Nearby Device Processing

    private func processNearbyDevicesUpdate(_ devices: [UUID: DevicePositionCategory]) {
        let deviceIDs = Set(devices.keys)

        print("📊 BoopManager: nearbyDevices updated - count: \(deviceIDs.count)")
        print("📊 BoopManager: Device IDs: \(deviceIDs.map { $0.uuidString.prefix(8) })")

        checkNearbyDevicesForBoops(devices)
        cleanUpDisconnectedDevices(currentDeviceIDs: deviceIDs)

        previousPositions = devices
        previousDevices = deviceIDs
    }

    private func checkNearbyDevicesForBoops(_ devices: [UUID: DevicePositionCategory]) {
        for (deviceID, position) in devices {
            if position == .ApproxTouching && previousPositions[deviceID] != .ApproxTouching {
                if let lastBoop = lastBoopTime[deviceID],
                   Date().timeIntervalSince(lastBoop) < boopCooldown {
                    print("⏳ BoopManager: Skipping auto-boop for \(deviceID.uuidString.prefix(8)) - cooldown active")
                    continue
                }
                print("🤝 BoopManager: Device \(deviceID.uuidString.prefix(8)) entered touching range - sending boop")
                lastBoopTime[deviceID] = Date()
                Task {
                    _ = await self.sendBluetoothMessage(deviceId: deviceID, messageType: .boop)
                }
            }
        }
    }

    private func cleanUpDisconnectedDevices(currentDeviceIDs: Set<UUID>) {
        var allDevices = Set(lastBoopTime.keys)
        
        var disconnectedPeripherals = allDevices.subtracting(currentDeviceIDs)
        lastBoopTime = lastBoopTime.filter { currentDeviceIDs.contains($0.key)
        }
        
        for peripheral in disconnectedPeripherals {
            handleSessionEnd(peripheralUUID: peripheral)
        }
    }

    func start() {
        _ = getOrCreateBluetoothManager()
        setupObservers()
        bluetoothManager?.start()
    }

    func stop() {
        cancellables.removeAll()
        bluetoothManager?.stop()
    }

    // MARK: - Public Methods

    /// Get nearby devices with their display info
    func getNearbyDevices() -> [UUID: DevicePositionCategory] {
        return bluetoothManager?.getNearbyDevices() ?? [:]
    }

    // MARK: - Simulation (Debug)

    /// Tracks the simulated peripheral UUID so we can disconnect it later.
    @Published var simulatedPeripheralUUID: UUID? = nil

    /// Simulate a BLE device connecting. Call `simulateDisconnect()` to end the session.
    /// If `autoDisconnectAfter` is provided, disconnects automatically after that many seconds.
    func simulateDeviceConnect(displayName: String = "Simulated Friend", autoDisconnectAfter: TimeInterval? = nil) {
        let peripheralUUID = UUID()
        let senderUUID = UUID()

        simulatedPeripheralUUID = peripheralUUID
        peripheralToSenderUUID[peripheralUUID] = senderUUID

        // Simulate receiving profile data so the contact can be created on disconnect
        let colors: [Color] = [.purple, .blue, .purple, .blue, .purple, .blue, .purple, .blue, .purple]
        let boop = Boop(senderUUID: senderUUID, displayName: displayName, birthday: nil, bio: nil, gradientColors: colors)
        let event = BoopEvent(boop: boop)
        handleBoopReceived(boop: boop, event: event)
        latestBoopEvent = event

        // Start the session
        didDeviceConnect(peripheralUUID: peripheralUUID)

        print("🧪 BoopManager: Simulated device connect - peripheral: \(peripheralUUID.uuidString.prefix(8)), sender: \(senderUUID.uuidString.prefix(8))")

        if let delay = autoDisconnectAfter {
            print("🧪 BoopManager: Auto-disconnect scheduled in \(Int(delay))s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.simulateDisconnect()
            }
        }
    }

    /// Manually disconnect the simulated device.
    func simulateDisconnect() {
        guard let peripheralUUID = simulatedPeripheralUUID else {
            print("🧪 BoopManager: No simulated device to disconnect")
            return
        }
        print("🧪 BoopManager: Simulated device disconnect - \(peripheralUUID.uuidString.prefix(8))")
        simulatedPeripheralUUID = nil
        didDeviceDisconnect(peripheralUUID: peripheralUUID)
    }

    // MARK: - Persistence

    /// Handle a received boop: create contact + interaction, broadcast event.
    private func handleBoopReceived(boop: Boop, event: BoopEvent) {
        let interactionRepo = BoopInteractionRepository.shared
        let contactRepo = ContactRepository.shared

        guard !interactionRepo.isDuplicate(contactUUID: boop.senderUUID, displayName: boop.displayName, timestamp: event.timestamp, window: duplicateWindow) else {
            print("⏭️ BoopManager: Skipping duplicate interaction for \(boop.senderUUID.uuidString.prefix(8))")
            return
        }

        guard let contact = contactRepo.findOrCreate(
            uuid: boop.senderUUID,
            displayName: boop.displayName,
            birthday: boop.birthday,
            bio: boop.bio,
            gradientColors: boop.gradientColors
        ) else { return }

        let locationName = locationManager?.currentLocationName ?? ""

        guard let interaction = interactionRepo.create(
            title: boop.displayName,
            location: locationName,
            timestamp: event.timestamp,
            contact: contact
        ) else { return }

        LiveActivityManager.shared.startBoopLiveActivity(
            contactName: boop.displayName,
            contactID: boop.senderUUID,
            interactionID: interaction.id
        )
    }

    // MARK: - Session End Handling

    private func handleSessionEnd(peripheralUUID: UUID) {
        let now = Date()
        let interactionRepo = BoopInteractionRepository.shared
        let contactRepo = ContactRepository.shared

        guard let sessionStart = deviceSessionStart[peripheralUUID] else {
            print("⚠️ BoopManager: No session start for \(peripheralUUID.uuidString.prefix(8))")
            return
        }

        let sessionDuration = now.timeIntervalSince(sessionStart)
        let senderUUID = peripheralToSenderUUID[peripheralUUID]

        print("📍 BoopManager: Session ended for \(peripheralUUID.uuidString.prefix(8)) - duration: \(Int(sessionDuration))s")

        guard let senderUUID else {
            print("⚠️ BoopManager: No sender UUID mapped for peripheral \(peripheralUUID.uuidString.prefix(8))")
            deviceSessionStart.removeValue(forKey: peripheralUUID)
            return
        }

        // Get location data for the session
        let pathCoords = locationManager?.getLocations(from: sessionStart, to: now) ?? []

        // Try to find an existing interaction created during this session (from a proximity boop)
        if let existingInteraction = interactionRepo.findLatest(forContactUUID: senderUUID) {
            guard existingInteraction.endTimestamp == nil else {
                print("Boop Manager: Attempted to end a session that has already ended")
                return
            }
            // Enrich the existing boop with session data
            if existingInteraction.location.isEmpty, let locationManager {
                Task {
                    let name = await locationManager.reverseGeocodeCurrentLocation()
                    interactionRepo.enrichWithSessionData(
                        existingInteraction,
                        endTimestamp: now,
                        pathCoordinates: pathCoords,
                        location: name
                    )
                }
            } else {
                interactionRepo.enrichWithSessionData(
                    existingInteraction,
                    endTimestamp: now,
                    pathCoordinates: pathCoords
                )
            }
            print("✅ BoopManager: Updated existing interaction with session data (path: \(pathCoords.count) points)")
        } else if sessionDuration >= minimumSessionDuration {
            // No boop happened but session was long enough — auto-create one
            Task {
                let locationName: String
                if let locationManager {
                    locationName = await locationManager.reverseGeocodeCurrentLocation()
                } else {
                    locationName = ""
                }

                if let contact = contactRepo.findOrCreate(uuid: senderUUID, displayName: "Simulated Friend", birthday: nil, bio: nil, gradientColors: []) {
                    let displayName = contact.displayName
                    _ = interactionRepo.create(
                        title: displayName,
                        location: locationName,
                        timestamp: sessionStart,
                        endTimestamp: now,
                        contact: contact,
                        pathCoordinates: pathCoords
                    )
                    print("✅ BoopManager: Auto-created interaction for long session (\(Int(sessionDuration))s, path: \(pathCoords.count) points)")
                }
            }
        } else {
            print("⏭️ BoopManager: Session too short (\(Int(sessionDuration))s < \(Int(minimumSessionDuration))s) - skipping auto-create")
        }

        // Clean up session state
        deviceSessionStart.removeValue(forKey: peripheralUUID)
    }

    // MARK: - BLE Messaging

    private func sendBluetoothMessage(deviceId: UUID,
                                      messageType: BluetoothMessage.MessageType) async -> Bool {
        guard let bluetoothManager else {
            print("⚠️ BoopManager: Bluetooth manager not initialized")
            return false
        }
        do {
            // Get user profile data
            let profile = UserProfileRepository.shared.getCurrent()
            let message = BluetoothMessage(
                senderUUID: bluetoothManager.getLocalDeviceUUID(),
                messageType: messageType,
                displayName: try await self.displayName.value,
                birthday: profile?.birthday,
                bio: profile?.bio,
                gradientColors: profile?.gradientColorsData ?? []
            )
            print("Boop: Sending BLE Message with profile data")
            bluetoothManager.sendMessage(message, to: deviceId)
            return true
        } catch {
            print("\(error.localizedDescription) occured")
            return false
        }
    }
}

// MARK: - BoopDelegate

extension BoopManager: BoopDelegate {
    func didReceiveBoop(from senderUUID: UUID, peripheralUUID: UUID, displayName: String, birthday: Date?, bio: String?, gradientColors: [String]) {
        print("🎉 BoopManager: Received boop from sender: \(senderUUID.uuidString.prefix(8)), peripheral: \(peripheralUUID.uuidString.prefix(8)), displayName: '\(displayName)'")

        // Store mapping
        peripheralToSenderUUID[peripheralUUID] = senderUUID

        // Convert gradient color strings to Color objects
        let colors = gradientColors.compactMap { Contact.stringToColor($0) }

        // Create boop object with profile data
        let boop = Boop(senderUUID: senderUUID, displayName: displayName, birthday: birthday, bio: bio, gradientColors: colors)
        let event = BoopEvent(boop: boop)

        // Persist the boop
        handleBoopReceived(boop: boop, event: event)

        // Broadcast event for UI
        latestBoopEvent = event

        if let lastBoop = lastBoopTime[peripheralUUID],
           Date().timeIntervalSince(lastBoop) < boopCooldown {
            print("⏳ BoopManager: Skipping send-back boop to \(peripheralUUID.uuidString.prefix(8)) - cooldown active")
        } else {
            
            // Send a boop back so the sender also gets the record.
            print("↩️ BoopManager: Sending boop back to \(peripheralUUID.uuidString.prefix(8))")
            lastBoopTime[peripheralUUID] = Date()
            Task {
                _ = await self.sendBluetoothMessage(deviceId: peripheralUUID, messageType: .boop)
            }
        }
    }

    func didReceiveBoopRequest(from senderUUID: UUID, peripheralUUID: UUID, displayName: String, birthday: Date?, bio: String?, gradientColors: [String]) {
        print("📨 BoopManager: Received boop request from sender: \(senderUUID.uuidString.prefix(8)), peripheral: \(peripheralUUID.uuidString.prefix(8)), displayName: '\(displayName)'")

        // Store mapping
        peripheralToSenderUUID[peripheralUUID] = senderUUID
    }

    func didDeviceConnect(peripheralUUID: UUID) {
        print("🔗 BoopManager: Device connected - \(peripheralUUID.uuidString.prefix(8))")
        deviceSessionStart[peripheralUUID] = Date()
    }

    func didDeviceDisconnect(peripheralUUID: UUID) {
        print("🔌 BoopManager: Device disconnected - \(peripheralUUID.uuidString.prefix(8))")
        handleSessionEnd(peripheralUUID: peripheralUUID)
    }
    
    func didDisableBle() {
        bluetoothManager?.stop()
        for (peripheral, starttime) in lastBoopTime {
            handleSessionEnd(peripheralUUID: peripheral)
        }
    }
}
