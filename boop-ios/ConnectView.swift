import SwiftUI

struct ConnectView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var selectedDeviceID: UUID?
    @State private var messageToSend: String = "Hello from Boop!"
    @State private var showingSendSheet = false

    var body: some View {
        VStack {
            Text("Nearby Devices")
                .font(.headline)
                .padding()

            List(bluetoothManager.nearbyDevices, id: \.self) { id in
                HStack {
                    VStack(alignment: .leading) {
                        Text("Device")
                            .font(.headline)
                        Text(id.uuidString)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button("Connect") {
                        selectedDeviceID = id
                        bluetoothManager.connect(to: id)
                        showingSendSheet = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingSendSheet) {
            if let deviceID = selectedDeviceID {
                SendDataView(
                    bluetoothManager: bluetoothManager,
                    deviceID: deviceID,
                    messageToSend: $messageToSend
                )
            }
        }
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

struct SendDataView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let deviceID: UUID
    @Binding var messageToSend: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Connected to Device")
                    .font(.headline)

                Text(deviceID.uuidString)
                    .font(.caption)
                    .foregroundColor(.gray)

                TextField("Enter message", text: $messageToSend)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button("Send Message") {
                    if let data = messageToSend.data(using: .utf8),
                       let peripheral = bluetoothManager.connectedPeripherals[deviceID] {
                        // Wait a moment for characteristic discovery
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            bluetoothManager.sendData(data, to: peripheral)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Send Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Disconnect") {
                        bluetoothManager.disconnect(from: deviceID)
                        dismiss()
                    }
                }
            }
        }
    }
}
