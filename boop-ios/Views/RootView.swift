import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var boopManager: BoopManager

    var body: some View {
        MainTabView()
            .pageBackground()
            .onAppear { boopManager.start() }
    }
}

#Preview {
    RootView()
}
