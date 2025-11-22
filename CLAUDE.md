# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An iOS Bluetooth Low Energy (BLE) application that discovers and connects with nearby devices. The app simultaneously acts as both a peripheral (advertising) and central (scanning) device to facilitate peer-to-peer discovery.

## Build Commands

```bash
# Build the project
xcodebuild -scheme boop-ios -configuration Debug build

# Build for simulator (specify simulator name)
xcodebuild -scheme boop-ios -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for device
xcodebuild -scheme boop-ios -destination 'generic/platform=iOS' build

# Clean build folder
xcodebuild -scheme boop-ios clean
```

## Running the App

This project must be run from Xcode as it requires:
- Bluetooth permissions (configured in Info.plist)
- Physical device or simulator with BLE support
- Code signing (currently set to automatic with team P3PR8G7GB9)

Open `boop-ios.xcodeproj` in Xcode and run using Cmd+R.

## Architecture

### Bluetooth Layer

The app uses a unified **BluetoothManager** approach for simultaneous advertising and scanning:

- **BluetoothManager** (`BluetoothManager.swift`): Main coordinator that manages both `CBPeripheralManager` (advertising) and `CBCentralManager` (scanning). Uses a dual-ready pattern to ensure both managers are powered on before starting operations. Implements automatic stale device removal with a 5-second threshold.

- **Service UUID**: `D3A42A7C-DA0E-4D2C-AAB1-88C77E018A5F` - Used for both advertising and discovery

Note: There are also legacy/unused `BluetoothCentral.swift` and `BluetoothPeripheral.swift` files that use a topic-based pattern with UUID `1234`. These are not currently integrated with the main UI.

### UI Layer

- **ContentView**: Main list view using SwiftData for persistence (displays timestamped items)
- **ConnectView**: Bluetooth connection view that instantiates BluetoothManager and displays discovered device UUIDs. Lifecycle-aware: starts scanning/advertising on appear, stops on disappear.

### Data Layer

- **SwiftData** with `Item` model for basic persistence
- `ModelContainer` configured in `boop_iosApp.swift`

## Key Permissions

The app declares Bluetooth permissions in the generated Info.plist:
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

## Project Configuration

- **Deployment Target**: iOS 18.2
- **Swift Version**: 5.0
- **Devices**: iPhone and iPad (universal)
- **Bundle ID**: `com.anonymous.boop-ios`
- **Team ID**: P3PR8G7GB9
