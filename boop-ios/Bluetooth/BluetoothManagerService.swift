//
//  BluetoothManagerService.swift
//  boop-ios
//

import Foundation
import CoreBluetooth
import NearbyInteraction

// MARK: - Delegate Protocol
@MainActor
protocol BluetoothServiceDelegate: AnyObject {
    func didDiscoverDevice(_ deviceID: UUID, peripheral: CBPeripheral, rssi: NSNumber)
    func didRemoveDevice(_ deviceID: UUID)
    func didConnect(to deviceID: UUID, peripheral: CBPeripheral)
    func didDisconnect(from deviceID: UUID)
    func didReceiveBoop(from senderUUID: UUID)
    func didReceiveConnectionRequest(from senderUUID: UUID)
    func didReceiveConnectionAccept(from senderUUID: UUID)
    func didReceiveConnectionReject(from senderUUID: UUID)
    func didReceiveDisconnect(from senderUUID: UUID)
    func didExchangeUWBToken(for deviceID: UUID, token: NIDiscoveryToken)
}

// MARK: - Service Protocol
protocol BluetoothManagerService {
    func start() async
    func stop() async
    func connect(to deviceID: UUID) async
    func sendMessage(_ message: BluetoothMessage, to peripheral: CBPeripheral) async
    func disconnect(from deviceID: UUID) async
    func getConnectedPeripheral(for deviceID: UUID) -> CBPeripheral?
}

class BluetoothManagerServiceImpl: NSObject, BluetoothManagerService {

    // MARK: - Properties
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    weak var delegate: BluetoothServiceDelegate?

    // MARK: - BLE UUIDs
    private let boopServiceUUID = CBUUID(string: "D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F")
    private let messageCharacteristicUUID = CBUUID(string: "D3A42A7D-DA0E-4D2C-AAB1-88C77E018A5F")
    private let uwbTokenCharacteristicUUID = CBUUID(string: "D3A42A7E-DA0E-4D2C-AAB1-88C77E018A5F")

    // MARK: - State
    private var peripheralReady = false
    private var centralReady = false
    private var hasStarted = false

