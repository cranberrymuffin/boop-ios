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
    func didInvalidateService(_ deviceID: UUID, peripheral: CBPeripheral)
    func didDiscover(_ deviceID: UUID, peripheral: CBPeripheral, rssi: NSNumber)
    func didConnect(to deviceID: UUID, peripheral: CBPeripheral)
    func didDisconnect(from deviceID: UUID)
    func didReceiveConnectionRequest(from senderUUID: UUID)
    func didReceiveConnectionAccept(from senderUUID: UUID)
    func didReceiveConnectionReject(from senderUUID: UUID)
    func didReceiveDisconnect(from senderUUID: UUID)
    func didReceiveStoppedRanging(peripheralUUID: UUID)
    func didExchangeUWBToken(for deviceID: UUID)
    func didReceiveUWBTokenUpdate(for deviceID: UUID, newToken: NIDiscoveryToken)
    func getUWBDiscoveryTokenForDevice(for deviceID: UUID) -> Data?
}

@MainActor
protocol BoopDelegate: AnyObject {
    func didReceiveBoop(from senderUUID: UUID, peripheralUUID: UUID, displayName: String, birthday: Date?, bio: String?, gradientColors: [String])
    func didReceiveBoopRequest(from senderUUID: UUID, peripheralUUID: UUID, displayName: String, birthday: Date?, bio: String?, gradientColors: [String])
    func didDeviceConnect(peripheralUUID: UUID)
    func didDeviceDisconnect(peripheralUUID: UUID)
    func didDisableBle()
}

// MARK: - Service Protocol
protocol BluetoothManagerService {
    func start() async
    func stop(from peripherals: [CBPeripheral]) async
    func connect(to peripheral: CBPeripheral) -> Bool
    func sendMessage(_ message: BluetoothMessage, to peripheral: CBPeripheral) async
    func disconnect(from peripheral: CBPeripheral) async
}

class BluetoothManagerServiceImpl: NSObject, BluetoothManagerService {

    // MARK: - Properties
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    weak var bleServiceDelegate: BluetoothServiceDelegate?
    weak var boopDelegate: BoopDelegate?

    // MARK: - BLE UUIDs
    private let boopServiceUUID = CBUUID(string: "D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F")
    private let messageCharacteristicUUID = CBUUID(string: "D3A42A7D-DA0E-4D2C-AAB1-88C77E018A5F")
    private let uwbTokenCharacteristicUUID = CBUUID(string: "D3A42A7E-DA0E-4D2C-AAB1-88C77E018A5F")
    private let tokenExchangeAckCharacteristicUUID = CBUUID(string: "D3A42A7F-DA0E-4D2C-AAB1-88C77E018A5F")

    // MARK: - State
    private var peripheralReady = false
    private var centralReady = false
    private var hasStarted = false

    // Track devices and peripherals
    private var messageCharacteristic: CBMutableCharacteristic?
    private var uwbTokenCharacteristic: CBMutableCharacteristic?
    private var tokenExchangeAckCharacteristic: CBMutableCharacteristic?
//    private var connectedPeripherals: [UUID: CBPeripheral] = [:]

    // Central-side readiness (keyed by peripheral.identifier)
    private var centralReceivedPeerToken: Set<UUID> = []
    private var centralReceivedAck: Set<UUID> = []

    // Track connected centrals (peers who have connected to us)
//    private var connectedCentrals: [UUID: CBCentral] = [:]

    // MARK: - Init
    override init() {
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

    func stop(from peripherals: [CBPeripheral]) async {
        hasStarted = false // prevents discovery from occuring while stopping is in progress
        centralManager.stopScan()
        for peripheral in peripherals {
            await disconnect(from: peripheral)
        }
        peripheralManager.stopAdvertising()
        centralReceivedPeerToken.removeAll()
        centralReceivedAck.removeAll()
        print("🛑 Stopped advertising and scanning")
    }
    
    func setBoopDelegate(boopDelegate: BoopDelegate) {
        self.boopDelegate = boopDelegate
    }

    @discardableResult
    func connect(to peripheral: CBPeripheral) -> Bool {
        guard self.hasStarted else { return false }
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        print("🔗 Connecting to \(peripheral.identifier)")
        return true
    }

    func sendMessage(_ message: BluetoothMessage, to peripheral: CBPeripheral) async {
        guard self.hasStarted else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == boopServiceUUID }),
              let characteristic = service.characteristics?.first(where: { $0.uuid == messageCharacteristicUUID }) else {
            print("⚠️ Service or characteristic not found")
            return
        }

