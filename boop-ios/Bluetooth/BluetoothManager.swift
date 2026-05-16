import Foundation
import CoreBluetooth
import Combine
import UIKit
import NearbyInteraction

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var nearbyDevices: AnyPublisher<[UUID: DevicePositionCategory], Never>
    @Published var connectionRequests: [UUID: ConnectionRequest] = [:]
    @Published var connectionResponses: [UUID: ConnectionResponse] = [:]
    
    var discoveredDevices: [UUID: CBPeripheral] = [:]

    // MARK: - Internal State
    var connectedPeripherals: [UUID: CBPeripheral] = [:]

    /// Local device UUID - persisted across app launches
    private(set) lazy var localDeviceUUID: UUID = {
        let key = "com.boop.localDeviceUUID"
        if let uuidString = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: uuidString) {
            return uuid
        }
        let newUUID = UUID()
        UserDefaults.standard.set(newUUID.uuidString, forKey: key)
        return newUUID
    }()

    // MARK: - Dependencies
    private var service: BluetoothManagerServiceImpl!
    private var uwbManager: UWBManaging

    // Track UWB token exchange
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    init(boopDelegate: BoopDelegate? = nil) {
        self.uwbManager = UWBManager()
        self.nearbyDevices = self.uwbManager.nearbyDevicesPublisher
        super.init()

        // Create service with UWB token
        
        service = BluetoothManagerServiceImpl()
        service.bleServiceDelegate = self
        if let boopDelegate = boopDelegate {
            service.setBoopDelegate(boopDelegate: boopDelegate)
        }
    }

    // MARK: - Public Methods
    func setBoopDelegate(_ delegate: BoopDelegate) {
        service.setBoopDelegate(boopDelegate: delegate)
    }

    func start() {
        Task {
            await service.start()
        }
    }

    func stop() {
        
        Task {
            // Notify all connected peers that we've stopped ranging
            let stoppedMessage = BluetoothMessage(
                senderUUID: localDeviceUUID,
                messageType: .stoppedRanging
            )
            for (_, peripheral) in connectedPeripherals {
                await service.sendMessage(stoppedMessage, to: peripheral)
            }
            await service.stop(from: Array(connectedPeripherals.values))
            uwbManager.stopRangingForAllDevices()
            connectedPeripherals.removeAll()
            discoveredDevices.removeAll()
            connectionRequests.removeAll()
            connectionResponses.removeAll()
        }
    }

    func getNearbyDevices() -> [UUID: DevicePositionCategory] {
        return uwbManager.nearbyDevices
    }

    func getLocalDeviceUUID() -> UUID {
        return localDeviceUUID
    }

    func sendMessage(_ message: BluetoothMessage, to device: UUID) {
        guard let peripheral = connectedPeripherals[device] else {
            print("❌ BT Manager: Cannot find peripheral for device \(device.uuidString.prefix(8))")
            print("📊 BT Manager: Connected peripherals: \(connectedPeripherals.keys.map { $0.uuidString.prefix(8) })")
            return
        }
        print("✅ BT Manager: Found peripheral, sending \(message.messageType) message to \(device.uuidString.prefix(8))")
        Task {
            await service.sendMessage(message, to: peripheral)
        }
    }

    func disconnect(from deviceID: UUID) {
        Task {
            guard let peripheral = connectedPeripherals[deviceID] else {
                return
            }
            uwbManager.stopRanging(to: deviceID)
            await service.disconnect(from: peripheral)
        }
        
    }

    // MARK: - Diagnostics

    /// Print comprehensive diagnostics for debugging UWB and BLE state
    func printDiagnostics() {
        print("🔍 === BLUETOOTH MANAGER DIAGNOSTICS ===")
        print("🔍 Connected peripherals: \(connectedPeripherals.count)")

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
    
    func getUWBDiscoveryTokenForDevice(for deviceID: UUID) -> Data? {
        uwbManager.getDiscoveryTokenForDeviceSession(for: deviceID)
    }
    
    
    func didInvalidateService(_ deviceID: UUID, peripheral: CBPeripheral) {
        self.uwbManager.stopRanging(to: deviceID)
    }
    
    func didReceiveUWBTokenUpdate(for deviceID: UUID, newToken: NIDiscoveryToken) {
        uwbManager.registerPeerDiscoveryToken(from: deviceID, token: newToken)

        if !uwbManager.isRanging(to: deviceID) {
            print("📍 BT Manager: Peer token received for \(deviceID.uuidString.prefix(8)); starting provisional ranging to trigger NI permission")
            uwbManager.startRanging(to: deviceID)
        }
    }
    

    func didDiscover(_ deviceID: UUID, peripheral: CBPeripheral, rssi: NSNumber) {
        if discoveredDevices[deviceID] == nil {
            if service.connect(to: peripheral) {
                discoveredDevices[deviceID] = peripheral
                print("✅ BT Manager: Added device to discoveredDevices - total: \(discoveredDevices.count)")
            }
        }
    }


    func didConnect(to deviceID: UUID, peripheral: CBPeripheral) {
        print("🔗 BT Manager: didConnect(\(deviceID.uuidString.prefix(8)))")
        if !connectedPeripherals.keys.contains(deviceID) {
            connectedPeripherals[deviceID] = peripheral
            print("✅ BT Manager: Added peripheral to connectedPeriphals - total: \(connectedPeripherals.count)")
        }
        uwbManager.registerPeer(to: deviceID)
        service.boopDelegate?.didDeviceConnect(peripheralUUID: deviceID)
        print("📊 BT Manager: State after discovery - discoveredDevices: \(discoveredDevices.count), connectedPeripherals: \(connectedPeripherals.count)")
    }

    func didDisconnect(from deviceID: UUID) {
        print("🔌 BT Manager: didDisconnect(\(deviceID.uuidString.prefix(8)))")

        connectedPeripherals.removeValue(forKey: deviceID)
        discoveredDevices.removeValue(forKey: deviceID)
        uwbManager.stopRanging(to: deviceID)
        service.boopDelegate?.didDeviceDisconnect(peripheralUUID: deviceID)

        print("✅ BT Manager: Removed from connectedPeripherals - total: \(connectedPeripherals.count)")
        print("📊 BT Manager: State after disconnect - discoveredDevices: \(discoveredDevices.count), connectedPeripherals: \(connectedPeripherals.count)")
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

    func didReceiveStoppedRanging(peripheralUUID: UUID) {
        print("🛑 BT Manager: didReceiveStoppedRanging(peripheral: \(peripheralUUID.uuidString.prefix(8)))")
        discoveredDevices.removeValue(forKey: peripheralUUID)
        connectedPeripherals.removeValue(forKey: peripheralUUID)
        uwbManager.stopRanging(to: peripheralUUID)
    }

    func didExchangeUWBToken(for deviceID: UUID) {
        print("📍 BT Manager: didExchangeUWBToken(\(deviceID.uuidString.prefix(8)))")
        guard !uwbManager.isRanging(to: deviceID) else {
            print("⚠️ BT Manager: Already ranging with \(deviceID.uuidString.prefix(8)), skipping")
            return
        }
        uwbManager.startRanging(to: deviceID)
        print("✅ BT Manager: Started UWB ranging with \(deviceID.uuidString.prefix(8))")
        print("📊 BT Manager: State after UWB token exchange - discoveredDevices: \(discoveredDevices.count), connectedPeripherals: \(connectedPeripherals.count)")
    }
}
