import Foundation
import CoreBluetooth
import Combine
import UIKit
import NearbyInteraction

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var nearbyDevices: [UUID] = []
    @Published var boops: [UUID: Boop] = [:]
    @Published var connectionRequests: [UUID: ConnectionRequest] = [:]
    @Published var connectionResponses: [UUID: ConnectionResponse] = [:]

    // MARK: - Internal State
    var connectedPeripherals: [UUID: CBPeripheral] = [:]

    // MARK: - Dependencies
    private var service: BluetoothManagerServiceImpl!
    private var uwbManager: UWBManaging?

    // Track UWB token exchange
    private var devicesWithUWBRanging: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    init(uwbManager: UWBManaging? = nil) {
        self.uwbManager = uwbManager
        super.init()

        // Create service with UWB token
        let uwbToken = uwbDiscoveryToken
        service = BluetoothManagerServiceImpl(
            uwbDiscoveryToken: uwbToken
        )
        service.delegate = self

        // Set up observer for nearbyDevices changes to manage UWB ranging
        setupUWBObserver()
    }

    // MARK: - Public Methods
    func start() {
        Task {
            await service.start()
        }
    }

    func stop() {
        Task {
            await service.stop()
        }
        nearbyDevices = []
        devicesWithUWBRanging.removeAll()
    }

    func getNearbyDevices() -> [UUID] {
        return nearbyDevices
    }

    func connect(to deviceID: UUID) {
        Task {
            await service.connect(to: deviceID)
        }
    }

    func sendMessage(_ message: BluetoothMessage, to peripheral: CBPeripheral) {
        Task {
            await service.sendMessage(message, to: peripheral)
        }
    }

    func disconnect(from deviceID: UUID) {
        Task {
            await service.disconnect(from: deviceID)
        }
    }

    // MARK: - UWB Integration
    private func setupUWBObserver() {
        // Observe changes to nearbyDevices and manage UWB ranging
        $nearbyDevices
            .sink { [weak self] devices in
                guard let self = self else { return }
                self.syncUWBRanging(with: Set(devices))
            }
            .store(in: &cancellables)
    }

    private func syncUWBRanging(with currentDevices: Set<UUID>) {
        print("🔄 BT Manager: syncUWBRanging called")
        print("📊 BT Manager: Current state - nearbyDevices: \(nearbyDevices.count), devicesWithUWBRanging: \(devicesWithUWBRanging.count), connectedPeripherals: \(connectedPeripherals.count)")
        print("📋 BT Manager: nearbyDevices: [\(nearbyDevices.map { $0.uuidString.prefix(8) }.joined(separator: ", "))]")
        print("📋 BT Manager: devicesWithUWBRanging: [\(devicesWithUWBRanging.map { $0.uuidString.prefix(8) }.joined(separator: ", "))]")
        print("📋 BT Manager: connectedPeripherals: [\(connectedPeripherals.keys.map { $0.uuidString.prefix(8) }.joined(separator: ", "))]")

        // Stop ranging for devices that are no longer nearby
        let devicesToRemove = devicesWithUWBRanging.subtracting(currentDevices)
        if !devicesToRemove.isEmpty {
            print("🛑 BT Manager: Stopping UWB ranging for \(devicesToRemove.count) device(s)")
            for deviceID in devicesToRemove {
                uwbManager?.stopRanging(to: deviceID)
                devicesWithUWBRanging.remove(deviceID)
                print("📍 BT Manager: Stopped UWB ranging for: \(deviceID.uuidString.prefix(8))")
            }
        }

        // Start ranging for new devices (will exchange tokens on connect)
        let newDevices = currentDevices.subtracting(devicesWithUWBRanging)
        if !newDevices.isEmpty {
            print("🆕 BT Manager: New devices detected, will start UWB ranging for \(newDevices.count) device(s)")
            for deviceID in newDevices {
                // Connect to device to exchange UWB tokens
                print("📍 BT Manager: Connecting to exchange UWB tokens with: \(deviceID.uuidString.prefix(8))")
                connect(to: deviceID)
            }
        }

        print("📊 BT Manager: After sync - devicesWithUWBRanging: \(devicesWithUWBRanging.count), connectedPeripherals: \(connectedPeripherals.count)")
    }

    // MARK: - UWB Methods

    /// Checks if the device is pointing at another device using UWB
    func isPointingAt(deviceID: UUID) -> Bool {
        return uwbManager?.isPointingAt(deviceID: deviceID) ?? false
    }

    /// Checks if a device is nearby using UWB distance only
    func isNearby(deviceID: UUID) -> Bool {
        return uwbManager?.isNearby(deviceID: deviceID) ?? false
    }

    /// Checks if devices are approximately touching (≤10cm)
    func isApproximatelyTouching(deviceID: UUID) -> Bool {
        return uwbManager?.isApproximatelyTouching(deviceID: deviceID) ?? false
    }

    // MARK: - Async UWB Methods

    /// Async version: Checks if the device is pointing at another device using UWB
    func isPointingAtAsync(deviceID: UUID) async -> Bool {
        return uwbManager?.isPointingAt(deviceID: deviceID) ?? false
    }

    /// Async version: Checks if a device is nearby using UWB distance only
    func isNearbyAsync(deviceID: UUID) async -> Bool {
        return uwbManager?.isNearby(deviceID: deviceID) ?? false
    }

    /// Async version: Checks if devices are approximately touching (≤10cm)
    func isApproximatelyTouchingAsync(deviceID: UUID) async -> Bool {
        return uwbManager?.isApproximatelyTouching(deviceID: deviceID) ?? false
    }

    /// Get the UWB discovery token for this device
    var uwbDiscoveryToken: Data? {
        guard let token = uwbManager?.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    // MARK: - Diagnostics

    /// Print comprehensive diagnostics for debugging UWB and BLE state
    func printDiagnostics() {
        print("🔍 === BLUETOOTH MANAGER DIAGNOSTICS ===")
        print("🔍 Nearby devices: \(nearbyDevices.count)")
        print("🔍 Connected peripherals: \(connectedPeripherals.count)")
        print("🔍 Devices with UWB ranging: \(devicesWithUWBRanging.count)")
        print("🔍 UWB Manager exists: \(uwbManager != nil)")

        if !nearbyDevices.isEmpty {
            print("🔍 Nearby devices list:")
            for deviceID in nearbyDevices {
                let isConnected = connectedPeripherals[deviceID] != nil
                let hasUWB = devicesWithUWBRanging.contains(deviceID)
                print("   - \(deviceID.uuidString.prefix(8)): connected=\(isConnected), uwb=\(hasUWB)")
            }
        }

        if let uwbMgr = uwbManager as? UWBManager {
            uwbMgr.printDiagnostics()
        } else {
            print("⚠️ UWB Manager not available for diagnostics")
        }
        print("🔍 =====================================")
    }
}

