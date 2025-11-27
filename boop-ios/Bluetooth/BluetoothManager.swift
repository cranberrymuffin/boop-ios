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
        // Stop ranging for devices that are no longer nearby
        let devicesToRemove = devicesWithUWBRanging.subtracting(currentDevices)
        for deviceID in devicesToRemove {
            uwbManager?.stopRanging(to: deviceID)
            devicesWithUWBRanging.remove(deviceID)
            print("📍 Stopped UWB ranging for removed device: \(deviceID.uuidString.prefix(8))")
        }

        // Start ranging for new devices (will exchange tokens on connect)
        let newDevices = currentDevices.subtracting(devicesWithUWBRanging)
        for deviceID in newDevices {
            // Connection will be handled automatically via service
            // Token exchange will trigger didExchangeUWBToken callback
            print("📍 Will exchange UWB tokens with: \(deviceID.uuidString.prefix(8))")
        }
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

    /// Get the UWB discovery token for this device
    var uwbDiscoveryToken: Data? {
        guard let token = uwbManager?.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
}

// MARK: - BluetoothServiceDelegate
extension BluetoothManager: BluetoothServiceDelegate {
    
    func didDiscoverDevice(_ deviceID: UUID, peripheral: CBPeripheral, rssi: NSNumber) {
        // Add to nearby devices if not already present
        if !nearbyDevices.contains(deviceID) {
            nearbyDevices.append(deviceID)
        }
    }

    func didRemoveDevice(_ deviceID: UUID) {
        // Remove from nearby devices
        nearbyDevices.removeAll { $0 == deviceID }
    }

    func didConnect(to deviceID: UUID, peripheral: CBPeripheral) {
        connectedPeripherals[deviceID] = peripheral
    }

    func didDisconnect(from deviceID: UUID) {
        connectedPeripherals.removeValue(forKey: deviceID)
    }
    
    func didReceiveBoop(from senderUUID: UUID) {
        boops[senderUUID] = Boop(senderUUID: senderUUID)
    }

    func didReceiveConnectionRequest(from senderUUID: UUID) {
        connectionRequests[senderUUID] = ConnectionRequest(requesterUUID: senderUUID)
        
    }

    func didReceiveConnectionAccept(from senderUUID: UUID) {
        connectionResponses[senderUUID] = ConnectionResponse(requesterUUID: senderUUID, accepted: true)
    }

    func didReceiveConnectionReject(from senderUUID: UUID) {
        connectionResponses[senderUUID] = ConnectionResponse(requesterUUID: senderUUID, accepted: false)
    }

    func didReceiveDisconnect(from senderUUID: UUID) {
        self.disconnect(from: senderUUID)
    }

    func didExchangeUWBToken(for deviceID: UUID, token: NIDiscoveryToken) {
        // Start UWB ranging with this peer
        uwbManager?.startRanging(to: deviceID, token: token)
        devicesWithUWBRanging.insert(deviceID)
        print("📍 Started UWB ranging with \(deviceID.uuidString.prefix(8))")
    }
}
