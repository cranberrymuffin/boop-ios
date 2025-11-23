# Bluetooth Binary Protocol

## Overview
This app uses a custom binary protocol for Bluetooth Low Energy (BLE) communication instead of plain text strings. This provides type safety, precise schema definition, and efficient data transfer.

## Message Format

```
[Sender UUID: 16 bytes][Message Type: 1 byte][Payload Length: 2 bytes][Payload: variable]
```

**Total overhead**: 19 bytes minimum

### Field Details

| Field | Size | Type | Description |
|-------|------|------|-------------|
| Sender UUID | 16 bytes | Binary | UUID of the device sending the message |
| Message Type | 1 byte | UInt8 | Type of message (see Message Types below) |
| Payload Length | 2 bytes | UInt16 (big-endian) | Length of payload in bytes (0-65535) |
| Payload | Variable | Binary | Message-specific data |

## Message Types

```swift
enum MessageType: UInt8 {
    case connectionRequest = 0x01  // Request to connect
    case connectionAccept = 0x02   // Accept connection request
    case connectionReject = 0x03   // Reject connection request
    case textMessage = 0x04        // Text message (UTF-8)
    case disconnect = 0x05         // Disconnect notification
}
```

## Implementation

### Encoding Example
```swift
let message = BluetoothMessage(
    senderUUID: UIDevice.current.identifierForVendor!,
    messageType: .textMessage,
    text: "Hello!"
)
let data = message.encode() // Returns Data
```

### Decoding Example
```swift
if let message = BluetoothMessage.decode(data) {
    print("From: \(message.senderUUID)")
    print("Type: \(message.messageType)")
    if let text = message.textPayload {
        print("Message: \(text)")
    }
}
```

## Key Benefits

1. **Type Safety**: Enum-based message types prevent invalid messages
2. **Schema Enforcement**: Fixed 19-byte header ensures consistent format
3. **Sender Identification**: Every message includes sender UUID, solving the CBATTRequest limitation
4. **Compact**: ~19 bytes overhead vs 100+ bytes for JSON
5. **Fast**: Direct byte extraction, no parsing overhead
6. **Extensible**: Easy to add new message types

## Usage in BluetoothManager

### Sending Messages
```swift
// Send text message (convenience method)
bluetoothManager.sendTextMessage("Hello!", to: peripheral)

// Send custom message type
let message = BluetoothMessage(
    senderUUID: myUUID,
    messageType: .connectionRequest,
    payload: Data()
)
bluetoothManager.sendMessage(message, to: peripheral)
```

### Receiving Messages
Messages are automatically decoded in `peripheralManager(_:didReceiveWrite:)`:
```swift
case .textMessage:
    if let text = message.textPayload {
        print("💬 Message: \(text)")
    }
case .connectionReject:
    disconnect(from: message.senderUUID) // Now we know who to disconnect!
```

## Future Extensions

The protocol can easily support:
- File transfer (add `.fileTransfer` type)
- Voice messages (add `.audioMessage` type)
- Images (add `.imageMessage` type)
- Custom binary data (add `.binaryData` type)

Simply add new enum cases and handle them in the switch statement.
