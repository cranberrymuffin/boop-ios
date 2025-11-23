//
//  BluetoothController.swift
//  boop-ios
//
//  Created by Claude on 11/22/25.
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
    @Published var connectionRequest: ConnectionRequest? = nil
    @Published var connectionResponse: ConnectionResponse? = nil
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastReceivedMessage: String = ""
    @Published var errorMessage: String?

    // MARK: - Private Properties
    private let bluetoothManager = BluetoothManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Enums
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }

    // MARK: - Init
    init() {
        setupObservers()
    }

    // MARK: - Setup
    private func setupObservers() {
        // Observe nearby devices changes
        bluetoothManager.$nearbyDevices
            .receive(on: DispatchQueue.main)
            .assign(to: &$nearbyDevices)
        bluetoothManager.$connectionRequest
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionRequest)
        bluetoothManager.$connectionResponse
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionResponse)
    }

    // MARK: - Public Methods
    func startScanning() {
        bluetoothManager.start()
    }

    func stopScanning() {
        bluetoothManager.stop()
        nearbyDevices = []
    }

    func connect(to deviceID: UUID) async {
        connectionState = .connecting
        connectedDeviceID = deviceID
        await bluetoothManager.connect(to: deviceID)

        // Simulate connection success after a delay
        // In a real implementation, this would be triggered by a delegate callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.connectionState = .connected
        }
    }

    func disconnect() {
        guard let deviceID = connectedDeviceID else { return }
        bluetoothManager.disconnect(from: deviceID)
        connectionState = .disconnected
        connectedDeviceID = nil
    }

    func onConnect(to deviceID: UUID) {
        guard let peripheral = bluetoothManager.connectedPeripherals[deviceID],
              let senderUUID = UIDevice.current.identifierForVendor else {
            errorMessage = "Cannot send connection request"
            return
        }

        let message = BluetoothMessage(
            senderUUID: senderUUID,
            messageType: .connectionRequest,
            payload: Data()
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.bluetoothManager.sendMessage(message, to: peripheral)
        }
    }
    
    func getRequesteeName() -> String {
        return connectionResponse?.requesterUUID.uuidString ?? "Unknown"
    }
    
    func getRequestResult() -> Bool {
        return connectionResponse?.accepted ?? false
    }

    func acceptConnection(to deviceID: UUID) {
        guard let peripheral = bluetoothManager.connectedPeripherals[deviceID],
              let senderUUID = UIDevice.current.identifierForVendor else { return }

        let message = BluetoothMessage(
            senderUUID: senderUUID,
            messageType: .connectionAccept,
            payload: Data()
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.bluetoothManager.sendMessage(message, to: peripheral)
        }
    }

    func rejectConnection(to deviceID: UUID) {
        guard let peripheral = bluetoothManager.connectedPeripherals[deviceID],
              let senderUUID = UIDevice.current.identifierForVendor else { return }

        let message = BluetoothMessage(
            senderUUID: senderUUID,
            messageType: .connectionReject,
            payload: Data()
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.bluetoothManager.sendMessage(message, to: peripheral)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helper Methods
    func deviceName(for uuid: UUID) -> String {
        return "Device \(uuid.uuidString.prefix(8))"
    }

    func isConnected(to deviceID: UUID) -> Bool {
        return connectedDeviceID == deviceID && connectionState == .connected
    }
}