// MARK: - BluetoothServiceDelegate
extension BluetoothManager: BluetoothServiceDelegate {

    func didDiscoverDevice(_ deviceID: UUID, peripheral: CBPeripheral, rssi: NSNumber) {
        print("🔍 BT Manager: didDiscoverDevice(\(deviceID.uuidString.prefix(8))) RSSI: \(rssi)")
        // Add to nearby devices if not already present
        if !nearbyDevices.contains(deviceID) {
            nearbyDevices.append(deviceID)
            print("✅ BT Manager: Added device to nearbyDevices - total: \(nearbyDevices.count)")
            print("📊 BT Manager: State after discovery - nearbyDevices: \(nearbyDevices.count), connectedPeripherals: \(connectedPeripherals.count), devicesWithUWBRanging: \(devicesWithUWBRanging.count)")
        } else {
            print("⚠️ BT Manager: Device already in nearbyDevices")
        }
    }

    func didRemoveDevice(_ deviceID: UUID) {
        print("🗑️ BT Manager: didRemoveDevice(\(deviceID.uuidString.prefix(8)))")
        // Remove from nearby devices
        nearbyDevices.removeAll { $0 == deviceID }
        print("✅ BT Manager: Removed device from nearbyDevices - total: \(nearbyDevices.count)")
        print("📊 BT Manager: State after removal - nearbyDevices: \(nearbyDevices.count), connectedPeripherals: \(connectedPeripherals.count), devicesWithUWBRanging: \(devicesWithUWBRanging.count)")
    }

