import Combine
import Foundation
import StoreKit

// Bigger Fish is free to try, with a one-time purchase that unlocks every world and its Deep End. Free: all ten of
// Shallow Reef's levels and a taste of each other world. With the unlock every world is open from the start, so a
// player stuck in one can try another; a world's Deep End still opens when its level 10 is beaten.

/// What's free, and what needs the unlock.
enum ArcadeUnlock {
    /// A non-consumable. Product IDs are permanent once created in App Store Connect.
    static let productID = "com.kraigstrong.biggerfish.allworlds"

    /// Whether the game sells the unlock. Off in Release until the product is set up in App Store Connect (see
    /// docs/bigger-fish-testflight.md); until then everyone plays as if they'd bought it. Xcode builds sell it
    /// against BiggerFish.storekit.
    #if DEBUG
    static let isSelling = true
    #else
    static let isSelling = false
    #endif

    /// The main levels free in each world: all of Shallow Reef's, and the first few of every other world
    /// (`GameTuning.freeLevelsPerWorld`) so a player can see what they'd be buying. The Deep End is never free.
    static func freeLevels(in world: ArcadeWorld) -> Int {
        world == .shallowReef ? ArcadeWorld.mainLevelCount : min(GameTuning.freeLevelsPerWorld, ArcadeWorld.mainLevelCount)
    }

    /// Past the free levels without the unlock: tapping it offers the unlock instead of playing. Worlds still being
    /// prototyped (Xcode builds only) are never locked.
    static func needsUnlock(_ world: ArcadeWorld, _ index: Int, unlocked: Bool, selling: Bool = isSelling) -> Bool {
        selling && !unlocked && ArcadeWorld.campaign.contains(world) && index >= freeLevels(in: world)
    }

    /// Every world is open to choose from the start, except one with no free levels before the unlock.
    static func isWorldOpen(_ world: ArcadeWorld, unlocked: Bool, selling: Bool = isSelling) -> Bool {
        !needsUnlock(world, 0, unlocked: unlocked, selling: selling)
    }

    /// The worlds the unlock adds levels to beyond Shallow Reef, in map order: the ones its screen shows.
    static var worldsItOpens: [ArcadeWorld] {
        ArcadeWorld.campaign.filter { freeLevels(in: $0) < min($0.levelCount, ArcadeWorld.mainLevelCount) }
    }

    /// Every Deep End level in the campaign.
    static var deepEndLevels: Int { ArcadeWorld.campaign.reduce(0) { $0 + $1.deepEndCount } }
}

/// The one-time purchase that unlocks every world (a non-consumable, shared with Family Sharing if it's turned on
/// in App Store Connect). Modeled on Math Reef's `ReefPurchases`.
@MainActor
final class ArcadePurchases: ObservableObject {
    /// Raw values are what the paywall funnel reports (`ArcadeAnalytics.purchase`); the server accepts only these.
    enum PurchaseOutcome: String, CaseIterable { case unlocked, pending, cancelled, failed }

    /// Cached so the maps draw correctly at launch and offline; StoreKit confirms it.
    @Published private(set) var isUnlocked: Bool
    @Published private(set) var product: Product?

    private let defaults: UserDefaults
    private static let unlockedKey = "biggerFish.unlocked"
    private var updates: Task<Void, Never>?
    /// `AppStore.sync()`, which can ask to sign in. Tests replace it, since it waits on that prompt.
    private let syncWithAppStore: () async throws -> Void

    init(defaults: UserDefaults = .standard, syncWithAppStore: @escaping () async throws -> Void = { try await AppStore.sync() }) {
        self.defaults = defaults
        self.syncWithAppStore = syncWithAppStore
        isUnlocked = defaults.bool(forKey: Self.unlockedKey)
        #if DEBUG
        if let override = ArcadePlaytest.unlockOverride { isUnlocked = override; isOverridden = true }
        #endif
    }

    /// Xcode builds launched with -arcadeUnlocked keep what it says rather than asking StoreKit.
    private var isOverridden = false

    /// Starts listening for transactions and checks what's already owned. Call once at launch; does nothing while
    /// the unlock isn't on sale.
    func start() {
        guard ArcadeUnlock.isSelling, !isOverridden, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result, transaction.productID == ArcadeUnlock.productID {
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
            if case .verified(let transaction) = result, transaction.productID == ArcadeUnlock.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [ArcadeUnlock.productID]).first
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
        defaults.set(unlocked, forKey: Self.unlockedKey)
    }
}
