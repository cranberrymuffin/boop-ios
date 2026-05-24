import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \BoopInteraction.timestamp, order: .reverse)
    private var interactions: [BoopInteraction]

    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                HomeFeedBody(interactions: interactions.filter(\.hasContent))
            }
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Home")
                        .heading1Style()
                }
            }
            .navigationDestination(for: BoopInteraction.self) { interaction in
                InteractionDetailView(interaction: interaction)
            }
        }
    }
}

#Preview {
    HomeView(path: .constant(NavigationPath()))
        .modelContainer(for: BoopInteraction.self, inMemory: true)
}
