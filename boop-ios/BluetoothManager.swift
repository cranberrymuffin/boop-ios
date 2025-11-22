import Foundation
import CoreBluetooth
import Combine

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var nearbyDevices: [UUID] = []

    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!

    private let topicServiceUUID = CBUUID(string: "D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F")
    private let dataCharacteristicUUID = CBUUID(string: "D3A42A7D-DA0E-4D2C-AAB1-88C77E018A5F")

    private var peripheralReady = false
    private var centralReady = false
    private var hasStarted = false

    // Track devices, last seen time, and peripheral references
    private var discoveredDevices: [UUID: (lastSeen: Date, peripheral: CBPeripheral)] = [:]
    private var dataCharacteristic: CBMutableCharacteristic?
    var connectedPeripherals: [UUID: CBPeripheral] = [:]

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
        // Create characteristic that can be written to
        dataCharacteristic = CBMutableCharacteristic(
            type: dataCharacteristicUUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )

        // Create service with the characteristic
        let service = CBMutableService(type: topicServiceUUID, primary: true)
        service.characteristics = [dataCharacteristic!]
        peripheralManager.add(service)

        // Start advertising
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [topicServiceUUID],
            CBAdvertisementDataLocalNameKey: "BoopDevice"
        ]
        peripheralManager.startAdvertising(advertisementData)
        print("📡 Started advertising with data characteristic")
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
        discoveredDevices = discoveredDevices.filter { now.timeIntervalSince($0.value.lastSeen) < threshold }
        nearbyDevices = Array(discoveredDevices.keys)
    }

    // MARK: - Connection and Data Transfer
    func connect(to deviceID: UUID) {
        guard let deviceInfo = discoveredDevices[deviceID] else {
            print("⚠️ Device not found in discovered devices")
            return
        }

        let peripheral = deviceInfo.peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        print("🔗 Connecting to \(deviceID)")
    }

    func sendData(_ data: Data, to peripheral: CBPeripheral) {
        guard let service = peripheral.services?.first(where: { $0.uuid == topicServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == dataCharacteristicUUID }) else {
            print("⚠️ Service or characteristic not found")
            return
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("📤 Sent data to \(peripheral.identifier)")
    }

    func disconnect(from deviceID: UUID) {
        guard let peripheral = connectedPeripherals[deviceID] else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        print("🔌 Disconnecting from \(deviceID)")
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
        discoveredDevices[peripheral.identifier] = (Date(), peripheral)
        nearbyDevices = Array(discoveredDevices.keys)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                          didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == dataCharacteristicUUID {
                if let value = request.value {
                    let receivedString = String(data: value, encoding: .utf8) ?? "Unknown"
                    print("📥 Received data: \(receivedString)")
                    // Handle the received data here
                }
                peripheralManager.respond(to: request, withResult: .success)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func centralManager(_ central: CBCentralManager,
                       didConnect peripheral: CBPeripheral) {
        print("✅ Connected to \(peripheral.identifier)")
        connectedPeripherals[peripheral.identifier] = peripheral
        peripheral.discoverServices([topicServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ Disconnected from \(peripheral.identifier)")
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("⚠️ Failed to connect to \(peripheral.identifier): \(error?.localizedDescription ?? "Unknown error")")
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([dataCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        print("🔍 Discovered characteristics for \(peripheral.identifier), ready to send data")
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("⚠️ Error writing value: \(error.localizedDescription)")
        } else {
            print("✅ Successfully wrote value to characteristic")
        }
    }
}
