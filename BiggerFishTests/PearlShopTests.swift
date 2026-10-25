import FishKit
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The pearl shop: what it sells only changes how your fish looks, never how big, and the pearls and looks a player
/// has are saved, synced, and never lost.
struct PearlShopTests {
    private func device(_ json: String? = nil, cloud: FakeCloud?) -> ArcadeProgress {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        if let json { defaults.set(Data(json.utf8), forKey: ArcadeProgress.key) }
        return ArcadeProgress(defaults: defaults, cloud: cloud)
    }

    private func item(_ id: String) throws -> PearlItem { try #require(PearlItem.item(id)) }

    // MARK: What's sold

    /// Every item's ID is saved, so each is one of a kind and says what kind it is; each draws as its kind does.
    @Test func everyItemIsOneOfAKindAndDraws() {
        let items = GameTuning.pearlShop
        #expect(Set(items.map(\.id)).count == items.count)
        for item in items {
            #expect(item.id.hasPrefix(item.kind.rawValue + "."), "\(item.id)")
            #expect(item.price > 0 && !item.name.isEmpty)
            let look = PlayerLook().wearing(item)
            switch item.kind {
            case .color: #expect(PearlShopArt.colors[item.id] != nil, "\(item.id)")
            case .pattern: #expect(look.style.pattern != .plain || PearlShopArt.markings(item) != nil, "\(item.id)")
            case .hat: #expect(PearlShopArt.hat(item) != nil, "\(item.id)")
            case .trail: #expect(look.trail.flatMap { GameTuning.pearlTrailEvery[$0] } != nil, "\(item.id)")
            }
        }
        #expect(Set(items.map(\.kind)) == Set(PearlItem.Kind.allCases))
    }

    /// Nothing you wear makes your fish look bigger: colors and patterns stay inside your body, and a hat stays inside
    /// your length and stands no more than its headroom above your back fin.
    @Test func nothingMakesYouLookBigger() {
        let plain = PlayerLook().fish().calculateAccumulatedFrame()
        for item in GameTuning.pearlShop where item.kind != .trail {
            let worn = PlayerLook().wearing(item).fish().calculateAccumulatedFrame()
            let headroom = item.kind == .hat ? GameTuning.pearlHatHeadroom * FishNode.referenceRadius : 0
            #expect(worn.maxY <= plain.maxY + headroom + 0.01, "\(item.name) is \(worn.maxY - plain.maxY - headroom) too tall")
            #expect(worn.minY >= plain.minY - 0.01 && worn.minX >= plain.minX - 0.01 && worn.maxX <= plain.maxX + 0.01,
                    "\(item.name)")
        }
    }

    /// A look saved by a later version, with things this one doesn't sell (or under the wrong kind), wears the rest.
    @Test func aLookWithUnknownThingsWearsWhatItKnows() {
        let look = PlayerLook(ids: ["hat": "hat.crown", "trail": "trail.comet", "color": "hat.beanie", "cape": "cape.red"])
        #expect(look[.hat]?.id == "hat.crown" && look[.trail] == nil && look[.color] == nil)
        #expect(look.ids == ["hat": "hat.crown"])
    }

    // MARK: Pearls and buying

    @Test func pearlsBuyLooksThatArePutOn() throws {
        let progress = device(cloud: nil)
        let stars = try item("pattern.stars"), crown = try item("hat.crown")
        #expect(progress.pearls == 0 && progress.look == .plain)
        #expect(!progress.buy(stars))
        progress.earnPearls(130)
        #expect(progress.buy(stars))
        #expect(progress.pearls == 10 && progress.owns(stars) && progress.look[.pattern] == stars)
        // Bought already, or too dear: nothing changes.
        #expect(!progress.buy(stars) && !progress.buy(crown))
        #expect(progress.pearls == 10 && !progress.owns(crown))
        // Only what's owned is worn.
        progress.wear(progress.look.wearing(crown))
        #expect(progress.look[.hat] == nil && progress.look[.pattern] == stars)
        progress.wear(progress.look.without(.pattern))
        #expect(progress.look == .plain && progress.owns(stars))
    }

    /// A save from before the shop has no pearls and wears nothing, and still loads as it was.
    @Test func aSaveFromBeforeTheShopLoads() {
        let progress = device(ArcadeCloudSaveTests.firstVersion, cloud: nil)
        #expect(progress.pearls == 0 && progress.look == .plain && progress.isCleared(.shallowReef, 1))
    }

    // MARK: Syncing

