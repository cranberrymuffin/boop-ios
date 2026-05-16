import SwiftUI

struct BoopHistoryRow<Destination: View>: View {
    let count: Int
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        Section {
            NavigationLink(destination: destination()) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.staticWhite)
                    Text("Boop History")
                        .foregroundColor(.staticWhite)
                    Spacer()
                    Text("\(count)")
                        .font(.subtitle)
                        .foregroundColor(.staticWhite)
                }
                .padding(.vertical, Spacing.sm)
            }
        }
        .listRowBackground(Color.clear)
        .tint(.staticWhite)
    }
}
