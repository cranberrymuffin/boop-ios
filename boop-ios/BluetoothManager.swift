import Foundation
import CoreBluetooth
import Combine

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var nearbyDevices: [UUID] = []

    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!

    private let topicServiceUUID = CBUUID(string: "D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F")

    private var peripheralReady = false
    private var centralReady = false
    private var hasStarted = false

    // Track devices and last seen time
    private var discoveredDevices: [UUID: Date] = [:]

    // MARK: - Init
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods
    func start() {
        // Reset state so maybeStart can run
        hasStarted = false
        maybeStart()
    }

    func stop() {
        peripheralManager.stopAdvertising()
        centralManager.stopScan()
        nearbyDevices = []
        discoveredDevices = [:]
        hasStarted = false
        print("🛑 Stopped advertising and scanning")
    }

    // MARK: - Private
    private func maybeStart() {
        guard peripheralReady, centralReady, !hasStarted else { return }

        // Small delay to allow both managers to stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasStarted = true
            self.startAdvertising()
            self.startScanning()
            
            // Timer to remove stale devices
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.removeStaleDevices()
            }
        }
    }

    private func startAdvertising() {
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [topicServiceUUID],
            CBAdvertisementDataLocalNameKey: "BoopDevice"
        ]
        peripheralManager.startAdvertising(advertisementData)
        print("📡 Started advertising")
    }

    private func startScanning() {
        centralManager.scanForPeripherals(
            withServices: [topicServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        print("🔍 Started scanning")
    }

    private func removeStaleDevices() {
        let now = Date()
        let threshold: TimeInterval = 5
        discoveredDevices = discoveredDevices.filter { now.timeIntervalSince($0.value) < threshold }
        nearbyDevices = Array(discoveredDevices.keys)
    }
}

// MARK: - Delegates
extension BluetoothManager: CBPeripheralManagerDelegate, CBCentralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            peripheralReady = true
            maybeStart()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralReady = true
            maybeStart()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        discoveredDevices[peripheral.identifier] = Date()
        nearbyDevices = Array(discoveredDevices.keys)
    }
}
