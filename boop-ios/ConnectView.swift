import SwiftUI

struct ConnectView: View {
    @StateObject private var bluetoothManager = BluetoothManager()

    var body: some View {
        VStack {
            Text("Nearby Devices")
                .font(.headline)
                .padding()

            List(bluetoothManager.nearbyDevices, id: \.self) { id in
                Text("Device: \(id.uuidString)")
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Start scanning and advertising when the view appears
            bluetoothManager.start()
        }
        .onDisappear {
            // Stop everything when leaving the view
            bluetoothManager.stop()
        }
    }
}
