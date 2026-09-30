import Foundation
import StoreKit

// Math Reef is free to try, with a one-time purchase that unlocks every level. The free sample is
// the first few levels of each world, so a child of any grade can try their own math before a
// grown-up decides. The purchase screen sits behind the parental gate (a Kids-category rule).

/// Which levels are free without the unlock.
enum FreeSample {
    /// The first 3 levels of each world, but only 1 in Exponents (it has 3 in all).
    static func freeLevels(in world: World) -> Int {
        world.id == "exponents" ? 1 : 3
    }

    static func isFree(_ index: Int, in world: World) -> Bool {
        index < freeLevels(in: world)
    }

    /// Past the free line and not yet unlocked: tapping it asks for the unlock instead of playing.
    /// Checkpoints (skip tests) past the line count too, so they can't get around the purchase.
    static func needsUnlock(_ index: Int, in world: World, isUnlocked: Bool) -> Bool {
        !isUnlocked && !isFree(index, in: world)
    }
}

/// The one-time purchase that unlocks the whole reef (a non-consumable, shared with Family Sharing).
@MainActor
final class ReefPurchases {
    static let productID = "com.kraigstrong.mathreef.fullreef"

    enum PurchaseOutcome { case unlocked, pending, cancelled, failed }

    /// Cached so the level path draws correctly at launch and offline; StoreKit confirms it.
    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    /// Called on the main actor whenever `isUnlocked` changes (a purchase, restore, Ask to Buy
    /// approval, Family Sharing change, or refund).
    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private let unlockedKey = "mathReef.unlocked"
    private var updates: Task<Void, Never>?
    /// `AppStore.sync()`, which can ask to sign in. Tests replace it, since it waits on that prompt.
    private let syncWithAppStore: () async throws -> Void

    init(defaults: UserDefaults = .standard, syncWithAppStore: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        self.defaults = defaults
        self.syncWithAppStore = syncWithAppStore
        isUnlocked = defaults.bool(forKey: unlockedKey)
    }

    /// Starts listening for transactions and checks what's already owned. Call once at launch.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result, transaction.productID == Self.productID {
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
        Task { [weak self] in
            await self?.refresh()
            await self?.loadProduct()
        }
    }

    /// Re-reads current entitlements. Refunded and revoked purchases drop out of them.
    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    /// The localized price, e.g. "$4.99", once the product has loaded.
    var displayPrice: String? { product?.displayPrice }

    func purchase() async -> PurchaseOutcome {
        await loadProduct()
        guard let product else { return .failed }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                setUnlocked(true)
                return .unlocked
            case .success(.unverified):
                return .failed
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Syncs with the App Store (it may ask to sign in), then re-checks. True if unlocked.
    func restore() async -> Bool {
        try? await syncWithAppStore()
        await refresh()
        return isUnlocked
    }

    private func setUnlocked(_ unlocked: Bool) {
        guard unlocked != isUnlocked else { return }
        isUnlocked = unlocked
        defaults.set(unlocked, forKey: unlockedKey)
        onChange?()
    }
}