    // Track devices and peripherals
    private var discoveredDevices: [UUID: (lastSeen: Date, peripheral: CBPeripheral, rssi: NSNumber)] = [:]
    private var messageCharacteristic: CBMutableCharacteristic?
    private var uwbTokenCharacteristic: CBMutableCharacteristic?
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]

    // UWB token data
    private var uwbDiscoveryTokenData: Data?

    // MARK: - Init
    init(uwbDiscoveryToken: Data?) {
        self.uwbDiscoveryTokenData = uwbDiscoveryToken
        super.init()

        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods
    func start() async {
        // Reset state
        hasStarted = false
        maybeStart()
    }

    func stop() async {
        peripheralManager.stopAdvertising()
        centralManager.stopScan()
        discoveredDevices = [:]
        hasStarted = false
        print("🛑 Stopped advertising and scanning")
    }

    func connect(to deviceID: UUID) async {
        guard let deviceInfo = discoveredDevices[deviceID] else {
            print("⚠️ Device not found in discovered devices")
            return
        }
        let peripheral = deviceInfo.peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        print("🔗 Connecting to \(deviceID)")
    }

    func sendMessage(_ message: BluetoothMessage, to peripheral: CBPeripheral) async {
        guard let service = peripheral.services?.first(where: { $0.uuid == boopServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == messageCharacteristicUUID }) else {
            print("⚠️ Service or characteristic not found")
            return
        }

        let encodedData = message.encode()
        peripheral.writeValue(encodedData, for: characteristic, type: .withResponse)
        print("📤 Sent \(message.messageType) to \(peripheral.identifier)")
    }

    func disconnect(from deviceID: UUID) async {
        guard let peripheral = connectedPeripherals[deviceID] else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        print("🔌 Disconnecting from \(deviceID)")
    }

    func getConnectedPeripheral(for deviceID: UUID) -> CBPeripheral? {
        return connectedPeripherals[deviceID]
    }

    func updateUWBToken(_ tokenData: Data?) {
        self.uwbDiscoveryTokenData = tokenData
        if let characteristic = uwbTokenCharacteristic {
            characteristic.value = tokenData
        }
    }

    // MARK: - Private Methods
    private func maybeStart() {
        guard peripheralReady, centralReady, !hasStarted else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasStarted = true
            self.startAdvertising()
            self.startScanning()

            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.removeStaleDevices()
            }
        }
    }

    private func startAdvertising() {
        // Create message characteristic
        messageCharacteristic = CBMutableCharacteristic(
            type: messageCharacteristicUUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )

        // Create UWB token characteristic
        uwbTokenCharacteristic = CBMutableCharacteristic(
            type: uwbTokenCharacteristicUUID,
            properties: [.read],
            value: uwbDiscoveryTokenData,
            permissions: [.readable]
        )

        let service = CBMutableService(type: boopServiceUUID, primary: true)
        service.characteristics = [messageCharacteristic!, uwbTokenCharacteristic!]
        peripheralManager.add(service)

        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [boopServiceUUID],
            CBAdvertisementDataLocalNameKey: "BoopDevice"
        ]
        peripheralManager.startAdvertising(advertisementData)
        print("📡 Started advertising")
    }

    private func startScanning() {
        centralManager.scanForPeripherals(
            withServices: [boopServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        print("🔍 Started scanning")
    }

    private func removeStaleDevices() {
        let now = Date()
        let threshold: TimeInterval = 5
        let previousCount = discoveredDevices.count

        let removedDevices = discoveredDevices.filter { now.timeIntervalSince($0.value.lastSeen) >= threshold }
        discoveredDevices = discoveredDevices.filter { now.timeIntervalSince($0.value.lastSeen) < threshold }

        if discoveredDevices.count != previousCount {
            let removedCount = previousCount - discoveredDevices.count
            print("📱 BLE: Removed \(removedCount) stale device(s)")

            // Notify delegate of removed devices
            Task { @MainActor in
                for (deviceID, _) in removedDevices {
                    self.delegate?.didRemoveDevice(deviceID)
                }
            }
        }
    }

}

// MARK: - CBPeripheralManagerDelegate, CBCentralManagerDelegate
extension BluetoothManagerServiceImpl: CBPeripheralManagerDelegate, CBCentralManagerDelegate {

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
        let deviceID = peripheral.identifier
        let isNewDevice = discoveredDevices[deviceID] == nil

        // Update discovered devices (RSSI and timestamp)
        discoveredDevices[deviceID] = (Date(), peripheral, RSSI)

        // Only notify delegate if this is a NEW device
        // This prevents constant observer triggers on RSSI updates
        if isNewDevice {
            print("📱 BLE: New device discovered - \(deviceID.uuidString.prefix(8))")
            Task { @MainActor in
                self.delegate?.didDiscoverDevice(deviceID, peripheral: peripheral, rssi: RSSI)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                          didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == messageCharacteristicUUID {
                if let value = request.value,
                   let message = BluetoothMessage.decode(value) {
                    // Handle message via delegate
                    Task { @MainActor in
                        switch message.messageType {
                        case .boop:
                            self.delegate?
                                .didReceiveBoop(from: message.senderUUID)
                        case .connectionRequest:
                            self.delegate?.didReceiveConnectionRequest(from: message.senderUUID)
                        case .connectionAccept:
                            self.delegate?.didReceiveConnectionAccept(from: message.senderUUID)
                        case .connectionReject:
                            self.delegate?.didReceiveConnectionReject(from: message.senderUUID)
                        case .disconnect:
                            self.delegate?.didReceiveDisconnect(from: message.senderUUID)
                        }
                    }
                    peripheralManager.respond(to: request, withResult: .success)
                } else {
                    print("⚠️ Failed to decode message")
                    peripheralManager.respond(to: request, withResult: .unlikelyError)
                }
            } else if request.characteristic.uuid == uwbTokenCharacteristicUUID {
                // Received peer's UWB token
                if let tokenData = request.value {
                    do {
                        if let _ = try NSKeyedUnarchiver.unarchivedObject(
                            ofClass: NIDiscoveryToken.self,
                            from: tokenData
                        ) {
                            print("📍 Received UWB token via peripheral manager")
                            peripheralManager.respond(to: request, withResult: .success)
                        }
                    } catch {
                        print("⚠️ Failed to decode received UWB token: \(error.localizedDescription)")
                        peripheralManager.respond(to: request, withResult: .unlikelyError)
                    }
                } else {
                    peripheralManager.respond(to: request, withResult: .invalidAttributeValueLength)
                }
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                          didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == uwbTokenCharacteristicUUID {
            // Provide our UWB token
            if let tokenData = uwbDiscoveryTokenData {
                request.value = tokenData
                peripheralManager.respond(to: request, withResult: .success)
                print("📍 Provided UWB token to peer")
            } else {
                peripheralManager.respond(to: request, withResult: .attributeNotFound)
            }
        } else {
            peripheralManager.respond(to: request, withResult: .requestNotSupported)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didConnect peripheral: CBPeripheral) {
        print("✅ Connected to \(peripheral.identifier)")
        connectedPeripherals[peripheral.identifier] = peripheral
        peripheral.discoverServices([boopServiceUUID])

        Task { @MainActor in
            self.delegate?.didConnect(to: peripheral.identifier, peripheral: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        print("❌ Disconnected from \(peripheral.identifier)")
        connectedPeripherals.removeValue(forKey: peripheral.identifier)

        Task { @MainActor in
            self.delegate?.didDisconnect(from: peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("⚠️ Failed to connect to \(peripheral.identifier): \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManagerServiceImpl: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([messageCharacteristicUUID, uwbTokenCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == uwbTokenCharacteristicUUID {
                // Read peer's UWB token
                peripheral.readValue(for: characteristic)

                // Write our UWB token to peer
                if let ourToken = uwbDiscoveryTokenData {
                    peripheral.writeValue(ourToken, for: characteristic, type: .withResponse)
                    print("📍 Exchanging UWB tokens with \(peripheral.identifier.uuidString.prefix(8))")
                }
            }
        }

        print("🔍 Discovered characteristics for \(peripheral.identifier.uuidString.prefix(8))")
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("⚠️ Error writing value: \(error.localizedDescription)")
        } else {
            if characteristic.uuid == uwbTokenCharacteristicUUID {
                print("✅ Successfully sent UWB token to \(peripheral.identifier.uuidString.prefix(8))")
            } else {
                print("✅ Successfully wrote value to characteristic")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("⚠️ Error reading characteristic: \(error.localizedDescription)")
            return
        }

        // Handle UWB token read
        if characteristic.uuid == uwbTokenCharacteristicUUID,
           let tokenData = characteristic.value {
            do {
                if let token = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: tokenData
                ) {
                    print("📍 Received UWB token from \(peripheral.identifier.uuidString.prefix(8))")
                    Task { @MainActor in
                        self.delegate?.didExchangeUWBToken(for: peripheral.identifier, token: token)
                    }
                }
            } catch {
                print("⚠️ Failed to decode UWB token: \(error.localizedDescription)")
            }
        }
    }
}