        let encodedData = message.encode()
        peripheral.writeValue(encodedData, for: characteristic, type: .withResponse)
        print("📤 Sent \(message.messageType) to \(peripheral.identifier)")
    }

    func disconnect(from peripheral: CBPeripheral) async {
        print("🔌 Disconnecting from \(peripheral.identifier)")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Private Methods
    private func maybeStart() {
        guard peripheralReady, centralReady, !hasStarted else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.hasStarted = true
            self.startAdvertising()
            self.startScanning()
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

        // Create ACK characteristic for token exchange acknowledgement
        tokenExchangeAckCharacteristic = CBMutableCharacteristic(
            type: tokenExchangeAckCharacteristicUUID,
            properties: [.notify],
            value: nil,
            permissions: []
        )

        let service = CBMutableService(type: boopServiceUUID, primary: true)
        service.characteristics = [messageCharacteristic!, uwbTokenCharacteristic!, tokenExchangeAckCharacteristic!]
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
}

// MARK: - CBPeripheralManagerDelegate, CBCentralManagerDelegate
extension BluetoothManagerServiceImpl: CBPeripheralManagerDelegate, CBCentralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            peripheralReady = true
            print("✅ BLE Peripheral state: poweredOn")
        case .poweredOff:
            peripheralReady = false
            print("⚠️ BLE Peripheral state: poweredOff")
            Task { @MainActor in
                boopDelegate?.didDisableBle()
            }
        case .unauthorized:
            peripheralReady = false
            print("❌ BLE Peripheral state: unauthorized")
        case .unsupported:
            peripheralReady = false
            print("❌ BLE Peripheral state: unsupported")
        case .resetting:
            peripheralReady = false
            print("⚠️ BLE Peripheral state: resetting")
        case .unknown:
            peripheralReady = false
            print("⚠️ BLE Peripheral state: unknown")
        @unknown default:
            peripheralReady = false
            print("⚠️ BLE Peripheral state: unrecognized")
        }
        maybeStart()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            centralReady = true
            print("✅ BLE Central state: poweredOn")
        case .poweredOff:
            centralReady = false
            print("⚠️ BLE Central state: poweredOff")
        case .unauthorized:
            centralReady = false
            print("❌ BLE Central state: unauthorized")
        case .unsupported:
            centralReady = false
            print("❌ BLE Central state: unsupported")
        case .resetting:
            centralReady = false
            print("⚠️ BLE Central state: resetting")
        case .unknown:
            centralReady = false
            print("⚠️ BLE Central state: unknown")
        @unknown default:
            centralReady = false
            print("⚠️ BLE Central state: unrecognized")
        }
        maybeStart()
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        guard self.hasStarted else { return }
        let deviceID = peripheral.identifier
        
        Task { @MainActor in
            self.bleServiceDelegate?.didDiscover(deviceID, peripheral: peripheral, rssi: RSSI) }
    }
    
    private func receivedBLERequestFromCentral(request: CBATTRequest) {
        let peripheralUUID = request.central.identifier
        print("📥 BLE Service: Received write request from central \(peripheralUUID.uuidString.prefix(8))")
        if let value = request.value,
           let message = BluetoothMessage.decode(value) {
            print("✅ BLE Service: Successfully decoded message")
            print("   - Type: \(message.messageType)")
            print("   - Sender UUID: \(message.senderUUID.uuidString.prefix(8))")
            print("   - Peripheral UUID: \(peripheralUUID.uuidString.prefix(8))")
            print("   - Display Name: '\(message.displayName)'")

            // Handle message via delegate
            Task { @MainActor in
                switch message.messageType {
                case .boop:
                    print("🎉 BLE Service: Routing boop message to delegate")
                    let (birthday, bio, gradientColors) = message.decodeProfileData()
                    self.boopDelegate?
                        .didReceiveBoop(from: message.senderUUID, peripheralUUID: peripheralUUID, displayName: message.displayName, birthday: birthday, bio: bio, gradientColors: gradientColors)
                case .boopRequest:
                    print("📨 BLE Service: Routing boop request to delegate")
                    let (birthday, bio, gradientColors) = message.decodeProfileData()
                    self.boopDelegate?
                        .didReceiveBoopRequest(from: message.senderUUID, peripheralUUID: peripheralUUID, displayName: message.displayName, birthday: birthday, bio: bio, gradientColors: gradientColors)
                case .presence:
                    print("👋 BLE Service: Ignoring presence message (feature removed)")
                case .connectionRequest:
                    self.bleServiceDelegate?.didReceiveConnectionRequest(from: message.senderUUID)
                case .connectionAccept:
                    self.bleServiceDelegate?.didReceiveConnectionAccept(from: message.senderUUID)
                case .connectionReject:
                    self.bleServiceDelegate?.didReceiveConnectionReject(from: message.senderUUID)
                case .disconnect:
                    self.bleServiceDelegate?.didReceiveDisconnect(from: message.senderUUID)
                case .stoppedRanging:
                    print("🛑 BLE Service: Routing stoppedRanging message to delegate")
                    self.bleServiceDelegate?.didReceiveStoppedRanging(peripheralUUID: peripheralUUID)
                }
            }
            peripheralManager.respond(to: request, withResult: .success)
        } else {
            print("⚠️ BLE Service: Failed to decode message from \(peripheralUUID.uuidString.prefix(8))")
            if let value = request.value {
                print("⚠️ BLE Service: Message data length: \(value.count) bytes")
            }
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
                    
                    Task { @MainActor in
                        self.bleServiceDelegate?.didReceiveUWBTokenUpdate(for: central.identifier, newToken: token)
                    }

                    peripheralManager.respond(to: request, withResult: .success)

                    // Notify ACK characteristic - tell central we received their token
                    if let ackChar = tokenExchangeAckCharacteristic {
                        peripheralManager.updateValue(Data([0x01]), for: ackChar, onSubscribedCentrals: nil)
                    }
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
        guard self.hasStarted else { return }
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
        guard self.hasStarted else { return }
        if request.characteristic.uuid == uwbTokenCharacteristicUUID {
            // Track this central so we can match writes later
            let central = request.central
            print("📍 BLE Service: Central \(central.identifier.uuidString.prefix(8)) reading our UWB token")
                // Provide our UWB token
            Task { @MainActor in
                if let tokenData = bleServiceDelegate?.getUWBDiscoveryTokenForDevice(for: central.identifier) {
                    request.value = tokenData
                    peripheralManager.respond(to: request, withResult: .success)
                    print("📍 BLE Service: Provided UWB token to peer")
                } else {
                    peripheralManager.respond(to: request, withResult: .attributeNotFound)
                }
            }
        } else {
            peripheralManager.respond(to: request, withResult: .requestNotSupported)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didConnect peripheral: CBPeripheral) {
        guard self.hasStarted else { return }
        print("✅ BLE Service: Connected to \(peripheral.identifier.uuidString.prefix(8))")
        peripheral.discoverServices([boopServiceUUID])
        print("🔍 BLE Service: Discovering services for \(peripheral.identifier.uuidString.prefix(8))")

        Task { @MainActor in
            self.bleServiceDelegate?.didConnect(to: peripheral.identifier, peripheral: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didDisconnectPeripheral peripheral: CBPeripheral,
                       error: Error?) {
        guard self.hasStarted else { return }
        if let error = error {
            print("❌ BLE Service: Disconnected from \(peripheral.identifier.uuidString.prefix(8)) with error: \(error.localizedDescription)")
        } else {
            print("❌ BLE Service: Disconnected from \(peripheral.identifier.uuidString.prefix(8))")
        }
        Task { @MainActor in
            self.bleServiceDelegate?.didDisconnect(from: peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didFailToConnect peripheral: CBPeripheral,
                       error: Error?) {
        guard self.hasStarted else { return }
        print("⚠️ BLE Service: Failed to connect to \(peripheral.identifier.uuidString.prefix(8)): \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManagerServiceImpl: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverServices error: Error?) {
        guard self.hasStarted else { return }
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
            peripheral.discoverCharacteristics([messageCharacteristicUUID, uwbTokenCharacteristicUUID, tokenExchangeAckCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                   didDiscoverCharacteristicsFor service: CBService,
                   error: Error?) {
        guard self.hasStarted else { return }
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
                Task { @MainActor in
                    if let ourToken = bleServiceDelegate?.getUWBDiscoveryTokenForDevice(for: peripheral.identifier) {
                        print("📍 BLE Service: Writing our UWB token to \(peripheral.identifier.uuidString.prefix(8)) (token size: \(ourToken.count) bytes)")
                        peripheral.writeValue(ourToken, for: characteristic, type: .withResponse)
                    } else {
                        print("⚠️ BLE Service: No UWB token available to send to \(peripheral.identifier.uuidString.prefix(8))")
                    }
                }
            } else if characteristic.uuid == tokenExchangeAckCharacteristicUUID {
                print("📍 BLE Service: Found ACK characteristic for \(peripheral.identifier.uuidString.prefix(8)), subscribing to notifications")
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == messageCharacteristicUUID {
                print("💬 BLE Service: Found message characteristic for \(peripheral.identifier.uuidString.prefix(8))")
            }
        }

        print("✅ BLE Service: Finished discovering characteristics for \(peripheral.identifier.uuidString.prefix(8))")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard self.hasStarted else { return }
        Task { @MainActor in
            bleServiceDelegate?.didInvalidateService(peripheral.identifier, peripheral: peripheral)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?) {
        guard self.hasStarted else { return }
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
        guard self.hasStarted else { return }
        if let error = error {
            let name: String
            switch characteristic.uuid {
            case uwbTokenCharacteristicUUID: name = "UWB Token"
            case tokenExchangeAckCharacteristicUUID: name = "Token Exchange ACK"
            case messageCharacteristicUUID: name = "Message"
            default: name = characteristic.uuid.uuidString
            }
            print("⚠️ BLE Service: Error reading \(name) characteristic from \(peripheral.identifier.uuidString.prefix(8)): \(error.localizedDescription)")
            return
        }

        if characteristic.uuid == uwbTokenCharacteristicUUID,
           let tokenData = characteristic.value {
            do {
                if let token = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: tokenData
                ) {
                    Task { @MainActor in
                        self.bleServiceDelegate?.didReceiveUWBTokenUpdate(
                            for: peripheral.identifier, newToken: token)
                    }
                }
            } catch {
                print("⚠️ BLE Service: Failed to decode UWB token: \(error.localizedDescription)")
            }
            centralReceivedPeerToken.insert(peripheral.identifier)
            maybeStartRangingCentral(for: peripheral.identifier)
        } else if characteristic.uuid == tokenExchangeAckCharacteristicUUID {
            // Central received ACK - peer confirmed it has our token
            print("📍 BLE Service: Central received ACK from \(peripheral.identifier.uuidString.prefix(8)) - peer has our token")
            centralReceivedAck.insert(peripheral.identifier)
            maybeStartRangingCentral(for: peripheral.identifier)
        }
    }

    private func maybeStartRangingCentral(for deviceID: UUID) {
        guard centralReceivedPeerToken.contains(deviceID),
              centralReceivedAck.contains(deviceID) else { return }
        centralReceivedPeerToken.remove(deviceID)
        centralReceivedAck.remove(deviceID)
        print("📍 BLE Service: Central-side token exchange complete for \(deviceID.uuidString.prefix(8)), starting ranging")
        Task { @MainActor in
            self.bleServiceDelegate?.didExchangeUWBToken(for: deviceID)
        }
    }

}
