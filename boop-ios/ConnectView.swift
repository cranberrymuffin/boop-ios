import SwiftUI

struct ConnectView: View {
    @StateObject private var viewModel = ConnectViewModel()
    @State private var showingSendSheet = false
    @State private var showingWaitingForResponse = false
    
    var showingReceivedRequestModal: Bool {
        viewModel.connectionRequest != nil
    }
    var showingResponseToRequestModal: Bool {
        viewModel.connectionResponse != nil
    }
    
    var showingModal: Bool {
        showingReceivedRequestModal || showingResponseToRequestModal
    }

    var body: some View {
        ZStack {
            VStack {
                Text("Nearby Devices")
                    .font(.headline)
                    .padding()
                
                if viewModel.nearbyDevices.isEmpty {
                    Text("Scanning for devices...")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(viewModel.nearbyDevices, id: \.self) { id in
                        DeviceRow(
                            deviceID: id,
                            deviceName: viewModel.deviceName(for: id),
                            isConnected: viewModel.isConnected(to: id)
                        ) {
                            showingWaitingForResponse = true
                            viewModel.onConnect(to: id)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .onAppear {
                viewModel.startScanning()
            }
            .onDisappear {
                viewModel.stopScanning()
            }
            
            if showingModal {
                Color.black.opacity(0.4).ignoresSafeArea() // dim background
                if showingReceivedRequestModal {
                    
                }
                if showingReceivedResponseModal {
                    FriendRequestResultModalView(requestee: viewModel.getRequesteeName(), result: viewModel.getRequestResult())
                }
            }
        }
        .animation(.default, value: showingModal)
    }
    
    struct FriendRequestResultModalView: View {
        let requestee: String
        let result: Bool
        @Environment(\.dismiss) var dismiss
        
        let requestResultModalText = {
            (result: Bool, requestee: String) -> (String) in
            let action = result ? "accepted" : "rejected"
            return "\(requestee) \(action) your friend request"
        }

        var body: some View {
            VStack(spacing: 20) {
                Text(requestResultModalText(result, requestee))
                    .font(.title)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
//    struct SendDataView: View {
//        @ObservedObject var bluetoothManager: BluetoothManager
//        let deviceID: UUID
//        @Binding var messageToSend: String
//        @Environment(\.dismiss) var dismiss
//
//        var body: some View {
//            NavigationView {
//                VStack(spacing: 20) {
//                    Text("Connected to Device")
//                        .font(.headline)
//
//                    Text(deviceID.uuidString)
//                        .font(.caption)
//                        .foregroundColor(.gray)
//
//                    TextField("Enter message", text: $messageToSend)
//                        .textFieldStyle(.roundedBorder)
//                        .padding()
//
//                    Button("Send Message") {
//                        if let data = messageToSend.data(using: .utf8),
//                           let peripheral = bluetoothManager.connectedPeripherals[deviceID] {
//                            // Wait a moment for characteristic discovery
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//                                bluetoothManager.sendData(data, to: peripheral)
//                            }
//                        }
//                    }
//                    .buttonStyle(.borderedProminent)
//
//                    Spacer()
//                }
//                .padding()
//                .navigationTitle("Send Data")
//                .navigationBarTitleDisplayMode(.inline)
//                .toolbar {
//                    ToolbarItem(placement: .navigationBarTrailing) {
//                        Button("Disconnect") {
//                            bluetoothManager.disconnect(from: deviceID)
//                            dismiss()
//                        }
//                    }
//                }
//            }
//        }
//    }


    struct DeviceRow: View {
        let deviceID: UUID
        let deviceName: String
        let isConnected: Bool
        let onConnect: () -> Void
        
        var body: some View {
            HStack {
                VStack(alignment: .leading) {
                    Text(deviceName)
                        .font(.headline)
                    Text(deviceID.uuidString)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button("Connect") {
                        onConnect()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    
    private var connectionStatusText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .failed:
            return "Connection Failed"
        }
    }
    
    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            return .gray
        case .connecting:
            return .yellow
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }
}
