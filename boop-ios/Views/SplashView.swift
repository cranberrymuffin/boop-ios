import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(.accentPrimary)
            Spacer()
        }
        .pageBackground()
    }
}
