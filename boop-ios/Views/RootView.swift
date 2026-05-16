import SwiftUI
import SwiftData

struct RootView: View {
    @Binding var selectedTab: Int
    @Binding var selectedInteractionID: UUID?
    
    var body: some View {
        Group {
            MainTabView(selectedTab: $selectedTab, selectedInteractionID: $selectedInteractionID)
        }
        .pageBackground()
    }
}

#Preview {
    RootView(selectedTab: .constant(0), selectedInteractionID: .constant(nil))
}
