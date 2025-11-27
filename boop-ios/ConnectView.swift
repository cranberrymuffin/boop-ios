import SwiftUI

struct ConnectView: View {
    @StateObject private var viewModel = ConnectViewModel()
    @State private var showingSendSheet = false
    
//    var showingWaitingForResponse: Bool {
//        viewModel.waitingForResponse
//    }
//    
//    var showingReceivedRequestModal: Bool {
//        viewModel.connectionRequest != nil
//    }
//    var showingReceivedResponseModal: Bool {
//        viewModel.connectionResponse != nil
//    }
//    
    var showingModal: Bool = false
//    {
//        showingReceivedRequestModal || showingReceivedResponseModal || showingWaitingForResponse
//    }

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
                            deviceName: viewModel.deviceName(for: id)
                        ) {
                            viewModel.onAddFriend(to: id)
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
//                if showingReceivedRequestModal {
//                    FriendRequestModalView(
//                        requester: viewModel.getRequesterNameFromRequest(),
//                        onAccept: { viewModel.onAcceptFriendRequest(to: viewModel.connectedDeviceID) },
//                        onReject: { viewModel.onRejectFriendRequest(to: viewModel.connectedDeviceID) }
//                    )
//                }
//                if showingReceivedResponseModal {
//                    FriendRequestResultModalView(requestee: viewModel.getRequesteeNameFromResponse(), result: viewModel.getRequestResult())
//                }
//                if showingWaitingForResponse {
//                    WaitingForResponseView()
//                }
            }
        }
//        .animation(.default, value: showingModal)
    }
    
    struct WaitingForResponseView: View {
        var body: some View {
            VStack(spacing: 20) {
                Text("Waiting for response")
                    .font(.title)
             }
            .padding()
            .navigationTitle("WaitingForResponseModal")
        }
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
            .navigationTitle("FriendRequestResultModal")
        }
    }
    
    struct FriendRequestModalView: View {
        let requester: String
        let onAccept: () -> Void
        let onReject: () -> Void
        @Environment(\.dismiss) var dismiss
        
        let requestResultModalText = {
            (requester: String) -> (String) in
            return "\(requester) has sent you a friend request"
        }

        var body: some View {
            VStack(spacing: 20) {
                Text(requestResultModalText(requester))
                    .font(.title)
                
                Spacer()
                
                HStack {
                    Button("Accept") {
                        onAccept()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Reject") {
                        onReject()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .navigationTitle("FriendRequestModal")
        }
    }

    struct DeviceRow: View {
        let deviceID: UUID
        let deviceName: String
        let onAddFriend: () -> Void
        
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
                    Button("Add Friend") {
                        onAddFriend()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
}
