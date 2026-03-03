import StoreKit

@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    private static let productID = "com.develloinc.osmo.pro.monthly"

    var isPro: Bool = false
    var isLoading: Bool = false

    private var product: Product?
    private var updateTask: Task<Void, Never>?

    private init() {
        updateTask = Task {
            await listenForTransactions()
        }
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            // Products unavailable
        }
    }

    var price: String {
        product?.displayPrice ?? "$4.99"
    }

    func purchasePro() async -> Bool {
        guard let product else { return false }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isPro = true
                // Verify with backend
                let apiClient = APIClient()
                _ = try? await apiClient.verifyReceipt(transactionId: String(transaction.id))
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.productID {
                isPro = true
                return
            }
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.productID {
                isPro = true
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.unverified
        case .verified(let value):
            return value
        }
    }

    enum StoreError: Error {
        case unverified
    }
}
