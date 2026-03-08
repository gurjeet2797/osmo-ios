import SwiftUI

struct MacCosmicBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.02, blue: 0.06),
                Color(red: 0.04, green: 0.03, blue: 0.10),
                Color(red: 0.02, green: 0.02, blue: 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
