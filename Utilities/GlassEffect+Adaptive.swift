import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlass(in shape: some Shape = .capsule) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self
        }
    }
}
