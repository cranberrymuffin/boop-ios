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
    @Published var boopQueue: [UUID] = [] // todo- update queue type to be o(1) removal

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
        startPeriodicUpdates()
    }

    deinit {
        updateTimer?.invalidate()
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

    private func startPeriodicUpdates() {
        print("🤝 Boop: Starting periodic queue updates every \(updateInterval)s")
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.updateBoopQueueAsync()
            }
        }
    }

    // MARK: - Queue Management
    /// Updates the boop queue by filtering nearby devices for touching distance (async version)
    private func updateBoopQueueAsync() async {
        print("🔄 Boop: [Async] Checking for devices in touching range...")

        let nearbyDevicesCopy = bluetoothManager.nearbyDevices

        // Check each device asynchronously
        var touchingDevices: [UUID] = []
        for deviceID in nearbyDevicesCopy {
            if await bluetoothManager.isApproximatelyTouchingAsync(deviceID: deviceID) {
                touchingDevices.append(deviceID)
            }
        }

        // Only update if changed to avoid unnecessary publishes
        if touchingDevices != boopQueue {
            let added = Set(touchingDevices).subtracting(Set(boopQueue))
            let removed = Set(boopQueue).subtracting(Set(touchingDevices))

            boopQueue = touchingDevices

            if !added.isEmpty {
                print("✅ Boop: [Async] Added \(added.count) device(s) to queue")
                for deviceID in added {
                    print("   + \(deviceID.uuidString.prefix(8))")
                }
            }

            if !removed.isEmpty {
                print("➖ Boop: [Async] Removed \(removed.count) device(s) from queue")
                for deviceID in removed {
                    print("   - \(deviceID.uuidString.prefix(8))")
                }
            }

            print("📊 Boop: [Async] Queue now has \(boopQueue.count) device(s)")
        } else {
            if !boopQueue.isEmpty {
                print("📊 Boop: [Async] Queue unchanged - \(boopQueue.count) device(s) still touching")
            }
        }
    }

    /// Updates the boop queue by filtering nearby devices for touching distance (sync version)
    private func updateBoopQueue() {
        print("🔄 Boop: Checking for devices in touching range...")

        let touchingDevices = bluetoothManager.nearbyDevices.filter { deviceID in
            bluetoothManager.isApproximatelyTouching(deviceID: deviceID)
        }

        // Only update if changed to avoid unnecessary publishes
        if touchingDevices != boopQueue {
            let added = Set(touchingDevices).subtracting(Set(boopQueue))
            let removed = Set(boopQueue).subtracting(Set(touchingDevices))

            boopQueue = touchingDevices

            if !added.isEmpty {
                print("✅ Boop: Added \(added.count) device(s) to queue")
                for deviceID in added {
                    print("   + \(deviceID.uuidString.prefix(8))")
                }
            }

            if !removed.isEmpty {
                print("➖ Boop: Removed \(removed.count) device(s) from queue")
                for deviceID in removed {
                    print("   - \(deviceID.uuidString.prefix(8))")
                }
            }

            print("📊 Boop: Queue now has \(boopQueue.count) device(s)")
        } else {
            if !boopQueue.isEmpty {
                print("📊 Boop: Queue unchanged - \(boopQueue.count) device(s) still touching")
            }
        }
    }

    /// Stop periodic queue updates
    func stopPeriodicUpdates() {
        print("🛑 Boop: Stopping periodic queue updates")
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// Restart periodic queue updates (if stopped)
    func restartPeriodicUpdates() {
        guard updateTimer == nil else {
            print("⚠️ Boop: Periodic updates already running")
            return
        }
        startPeriodicUpdates()
    }
    
    func boopAndRemove() throws -> UUID {
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
