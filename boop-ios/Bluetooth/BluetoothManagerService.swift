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

    // Track connected centrals (peers who have connected to us)
    private var connectedCentrals: [UUID: CBCentral] = [:]

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
        // Note: value must be nil to support both read and write
        uwbTokenCharacteristic = CBMutableCharacteristic(
            type: uwbTokenCharacteristicUUID,
            properties: [.read, .write],
            value: nil,  // Must be nil for writeable characteristics
            permissions: [.readable, .writeable]
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

        if isNewDevice {
            print("📱 BLE Service: New device discovered - \(deviceID.uuidString.prefix(8)), RSSI: \(RSSI) dBm")
            print("📊 BLE Service: discoveredDevices count: \(discoveredDevices.count), connectedPeripherals: \(connectedPeripherals.count)")
            Task { @MainActor in
                self.delegate?.didDiscoverDevice(deviceID, peripheral: peripheral, rssi: RSSI)
            }
        } else {
            // Log RSSI updates for debugging (can be verbose)
            // print("📶 BLE Service: RSSI update - \(deviceID.uuidString.prefix(8)), RSSI: \(RSSI) dBm")
        }
    }
    
    private func receivedBLERequestFromCentral(request: CBATTRequest) {
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
    }
    
    private func receivedUWBRequestFromCentral(request: CBATTRequest) {
        let central = request.central
        if let tokenData = request.value {
            do {
                if let token = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: tokenData
                ) {
                    let peerID = central.identifier
                    print("📍 BLE Service: Received UWB token via write from central \(peerID.uuidString.prefix(8)) (size: \(tokenData.count) bytes)")
                    
                    // Track this central
                    connectedCentrals[peerID] = central
                    
                    // Now we can start ranging on the peripheral side too!
                    print("✅ BLE Service: Starting bidirectional UWB ranging from peripheral side")
                    Task { @MainActor in
                        self.delegate?.didExchangeUWBToken(for: peerID, token: token)
                    }
                    
                    peripheralManager.respond(to: request, withResult: .success)
                }
            } catch {
                print("⚠️ Failed to decode received UWB token: \(error.localizedDescription)")
                peripheralManager.respond(to: request, withResult: .unlikelyError)
            }
        } else {
            print("⚠️ UWB request has empty value")
            peripheralManager.respond(to: request, withResult: .attributeNotFound)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                          didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let incommingRequestCharacteristic = request.characteristic.uuid
            switch incommingRequestCharacteristic {
                case messageCharacteristicUUID:
                    receivedBLERequestFromCentral(request: request)
                case uwbTokenCharacteristicUUID:
                    receivedUWBRequestFromCentral(request: request)
                default:
                    print("⚠️ BLE Service: Received message from unknown  characteristic \(incommingRequestCharacteristic)")
                    peripheralManager.respond(to: request, withResult: .unsupportedGroupType)
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                          didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == uwbTokenCharacteristicUUID {
            // Track this central so we can match writes later
            let central = request.central
            print("📍 BLE Service: Central \(central.identifier.uuidString.prefix(8)) reading our UWB token")
            connectedCentrals[central.identifier] = central

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
        print("✅ BLE Service: Connected to \(peripheral.identifier.uuidString.prefix(8))")
        connectedPeripherals[peripheral.identifier] = peripheral
        print("📊 BLE Service: connectedPeripherals count: \(connectedPeripherals.count)")
        peripheral.discoverServices([boopServiceUUID])
        print("🔍 BLE Service: Discovering services for \(peripheral.identifier.uuidString.prefix(8))")

        Task { @MainActor in
            self.delegate?.didConnect(to: peripheral.identifier, peripheral: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        if let error = error {
            print("❌ BLE Service: Disconnected from \(peripheral.identifier.uuidString.prefix(8)) with error: \(error.localizedDescription)")
        } else {
            print("❌ BLE Service: Disconnected from \(peripheral.identifier.uuidString.prefix(8))")
        }
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        print("📊 BLE Service: connectedPeripherals count: \(connectedPeripherals.count)")

        Task { @MainActor in
            self.delegate?.didDisconnect(from: peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        print("⚠️ BLE Service: Failed to connect to \(peripheral.identifier.uuidString.prefix(8)): \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManagerServiceImpl: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverServices error: Error?) {
        if let error = error {
            print("⚠️ BLE Service: Error discovering services for \(peripheral.identifier.uuidString.prefix(8)): \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            print("⚠️ BLE Service: No services found for \(peripheral.identifier.uuidString.prefix(8))")
            return
        }

        print("🔍 BLE Service: Discovered \(services.count) service(s) for \(peripheral.identifier.uuidString.prefix(8))")
        for service in services {
            print("🔍 BLE Service: Discovering characteristics for service \(service.uuid)")
            peripheral.discoverCharacteristics([messageCharacteristicUUID, uwbTokenCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        if let error = error {
            print("⚠️ BLE Service: Error discovering characteristics for \(peripheral.identifier.uuidString.prefix(8)): \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            print("⚠️ BLE Service: No characteristics found for \(peripheral.identifier.uuidString.prefix(8))")
            return
        }

        print("🔍 BLE Service: Discovered \(characteristics.count) characteristic(s) for \(peripheral.identifier.uuidString.prefix(8))")

        for characteristic in characteristics {
            if characteristic.uuid == uwbTokenCharacteristicUUID {
                print("📍 BLE Service: Found UWB token characteristic for \(peripheral.identifier.uuidString.prefix(8))")

                // Read peer's UWB token
                print("📍 BLE Service: Reading peer's UWB token from \(peripheral.identifier.uuidString.prefix(8))")
                peripheral.readValue(for: characteristic)

                // Write our UWB token to peer
                if let ourToken = uwbDiscoveryTokenData {
                    print("📍 BLE Service: Writing our UWB token to \(peripheral.identifier.uuidString.prefix(8)) (token size: \(ourToken.count) bytes)")
                    peripheral.writeValue(ourToken, for: characteristic, type: .withResponse)
                } else {
                    print("⚠️ BLE Service: No UWB token available to send to \(peripheral.identifier.uuidString.prefix(8))")
                }
            } else if characteristic.uuid == messageCharacteristicUUID {
                print("💬 BLE Service: Found message characteristic for \(peripheral.identifier.uuidString.prefix(8))")
            }
        }

        print("✅ BLE Service: Finished discovering characteristics for \(peripheral.identifier.uuidString.prefix(8))")
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("⚠️ BLE Service: Error writing value to \(peripheral.identifier.uuidString.prefix(8)): \(error.localizedDescription)")
        } else {
            if characteristic.uuid == uwbTokenCharacteristicUUID {
                print("✅ BLE Service: Successfully sent UWB token to \(peripheral.identifier.uuidString.prefix(8))")
            } else if characteristic.uuid == messageCharacteristicUUID {
                print("✅ BLE Service: Successfully sent message to \(peripheral.identifier.uuidString.prefix(8))")
            } else {
                print("✅ BLE Service: Successfully wrote value to characteristic \(characteristic.uuid)")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        if let error = error {
            print("⚠️ BLE Service: Error reading characteristic from \(peripheral.identifier.uuidString.prefix(8)): \(error.localizedDescription)")
            return
        }

        // Handle UWB token read
        if characteristic.uuid == uwbTokenCharacteristicUUID,
           let tokenData = characteristic.value {
            print("📍 BLE Service: Received UWB token data from \(peripheral.identifier.uuidString.prefix(8)) (size: \(tokenData.count) bytes)")
            do {
                if let token = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: tokenData
                ) {
                    print("✅ BLE Service: Successfully decoded UWB token from \(peripheral.identifier.uuidString.prefix(8))")
                    Task { @MainActor in
                        self.delegate?.didExchangeUWBToken(for: peripheral.identifier, token: token)
                    }
                }
            } catch {
                print("⚠️ BLE Service: Failed to decode UWB token from \(peripheral.identifier.uuidString.prefix(8)): \(error.localizedDescription)")
            }
        }
    }
}
