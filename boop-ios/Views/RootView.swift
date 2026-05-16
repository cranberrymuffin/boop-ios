import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        MainTabView()
            .pageBackground()
    }
}

#Preview {
    RootView()
}
