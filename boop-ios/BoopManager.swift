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
    @Published var latestBoopInteraction: BoopInteraction? = nil
    @Published var nearbyDeviceNames: [UUID: String] = [:]
    @Published var nearbyDistances: [UUID: Float] = [:]
    @Published var nearbyDevicePositions: [UUID: DevicePositionCategory] = [:]
    @Published var connectedPeripheralIDs: Set<UUID> = []

    /// Map peripheral UUIDs to sender's local UUIDs
    private var peripheralToSenderUUID: [UUID: UUID] = [:]

    // MARK: - Session Tracking
    /// When each peripheral's BLE session started
    private var deviceSessionStart: [UUID: Date] = [:]
    /// The single interaction created for each active BLE session (peripheral UUID → interaction)
    private var activeSessionInteraction: [UUID: BoopInteraction] = [:]
    /// Minimum session duration (seconds) to auto-create a boop on disconnect
    private let minimumSessionDuration: TimeInterval = 60 // 1 minute
    /// Devices currently within touching range — boop fires on separation
    private var devicesInTouchingRange: Set<UUID> = []

    // MARK: - Dependencies
    private var bluetoothManager: BluetoothManager?
    private var locationManager: LocationManager?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var lastBoopTime: [UUID: Date] = [:]
    private let boopCooldown: TimeInterval = 5.0
    private var boopDetectionEnabled = false

    private lazy var displayName: Task<String, Error> = {
        Task {
            return ContactRepository.shared.getOwnProfile()?.displayName ?? ""
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
        let btManager = getOrCreateBluetoothManager()
        btManager.nearbyDevices
            .sink { [weak self] devices in
                guard let self = self else { return }
                self.processNearbyDevicesUpdate(devices)
            }
            .store(in: &cancellables)
        btManager.nearbyDistances
            .sink { [weak self] distances in
                guard let self = self else { return }
                self.nearbyDistances = distances
            }
            .store(in: &cancellables)
    }

    // MARK: - Nearby Device Processing

    private func processNearbyDevicesUpdate(_ devices: [UUID: DevicePositionCategory]) {
        let deviceIDs = Set(devices.keys)

        print("📊 BoopManager: nearbyDevices updated - count: \(deviceIDs.count)")
        print("📊 BoopManager: Device IDs: \(deviceIDs.map { $0.uuidString.prefix(8) })")

        nearbyDevicePositions = devices

        if boopDetectionEnabled {
            checkNearbyDevicesForBoops(devices)
            cleanUpDisconnectedDevices(currentDeviceIDs: deviceIDs)
        }

        previousPositions = devices
        previousDevices = deviceIDs
    }

    private func checkNearbyDevicesForBoops(_ devices: [UUID: DevicePositionCategory]) {
        // Track devices entering touching range
        for (deviceID, position) in devices where position == .ApproxTouching {
            if devicesInTouchingRange.insert(deviceID).inserted {
                print("🤝 BoopManager: Device \(deviceID.uuidString.prefix(8)) entered touching range")
            }
        }

        // Fire boop when a tracked device leaves touching range (moved away or UWB lost)
        let separated = devicesInTouchingRange.filter { devices[$0] != .ApproxTouching }
        for deviceID in separated {
            devicesInTouchingRange.remove(deviceID)
            if let lastBoop = lastBoopTime[deviceID],
               Date().timeIntervalSince(lastBoop) < boopCooldown {
                print("⏳ BoopManager: Skipping boop for \(deviceID.uuidString.prefix(8)) - cooldown active")
                continue
            }
            print("🤝 BoopManager: Device \(deviceID.uuidString.prefix(8)) separated after touching - sending boop")
            lastBoopTime[deviceID] = Date()
            Task {
                _ = await self.sendBluetoothMessage(deviceId: deviceID, messageType: .boop)
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
        disableBoopDetection()
        cancellables.removeAll()
        nearbyDeviceNames.removeAll()
        nearbyDistances.removeAll()
        nearbyDevicePositions.removeAll()
        connectedPeripheralIDs.removeAll()
        bluetoothManager?.stop()
    }

    /// Enable boop detection — call when the Boop tab appears.
    func enableBoopDetection() {
        boopDetectionEnabled = true
    }

    /// Disable boop detection — call when the Boop tab disappears.
    /// Clears touching-range state so stale positions don't fire a boop on re-enable.
    func disableBoopDetection() {
        boopDetectionEnabled = false
        devicesInTouchingRange.removeAll()
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
        nearbyDeviceNames[peripheralUUID] = displayName
        peripheralToSenderUUID[peripheralUUID] = senderUUID

        // Simulate receiving profile data so the contact can be created on disconnect
        let colors: [Color] = [.purple, .blue, .purple, .blue, .purple, .blue, .purple, .blue, .purple]
        let boop = Boop(senderUUID: senderUUID, displayName: displayName, birthday: nil, bio: nil, gradientColors: colors)
        let event = BoopEvent(boop: boop)
        handleBoopReceived(boop: boop, event: event, peripheralUUID: peripheralUUID)
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

    /// Handle a received boop: find or create today's interaction, broadcast event.
    private func handleBoopReceived(boop: Boop, event: BoopEvent, peripheralUUID: UUID) {
        let contactRepo = ContactRepository.shared

        guard let contact = contactRepo.findOrCreate(
            uuid: boop.senderUUID,
            displayName: boop.displayName,
            birthday: boop.birthday,
            bio: boop.bio,
            gradientColors: boop.gradientColors
        ) else { return }

        Task {
            await SupabaseManager.shared.recordBoopConnection(
                withBLEDeviceUUID: boop.senderUUID,
                lastBoopedAt: event.timestamp
            )
            await SupabaseManager.shared.fetchAndSaveAvatar(
                forBLEDeviceUUID: boop.senderUUID,
                into: contact
            )
        }

        let interactionRepo = BoopInteractionRepository.shared

        // Same BLE session already has an interaction — refresh live activity only.
        if let existing = activeSessionInteraction[peripheralUUID] {
            print("↩️ BoopManager: Session already has interaction \(existing.id) — refreshing live activity")
            latestBoopInteraction = existing
            LiveActivityManager.shared.refreshBoopLiveActivity(
                contactName: boop.displayName,
                contactID: boop.senderUUID,
                interactionID: existing.id
            )
            return
        }

        // Reuse an existing interaction from today for this contact.
        if let todayInteraction = interactionRepo.findToday(forContactUUID: boop.senderUUID) {
            interactionRepo.incrementBoopCount(todayInteraction)
            print("📅 BoopManager: Reusing today's interaction \(todayInteraction.id) for \(boop.senderUUID.uuidString.prefix(8)) (boopCount: \(todayInteraction.boopCount))")
            activeSessionInteraction[peripheralUUID] = todayInteraction
            latestBoopInteraction = todayInteraction
            LiveActivityManager.shared.refreshBoopLiveActivity(
                contactName: boop.displayName,
                contactID: boop.senderUUID,
                interactionID: todayInteraction.id
            )
            return
        }

        // No interaction yet today — create one.
        let locationName = locationManager?.currentLocationName ?? ""

        guard let interaction = interactionRepo.create(
            location: locationName,
            timestamp: event.timestamp,
            contact: contact
        ) else { return }

        activeSessionInteraction[peripheralUUID] = interaction
        latestBoopInteraction = interaction

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

        // Get location data for the session; fall back to current position if device didn't move
        var pathCoords = locationManager?.getLocations(from: sessionStart, to: now) ?? []
        if pathCoords.isEmpty, let coord = locationManager?.currentCoordinate() {
            pathCoords = [coord]
        }

        // Use the interaction created at first boop this session, or fall back to latest
        let existingInteraction = activeSessionInteraction[peripheralUUID]
            ?? interactionRepo.findLatest(forContactUUID: senderUUID)

        if let existingInteraction {
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
                    _ = interactionRepo.create(
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
        activeSessionInteraction.removeValue(forKey: peripheralUUID)
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
            let profile = ContactRepository.shared.getOwnProfile()
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
        guard boopDetectionEnabled else {
            print("⏭️ BoopManager: Ignoring boop from \(peripheralUUID.uuidString.prefix(8)) - not on Boop screen")
            return
        }
        print("🎉 BoopManager: Received boop from sender: \(senderUUID.uuidString.prefix(8)), peripheral: \(peripheralUUID.uuidString.prefix(8)), displayName: '\(displayName)'")

        // Store mapping
        peripheralToSenderUUID[peripheralUUID] = senderUUID
        nearbyDeviceNames[peripheralUUID] = displayName

        // Convert gradient color strings to Color objects
        let colors = gradientColors.compactMap { Contact.stringToColor($0) }

        // Create boop object with profile data
        let boop = Boop(senderUUID: senderUUID, displayName: displayName, birthday: birthday, bio: bio, gradientColors: colors)
        let event = BoopEvent(boop: boop)

        // Persist the boop
        handleBoopReceived(boop: boop, event: event, peripheralUUID: peripheralUUID)

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
        nearbyDeviceNames[peripheralUUID] = displayName
    }

    func didDeviceConnect(peripheralUUID: UUID) {
        print("🔗 BoopManager: Device connected - \(peripheralUUID.uuidString.prefix(8))")
        connectedPeripheralIDs.insert(peripheralUUID)
        deviceSessionStart[peripheralUUID] = Date()
        activeSessionInteraction.removeValue(forKey: peripheralUUID)
    }

    func didDeviceDisconnect(peripheralUUID: UUID) {
        print("🔌 BoopManager: Device disconnected - \(peripheralUUID.uuidString.prefix(8))")
        connectedPeripheralIDs.remove(peripheralUUID)
        nearbyDeviceNames.removeValue(forKey: peripheralUUID)
        handleSessionEnd(peripheralUUID: peripheralUUID)
    }
    
    func didDisableBle() {
        bluetoothManager?.stop()
        for (peripheral, starttime) in lastBoopTime {
            handleSessionEnd(peripheralUUID: peripheral)
        }
    }
}
