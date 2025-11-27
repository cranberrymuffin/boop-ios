//
//  BluetoothMessage.swift
//  boop-ios
//

import Foundation

/// Binary protocol for Bluetooth communication
/// Format: [UUID: 16 bytes][MessageType: 1 byte][PayloadLength: 2 bytes][Payload: variable]
struct BluetoothMessage {
    let senderUUID: UUID
    let messageType: MessageType
    let payload: Data

    enum MessageType: UInt8 {
        case connectionRequest = 0x01
        case connectionAccept = 0x02
        case connectionReject = 0x03
        case disconnect = 0x05
        case boop = 0x06
    }

    // MARK: - Encoding
    func encode() -> Data {
        var data = Data()

        // Add sender UUID (16 bytes)
        data.append(senderUUID.uuidData)

        // Add message type (1 byte)
        data.append(messageType.rawValue)

        // Add payload length (2 bytes, big-endian)
        let payloadLength = UInt16(payload.count)
        data.append(UInt8(payloadLength >> 8))
        data.append(UInt8(payloadLength & 0xFF))

        // Add payload
        data.append(payload)

        return data
    }

    // MARK: - Decoding
    static func decode(_ data: Data) -> BluetoothMessage? {
        // Minimum size: 16 (UUID) + 1 (type) + 2 (length) = 19 bytes
        guard data.count >= 19 else {
            print("⚠️ BluetoothMessage decode failed: data too short (\(data.count) bytes)")
            return nil
        }

        // Extract UUID (16 bytes)
        let uuidData = data.subdata(in: 0..<16)
        guard let uuid = UUID(data: uuidData) else {
            print("⚠️ BluetoothMessage decode failed: invalid UUID")
            return nil
        }

        // Extract message type (1 byte)
        guard let messageType = MessageType(rawValue: data[16]) else {
            print("⚠️ BluetoothMessage decode failed: unknown message type \(data[16])")
            return nil
        }

        // Extract payload length (2 bytes)
        let payloadLength = Int(data[17]) << 8 | Int(data[18])

        // Validate payload length
        guard data.count >= 19 + payloadLength else {
            print("⚠️ BluetoothMessage decode failed: payload length mismatch")
            return nil
        }

        // Extract payload
        let payload = data.subdata(in: 19..<(19 + payloadLength))

        return BluetoothMessage(
            senderUUID: uuid,
            messageType: messageType,
            payload: payload
        )
    }

    // MARK: - Convenience Initializers
    init(senderUUID: UUID, messageType: MessageType, payload: Data) {
        self.senderUUID = senderUUID
        self.messageType = messageType
        self.payload = payload
    }
}

// MARK: - UUID Extension
extension UUID {
    /// Convert UUID to 16-byte Data
    var uuidData: Data {
        var data = Data(count: 16)
        data.withUnsafeMutableBytes { buffer in
            var uuid = self.uuid
            withUnsafeBytes(of: &uuid) { uuidBuffer in
                buffer.copyMemory(from: uuidBuffer)
            }
        }
        return data
    }

    /// Create UUID from 16-byte Data
    init?(data: Data) {
        guard data.count == 16 else { return nil }
        let bytes = [UInt8](data)
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
