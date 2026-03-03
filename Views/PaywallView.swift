import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var purchased = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))

            Text("Osmo Pro")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "infinity", text: "Unlimited requests")
                featureRow(icon: "magnifyingglass", text: "OpenClaw deep research")
                featureRow(icon: "eye", text: "Vision mode — photo analysis")
                featureRow(icon: "envelope", text: "Email summaries")
            }
            .padding(.horizontal, 32)

            Text(SubscriptionManager.shared.price + "/month")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            if purchased {
                Label("You're on Pro!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button {
                    purchasing = true
                    Task {
                        let success = await SubscriptionManager.shared.purchasePro()
                        purchasing = false
                        if success {
                            purchased = true
                            try? await Task.sleep(for: .seconds(1.5))
                            dismiss()
                        }
                    }
                } label: {
                    Text("Subscribe")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(.white)
                        )
                }
                .disabled(purchasing)
                .opacity(purchasing ? 0.5 : 1)
                .padding(.horizontal, 32)
            }

            Button("Restore Purchases") {
                Task { await SubscriptionManager.shared.restorePurchases() }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task {
            await SubscriptionManager.shared.loadProducts()
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
