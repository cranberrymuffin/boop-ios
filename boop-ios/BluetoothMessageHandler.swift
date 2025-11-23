//
//  BluetoothMessageHandler.swift
//  boop-ios
//

import Foundation
import CoreBluetooth

/// Protocol for handling different types of Bluetooth messages
protocol BluetoothMessageHandlerDelegate: AnyObject {
    func handleConnectionRequest(from senderUUID: UUID)
    func handleConnectionAccept(from senderUUID: UUID)
    func handleConnectionReject(from senderUUID: UUID)
    func handleDisconnect(from senderUUID: UUID)
}

/// State error for message handler
enum BluetoothMessageHandlerError: Error {
    case noDelegateSet
    case invalidState(String)

    var localizedDescription: String {
        switch self {
        case .noDelegateSet:
            return "BluetoothMessageHandler: No delegate set. Cannot process messages."
        case .invalidState(let message):
            return "BluetoothMessageHandler: Invalid state - \(message)"
        }
    }
}

/// Handles routing and processing of incoming Bluetooth messages
class BluetoothMessageHandler {
    weak var delegate: BluetoothMessageHandlerDelegate?

    init(delegate: BluetoothMessageHandlerDelegate? = nil) {
        self.delegate = delegate
    }

    // MARK: - Message Handling
    func handle(_ message: BluetoothMessage) throws {
        try verifyState()

        print("📥 Received \(message.messageType) from \(message.senderUUID)")

        switch message.messageType {
        case .connectionRequest:
            try handleConnectionRequest(message)
        case .connectionAccept:
            try handleConnectionAccept(message)
        case .connectionReject:
            try handleConnectionReject(message)
        case .disconnect:
            try handleDisconnect(message)
        }
    }

    // MARK: - State Verification
    private func verifyState() throws {
        guard delegate != nil else {
            throw BluetoothMessageHandlerError.noDelegateSet
        }
    }

    // MARK: - Private Handlers
    private func handleConnectionRequest(_ message: BluetoothMessage) throws {
        try verifyState()
        print("🔔 Connection request from \(message.senderUUID)")
        delegate?.handleConnectionRequest(from: message.senderUUID)
    }

    private func handleConnectionAccept(_ message: BluetoothMessage) throws {
        try verifyState()
        print("✅ Connection accepted by \(message.senderUUID)")
        delegate?.handleConnectionAccept(from: message.senderUUID)
    }

    private func handleConnectionReject(_ message: BluetoothMessage) throws {
        try verifyState()
        print("❌ Connection rejected by \(message.senderUUID)")
        delegate?.handleConnectionReject(from: message.senderUUID)
    }

    private func handleDisconnect(_ message: BluetoothMessage) throws {
        try verifyState()
        print("🔌 Disconnect request from \(message.senderUUID)")
        delegate?.handleDisconnect(from: message.senderUUID)
    }
}
