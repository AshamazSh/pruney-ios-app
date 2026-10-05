import Foundation
import Observation
import StoreKit

nonisolated enum FreeAllowance: String, Identifiable {
    case deletions, replacements
    var id: Self { self }
    var limit: Int { self == .deletions ? 50 : 10 }
    var title: String { self == .deletions ? "deletions" : "resize or Make static actions" }
}

@MainActor @Observable
final class ProAccess {
    static let shared = ProAccess()
    static let productID = "com.ashamazsh.pruney.pro.lifetime"
    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var message: String?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    private var started = false
    private var entitlementGeneration = UUID()

    private init() {}

    func start() async {
        if !started {
            started = true
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    guard case .verified(let transaction) = result,
                          transaction.productID == Self.productID else { continue }
                    await self.refreshEntitlement()
                    await transaction.finish()
                }
            }
        }
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        let token = UUID()
        entitlementGeneration = token
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.productType == .nonConsumable,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        if entitlementGeneration == token { isPro = entitled }
    }

    func loadProduct() async {
        guard !isLoading else { return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first { $0.type == .nonConsumable }
            if product == nil { message = "The lifetime purchase is currently unavailable. Please try again later." }
        } catch { message = error.localizedDescription }
    }

    func purchase() async {
        guard let product, !isPurchasing, !isRestoring, !isPro else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.productID,
                      transaction.productType == .nonConsumable,
                      transaction.revocationDate == nil else {
                    message = "This purchase could not be verified. Please try restoring purchases."
                    return
                }
                entitlementGeneration = UUID()
                isPro = true
                await transaction.finish()
            case .pending:
                message = "Your purchase is pending approval. Your current item has not been selected."
            case .userCancelled:
                break
            @unknown default:
                message = "The purchase did not complete. Please try again."
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        guard !isRestoring, !isPurchasing else { return }
        isRestoring = true
        message = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isPro { message = "No lifetime purchase was found for this Apple Account." }
        } catch { message = error.localizedDescription }
    }

    func permits(deletions: Int, replacements: Int) -> Bool {
        isPro || (deletions <= FreeAllowance.deletions.limit && replacements <= FreeAllowance.replacements.limit)
    }

    isolated deinit { updatesTask?.cancel() }
}