    /// Two devices' pearls add up, and spending on one stays spent, even after iCloud keeps an older backup.
    @Test @MainActor func twoDevicesPearlsAddUpAndSpendingStays() async throws {
        let cloud = FakeCloud()
        let phone = device(cloud: cloud), pad = device(cloud: cloud)
        phone.earnPearls(30)
        pad.earnPearls(20)
        #expect(pad.pearls == 50)
        cloud.change(to: String(decoding: cloud.values[ArcadeProgress.key]!, as: UTF8.self))
        try await settle { phone.pearls == 50 }

        let stale = try JSONEncoder().encode(pad.save)
        #expect(phone.buy(try item("color.copper")))
        #expect(phone.pearls == 0)
        // The pad's older backup lands over the phone's: the phone keeps its spending, and so does iCloud.
        cloud.change(to: String(decoding: stale, as: UTF8.self))
        try await settle { cloud.save?.ownedLooks == ["color.copper"] }
        #expect(phone.pearls == 0 && phone.look[.color]?.id == "color.copper")
        cloud.change(to: String(decoding: cloud.values[ArcadeProgress.key]!, as: UTF8.self))
        try await settle { pad.save.ownedLooks == ["color.copper"] }
        #expect(pad.pearls == 0 && pad.save == phone.save)
    }

    /// What's worn is the look changed last, on whichever device; at the same moment, the same one either way round.
    @Test func theLookChangedLastIsWorn() throws {
        let decoder = JSONDecoder()
        let older = try decoder.decode(ArcadeSave.self, from: Data(#"{"ownedLooks":["hat.crown"],"wornLook":{"items":{"hat":"hat.crown"},"changed":100}}"#.utf8))
        let newer = try decoder.decode(ArcadeSave.self, from: Data(#"{"ownedLooks":["hat.beanie"],"wornLook":{"items":{"hat":"hat.beanie"},"changed":200}}"#.utf8))
        let tied = try decoder.decode(ArcadeSave.self, from: Data(#"{"wornLook":{"items":{"trail":"trail.bubbles"},"changed":200}}"#.utf8))
        #expect(older.merged(withCloud: newer).wornLook?.items == ["hat": "hat.beanie"])
        #expect(newer.merged(withCloud: older).wornLook?.items == ["hat": "hat.beanie"])
        #expect(newer.merged(withCloud: older).ownedLooks == ["hat.crown", "hat.beanie"])
        #expect(newer.merged(withCloud: tied) == tied.merged(withCloud: newer))
    }

    /// The shop's fields merge the same either way round and however often, and an empty side takes nothing away.
    @Test func mergingPearlsIsTheSameEitherWayAndRepeatable() throws {
        let saves = try [
            ArcadeSave(),
            JSONDecoder().decode(ArcadeSave.self, from: Data(ArcadeCloudSaveTests.firstVersion.utf8)),
            JSONDecoder().decode(ArcadeSave.self, from: Data(#"{"pearlsEarned":{"a":40,"b":7},"pearlsSpent":{"a":25},"ownedLooks":["hat.beanie"],"wornLook":{"items":{"hat":"hat.beanie"},"changed":5}}"#.utf8)),
            JSONDecoder().decode(ArcadeSave.self, from: Data(#"{"pearlsEarned":{"a":32,"c":60},"pearlsSpent":{"c":50},"ownedLooks":["trail.bubbles"],"wornLook":{"items":{"trail":"trail.bubbles"},"changed":9}}"#.utf8)),
        ]
        for a in saves {
            #expect(a.merged(withCloud: a) == a)
            for b in saves {
                let ab = a.merged(withCloud: b)
                #expect(ab == b.merged(withCloud: a))
                #expect(ab.merged(withCloud: b) == ab && ab.merged(withCloud: a) == ab)
                for (install, count) in (a.pearlsEarned ?? [:]).merging(b.pearlsEarned ?? [:], uniquingKeysWith: max) {
                    #expect(ab.pearlsEarned?[install] == count)
                }
                #expect((a.ownedLooks ?? []).isSubset(of: ab.ownedLooks ?? []) && (b.ownedLooks ?? []).isSubset(of: ab.ownedLooks ?? []))
            }
        }
        let merged = saves[2].merged(withCloud: saves[3])
        #expect(merged.pearlsEarned == ["a": 40, "b": 7, "c": 60] && merged.pearlsSpent == ["a": 25, "c": 50])
    }

    @MainActor private func settle(_ done: () -> Bool) async throws {
        for _ in 0..<100 where !done() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(done())
    }

    // MARK: The run's card

    @Test func anOpenWaterRunsCardOffersTheShop() {
        #expect(ArcadeResultAction.choices(passed: false, hasNext: true, shop: true) == [.tryAgain, .shop, .levels])
        #expect(ArcadeResultAction.choices(passed: false, hasNext: true) == [.tryAgain, .levels])
    }
}
