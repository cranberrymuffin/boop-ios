//
//  BluetoothController.swift
//  boop-ios
//
//

import Foundation
import CoreBluetooth
import Combine
import UIKit

@MainActor
class ConnectViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var nearbyDevices: [UUID] = []
    @Published var connectedDeviceID: UUID? = nil
//    @Published var waitingForResponse: Bool = false
    @Published var connectionRequests: [UUID: ConnectionRequest] = [:]
    @Published var connectionResponses: [UUID: ConnectionResponse] = [:]
    @Published var lastReceivedMessage: String = ""
    @Published var errorMessage: String?

    // MARK: - Private Properties
    private lazy var bluetoothManager: BluetoothManager = {
        return getBluetoothManager()
    }()
    private var cancellables = Set<AnyCancellable>()


    // MARK: - Init
    init() {
        setupObservers()
    }
    
    private func getBluetoothManager() -> BluetoothManager {
        let uwbManager = UWBManager()
        return BluetoothManager(uwbManager: uwbManager)
    }

    // MARK: - Setup
    private func setupObservers() {
        // Observe nearby devices changes
        bluetoothManager.$nearbyDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$nearbyDevices)
    }

    // MARK: - Public Methods
    func startScanning() {
        bluetoothManager.start()
    }

    func stopScanning() {
        bluetoothManager.stop()
        nearbyDevices = []
    }

    func disconnect() {
        guard let deviceID = connectedDeviceID else { return }
        bluetoothManager.disconnect(from: deviceID)
        connectedDeviceID = nil
    }
    
    func onAcceptFriendRequest(to deviceID: UUID?) {
        if let dID = deviceID {
            guard let peripheral = bluetoothManager.connectedPeripherals[dID],
                  let senderUUID = UIDevice.current.identifierForVendor else { return }
            
            let message = BluetoothMessage(
                senderUUID: senderUUID,
                messageType: .connectionAccept,
                payload: Data()
            )
            
            self.bluetoothManager.sendMessage(message, to: peripheral)
        }
    }
    
    func onRejectFriendRequest(to deviceID: UUID?) {
        if let dID = deviceID {
            guard let peripheral = bluetoothManager.connectedPeripherals[dID],
                  let senderUUID = UIDevice.current.identifierForVendor else { return }
            
            let message = BluetoothMessage(
                senderUUID: senderUUID,
                messageType: .connectionReject,
                payload: Data()
            )
            
            self.bluetoothManager.sendMessage(message, to: peripheral)
        }
    }

    func onAddFriend(to deviceID: UUID) {
        guard let peripheral = bluetoothManager.connectedPeripherals[deviceID],
              let senderUUID = UIDevice.current.identifierForVendor else {
            errorMessage = "Cannot send connection request"
            return
        }
//        waitingForResponse = true
        
        // create temporary connection
        bluetoothManager.connect(to: deviceID)

        let message = BluetoothMessage(
            senderUUID: senderUUID,
            messageType: .connectionRequest,
            payload: Data()
        )

        // send friend request
        self.bluetoothManager.sendMessage(message, to: peripheral)
        
    }
    
//    func getRequesterNameFromRequest() -> String {
//        return connectionRequest?.requesterUUID.uuidString ?? "Unkown"
//    }
//    
//    func getRequesteeNameFromResponse() -> String {
//        return connectionResponse?.requesterUUID.uuidString ?? "Unknown"
//    }
//    
//    func getRequestResult() -> Bool {
//        return connectionResponse?.accepted ?? false
//    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helper Methods
    func deviceName(for uuid: UUID) -> String {
        return "Device \(uuid.uuidString.prefix(8))"
    }

}
