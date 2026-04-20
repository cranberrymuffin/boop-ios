import Foundation
import CoreBluetooth
import CoreLocation
import Combine
import UIKit
import SwiftUI
import SwiftData

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
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var lastBoopTime: [UUID: Date] = [:]
    private let boopCooldown: TimeInterval = 5.0
    private let duplicateWindow: TimeInterval = 3

    private lazy var displayName: Task<String, Error> = {
        Task {
            if let profile = await UserDataStore.shared.getUserProfile() {
                return profile.displayName
            }
            return ""
        }
    }()

    // MARK: - Init
    override init() {
        super.init()
    }

    // MARK: - Configuration

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = ModelContext(container)
    }

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
        lastBoopTime = lastBoopTime.filter { currentDeviceIDs.contains($0.key) }
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

    /// Find or create a Contact for the given sender UUID and profile data.
    private func findOrCreateContact(senderUUID: UUID, displayName: String, birthday: Date?, bio: String?, gradientColors: [Color]) -> Contact? {
        guard let modelContext else {
            print("⚠️ BoopManager: ModelContext not available")
            return nil
        }

        let descriptor = FetchDescriptor<Contact>(predicate: #Predicate { $0.uuid == senderUUID })
        let existingContacts = (try? modelContext.fetch(descriptor)) ?? []

        if let existing = existingContacts.first {
            existing.displayName = displayName
            existing.birthday = birthday
            existing.bio = bio
            existing.gradientColorsData = gradientColors.map { Contact.colorToString($0) }
            return existing
        }

        let contact = Contact(
            uuid: senderUUID,
            displayName: displayName,
            birthday: birthday,
            bio: bio,
            gradientColors: gradientColors
        )
        modelContext.insert(contact)
        return contact
    }

    /// Create a BoopInteraction and associate it with a contact.
    private func createInteraction(title: String, location: String, timestamp: Date, endTimestamp: Date? = nil, contact: Contact, pathCoordinates: [CLLocationCoordinate2D] = []) -> BoopInteraction {
        let interaction = BoopInteraction(
            title: title,
            location: location,
            timestamp: timestamp,
            endTimestamp: endTimestamp,
            contact: contact,
            pathCoordinates: pathCoordinates
        )
        modelContext?.insert(interaction)
        contact.interactions.append(interaction)
        return interaction
    }

    /// Check if a duplicate interaction already exists within the duplicate window.
    private func isDuplicateInteraction(contactUUID: UUID, displayName: String, timestamp: Date) -> Bool {
        guard let modelContext else { return false }

        let windowStart = timestamp.addingTimeInterval(-duplicateWindow)
        let windowEnd = timestamp.addingTimeInterval(duplicateWindow)
        let descriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {
            $0.timestamp >= windowStart && $0.timestamp <= windowEnd
        })
        let interactions = (try? modelContext.fetch(descriptor)) ?? []
        return interactions.contains { $0.contact?.uuid == contactUUID && $0.title == displayName }
    }

    private func debugInteractionFetching(_ contactUUID: UUID, _ modelContext: ModelContext) {
        #if DEBUG
        let generalDescriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {
            $0.contact?.uuid == contactUUID
        })
        let allInteractionsForContact = (try? modelContext.fetch(generalDescriptor)) ?? []
        for interaction in allInteractionsForContact {
            print("------ boop interaction ------")
            print(interaction.id, ", ", interaction.timestamp)
        }
        print("------ boop interaction ------")
        #endif
    }
    
    
    /// Find an existing interaction for a contact within a session time window.
    private func findInteractionInSession(contactUUID: UUID, sessionStart: Date, sessionEnd: Date) -> BoopInteraction? {
        guard let modelContext else { return nil }

        let descriptor = FetchDescriptor<BoopInteraction>(predicate: #Predicate {$0.contact?.uuid == contactUUID }, sortBy: [SortDescriptor(\BoopInteraction.timestamp, order: .reverse)]
        )
        let interactions = (try? modelContext.fetch(descriptor)) ?? []
        debugInteractionFetching(contactUUID, modelContext)
        return interactions.first { $0.contact?.uuid == contactUUID }
    }

    /// Handle a received boop: create contact + interaction, broadcast event.
    private func handleBoopReceived(boop: Boop, event: BoopEvent) {
        guard isDuplicateInteraction(contactUUID: boop.senderUUID, displayName: boop.displayName, timestamp: event.timestamp) == false else {
            print("⏭️ BoopManager: Skipping duplicate interaction for \(boop.senderUUID.uuidString.prefix(8))")
            return
        }

        guard let contact = findOrCreateContact(
            senderUUID: boop.senderUUID,
            displayName: boop.displayName,
            birthday: boop.birthday,
            bio: boop.bio,
            gradientColors: boop.gradientColors
        ) else { return }

        let locationName = locationManager?.currentLocationName ?? ""

        let interaction = createInteraction(
            title: boop.displayName,
            location: locationName,
            timestamp: event.timestamp,
            contact: contact
        )

        try? modelContext?.save()

        LiveActivityManager.shared.startBoopLiveActivity(
            contactName: boop.displayName,
            contactID: boop.senderUUID,
            interactionID: interaction.id
        )
    }

    // MARK: - Session End Handling

    private func handleSessionEnd(peripheralUUID: UUID) {
        let now = Date()

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
        if let existingInteraction = findInteractionInSession(
            contactUUID: senderUUID,
            sessionStart: sessionStart,
            sessionEnd: now
        ) {
            // Enrich the existing boop with session data
            existingInteraction.endTimestamp = now
            if !pathCoords.isEmpty {
                existingInteraction.pathCoordinates = pathCoords
            }
            // Update location name if we have path data and the existing one is empty
            if existingInteraction.location.isEmpty, let locationManager {
                Task {
                    let name = await locationManager.reverseGeocodeCurrentLocation()
                    if !name.isEmpty {
                        existingInteraction.location = name
                    }
                    try? self.modelContext?.save()
                }
            } else {
                try? modelContext?.save()
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

                // We need a display name — try DataStore or use a fallback
                let displayName: String
                if let contact = findOrCreateContact(senderUUID: senderUUID, displayName: "Simulated Friend", birthday: nil, bio: nil, gradientColors: []) {
                    displayName = contact.displayName
                    _ = createInteraction(
                        title: displayName,
                        location: locationName,
                        timestamp: sessionStart,
                        endTimestamp: now,
                        contact: contact,
                        pathCoordinates: pathCoords
                    )
                    try? self.modelContext?.save()
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
            let profile = await UserDataStore.shared.getUserProfile()

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

        // Send a boop back so the sender also gets the record.
        if let lastBoop = lastBoopTime[peripheralUUID],
           Date().timeIntervalSince(lastBoop) < boopCooldown {
            print("⏳ BoopManager: Skipping send-back boop to \(peripheralUUID.uuidString.prefix(8)) - cooldown active")
        } else {
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
}
