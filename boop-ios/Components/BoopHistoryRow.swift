import SwiftUI

struct BoopHistoryRow<Route: Hashable>: View {
    let count: Int
    let route: Route

    var body: some View {
        Section {
            NavigationLink(value: route) {
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
