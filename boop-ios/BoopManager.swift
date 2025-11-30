import Foundation
import Combine
import UIKit

// MARK: - Boop Manager
/// Manages the queue of devices that are in "boop" range (touching distance)
/// Automatically tracks devices that are ≤10cm away with aligned angles
@MainActor
class BoopManager: ObservableObject {

    // MARK: - Published Properties
    /// Devices currently in touching range (≤10cm, angles aligned)
    @Published var boopQueue = Set<UUID>()

    // MARK: - Private Properties
    private let bluetoothManager: BluetoothManager
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 2.0  // Update every 2 seconds

    // MARK: - Init
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        self.bluetoothManager.start()
        setupObservers()
    }
    
    // MARK: - Setup
    private func setupObservers() {
        // Observe nearbyDevices changes and update boop queue
        bluetoothManager.$nearbyDevices
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateBoopQueue()
            }
            .store(in: &cancellables)
    }

    /// Updates the boop queue by filtering nearby devices for touching distance (sync version)
    private func updateBoopQueue() {
        print("🔄 Boop: Checking for devices in touching range...")
        
        let touchingDevices = Set(
            bluetoothManager.nearbyDevices.filter
            { key, value in value == DevicePositionCategory.ApproxTouching }.keys)
        
        let devicesToAdd = touchingDevices.subtracting(boopQueue)
    
        for device in devicesToAdd {
            boopQueue.insert(device)
        }
    }
    
    func boopAndRemove() throws -> UUID {
        guard !boopQueue.isEmpty else {
            print("🤝 Boop: Queue is empty, cannot boop + remove")
            return UUID()
        }
        var deviceID = boopQueue.removeFirst()
        // Check if device is connected
        var success = false
        var attempts = 0
        while (!success && attempts < 3) {
            guard let peripheral = bluetoothManager.connectedPeripherals[deviceID] else {
                print("⚠️ Boop: Device \(deviceID.uuidString.prefix(8)) not connected, connecting...")
                bluetoothManager.connect(to: deviceID)
                // Note: Will need to retry sending after connection establishes
                attempts += 1
                continue
            }
            
            // Create connection request message
            let message = BluetoothMessage(
                senderUUID: deviceID,
                messageType: .boop,
                payload: Data()
            )
            
            // Send friend request
            bluetoothManager.sendMessage(message, to: peripheral)
            print("✉️ Boop: Booped \(deviceID.uuidString.prefix(8))")
            success = true
            return deviceID
        }
        
        throw fatalError("Could not connect to device to boop")
    }

    /// Processes the boop queue by sending friend requests to all touching devices
    func processQueue() {
        guard !boopQueue.isEmpty else {
            print("🤝 Boop: Queue is empty, nothing to process")
            return
        }

        guard let senderUUID = UIDevice.current.identifierForVendor else {
            print("⚠️ Boop: Cannot get device identifier")
            return
        }

        print("🤝 Boop: Processing queue - sending \(boopQueue.count) friend request(s)")

        while !boopQueue.isEmpty {
            var deviceID = boopQueue.removeFirst()
            // Check if device is connected
            guard let peripheral = bluetoothManager.connectedPeripherals[deviceID] else {
                print("⚠️ Boop: Device \(deviceID.uuidString.prefix(8)) not connected, connecting...")
                bluetoothManager.connect(to: deviceID)
                // Note: Will need to retry sending after connection establishes
                continue
            }

            // Create connection request message
            let message = BluetoothMessage(
                senderUUID: senderUUID,
                messageType: .connectionRequest,
                payload: Data()
            )

            // Send friend request
            bluetoothManager.sendMessage(message, to: peripheral)

            print("✉️ Boop: Sent friend request to \(deviceID.uuidString.prefix(8))")
        }
    }
}
