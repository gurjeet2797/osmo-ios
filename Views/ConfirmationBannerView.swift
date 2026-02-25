import SwiftUI

struct ConfirmationBannerView: View {
    let prompt: String
    let onConfirm: () -> Void
    let onDecline: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Text(prompt)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            HStack(spacing: 12) {
                Button {
                    onDecline()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.06))
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                }

                Button {
                    onConfirm()
                } label: {
                    Text("Confirm")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.12))
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.05))
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}
