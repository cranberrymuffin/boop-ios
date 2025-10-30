//
//  BluetoothCentral.swift
//  boop-ios
//
//  Created by Aparna Natarajan on 10/30/25.
//


import CoreBluetooth

class BluetoothCentral: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [(peripheral: CBPeripheral, rssi: NSNumber, topic: String)] = []
    private let targetTopic: String
    
    init(targetTopic: String) {
        self.targetTopic = targetTopic
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [CBUUID(string: "1234")],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String else { return }
        if name.contains("Topic:\(targetTopic)") {
            discoveredPeripherals.append((peripheral, RSSI, targetTopic))
            print("Found \(targetTopic) device: \(peripheral.name ?? "?") RSSI: \(RSSI)")
        }
    }
}
