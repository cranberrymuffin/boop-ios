//
//  BluetoothPeripheral.swift
//  boop-ios
//
//  Created by Aparna Natarajan on 10/30/25.
//


import CoreBluetooth

class BluetoothPeripheral: NSObject, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager!
    private let topic: String
    
    init(topic: String) {
        self.topic = topic
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            let advertisementData: [String: Any] = [
                CBAdvertisementDataLocalNameKey: "Topic:\(topic)",
                CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "1234")]
            ]
            peripheralManager.startAdvertising(advertisementData)
        } else {
            peripheralManager.stopAdvertising()
        }
    }
}