    func didConnect(to deviceID: UUID, peripheral: CBPeripheral) {
        print("🔗 BT Manager: didConnect(\(deviceID.uuidString.prefix(8)))")
        connectedPeripherals[deviceID] = peripheral
        print("✅ BT Manager: Added to connectedPeripherals - total: \(connectedPeripherals.count)")
        print("📊 BT Manager: State after connect - nearbyDevices: \(nearbyDevices.count), connectedPeripherals: \(connectedPeripherals.count), devicesWithUWBRanging: \(devicesWithUWBRanging.count)")
    }

    func didDisconnect(from deviceID: UUID) {
        print("🔌 BT Manager: didDisconnect(\(deviceID.uuidString.prefix(8)))")
        connectedPeripherals.removeValue(forKey: deviceID)
        print("✅ BT Manager: Removed from connectedPeripherals - total: \(connectedPeripherals.count)")
        print("📊 BT Manager: State after disconnect - nearbyDevices: \(nearbyDevices.count), connectedPeripherals: \(connectedPeripherals.count), devicesWithUWBRanging: \(devicesWithUWBRanging.count)")
    }

    func didReceiveBoop(from senderUUID: UUID) {
        print("🤝 BT Manager: didReceiveBoop(\(senderUUID.uuidString.prefix(8)))")
        boops[senderUUID] = Boop(senderUUID: senderUUID)
    }

    func didReceiveConnectionRequest(from senderUUID: UUID) {
        print("📨 BT Manager: didReceiveConnectionRequest(\(senderUUID.uuidString.prefix(8)))")
        connectionRequests[senderUUID] = ConnectionRequest(requesterUUID: senderUUID)
    }

    func didReceiveConnectionAccept(from senderUUID: UUID) {
        print("✅ BT Manager: didReceiveConnectionAccept(\(senderUUID.uuidString.prefix(8)))")
        connectionResponses[senderUUID] = ConnectionResponse(requesterUUID: senderUUID, accepted: true)
    }

    func didReceiveConnectionReject(from senderUUID: UUID) {
        print("❌ BT Manager: didReceiveConnectionReject(\(senderUUID.uuidString.prefix(8)))")
        connectionResponses[senderUUID] = ConnectionResponse(requesterUUID: senderUUID, accepted: false)
    }

    func didReceiveDisconnect(from senderUUID: UUID) {
        print("🔌 BT Manager: didReceiveDisconnect(\(senderUUID.uuidString.prefix(8)))")
        self.disconnect(from: senderUUID)
    }

    func didExchangeUWBToken(for deviceID: UUID, token: NIDiscoveryToken) {
        print("📍 BT Manager: didExchangeUWBToken(\(deviceID.uuidString.prefix(8)))")
        // Start UWB ranging with this peer
        uwbManager?.startRanging(to: deviceID, token: token)
        devicesWithUWBRanging.insert(deviceID)
        print("✅ BT Manager: Started UWB ranging with \(deviceID.uuidString.prefix(8)) - total ranging: \(devicesWithUWBRanging.count)")
        print("📊 BT Manager: State after UWB token exchange - nearbyDevices: \(nearbyDevices.count), connectedPeripherals: \(connectedPeripherals.count), devicesWithUWBRanging: \(devicesWithUWBRanging.count)")
    }
}
