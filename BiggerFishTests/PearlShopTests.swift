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
            #expect(!item.name.isEmpty)
            let look = PlayerLook().wearing(item)
            switch item.kind {
            case .color: #expect(PearlShopArt.colors[item.id] != nil, "\(item.id)")
            case .pattern: #expect(look.style.pattern != .plain || PearlShopArt.markings(item) != nil, "\(item.id)")
            case .hat: #expect(PearlShopArt.hat(item) != nil, "\(item.id)")
            case .face: #expect(PearlShopArt.face(item) != nil, "\(item.id)")
            case .trail:
                #expect(look.trail.flatMap { GameTuning.pearlTrailEvery[$0] } != nil, "\(item.id)")
                #expect(look.trail.flatMap { GameTuning.pearlTrailSeconds[$0] } != nil, "\(item.id)")
            }
        }
        #expect(Set(items.map(\.kind)) == Set(PearlItem.Kind.allCases))
        // Sold for pearls, or earned and never sold.
        for item in items {
            #expect(item.earnedBy == nil ? item.price > 0 : item.price == 0 && item.season == nil && !item.onSale(), "\(item.id)")
        }
    }

    /// Nothing you wear makes your fish look bigger: colors and patterns stay inside your body, and a hat stays inside
    /// your length and stands no more than its headroom above your back fin.
    @Test func nothingMakesYouLookBigger() {
        let plain = PlayerLook().fish().calculateAccumulatedFrame()
        for item in GameTuning.pearlShop where item.kind != .trail {
            let fish = PlayerLook().wearing(item).fish()
            // The red nose is the one exception (Kraig, 2026-10-25): its glow spills past you, and it sits on the tip of
            // your face, standing a little past it. Nothing else may glow.
            var lights: [SKNode] = []
            fish.enumerateChildNodes(withName: "//\(PearlShopArt.lightName)") { light, _ in lights.append(light) }
            #expect(lights.isEmpty || item.id == "face.nose", "\(item.name) glows")
            lights.forEach { $0.removeFromParent() }
            let worn = fish.calculateAccumulatedFrame()
            let headroom = item.kind == .hat ? GameTuning.pearlHatHeadroom * FishNode.referenceRadius : 0
            let nose = item.id == "face.nose" ? 0.1 * FishNode.referenceRadius : 0
            #expect(worn.maxY <= plain.maxY + headroom + 0.01, "\(item.name) is \(worn.maxY - plain.maxY - headroom) too tall")
            #expect(worn.minY >= plain.minY - 0.01 && worn.minX >= plain.minX - 0.01 && worn.maxX <= plain.maxX + nose + 0.01,
                    "\(item.name)")
        }
    }

    /// A look saved by a later version, with things this one doesn't sell (or under the wrong kind), wears the rest.
    @Test func aLookWithUnknownThingsWearsWhatItKnows() {
        let look = PlayerLook(ids: ["hat": "hat.crown", "trail": "trail.lasers", "color": "hat.beanie", "cape": "cape.red"])
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

    /// A limited edition is on sale only in its season, every year (Christmas's runs across the new year). Whoever bought
    /// one keeps it, and wears it out of season too.
    @Test func limitedEditionsSellOnlyInTheirSeason() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let christmas = PearlSeason.christmas
        for (date, onSale) in [(day(2026, 11, 30), false), (day(2026, 12, 1), true), (day(2026, 12, 25), true),
                               (day(2027, 1, 1), true), (day(2027, 1, 6), true), (day(2027, 1, 7), false), (day(2027, 7, 4), false)] {
            #expect(christmas.contains(date, calendar: calendar) == onSale, "\(date)")
        }
        // A player whose preferred calendar is another still finds Christmas in December: its days are the Gregorian's.
        for identifier in [Calendar.Identifier.hebrew, .islamicUmmAlQura, .buddhist] {
            var preferred = Calendar(identifier: identifier)
            preferred.timeZone = calendar.timeZone
            let seasonal = PearlSeason.calendar(preferring: preferred)
            #expect(seasonal.identifier == .gregorian && seasonal.timeZone == preferred.timeZone)
            #expect(christmas.contains(day(2026, 12, 25), calendar: seasonal), "\(identifier)")
            #expect(!christmas.contains(day(2027, 7, 4), calendar: seasonal), "\(identifier)")
        }
        let santa = try item("hat.santa"), antlers = try item("hat.antlers")
        #expect(santa.season == .christmas && antlers.season == .christmas)
        #expect(try item("hat.baseball").season == nil && item("trail.cropduster").season == nil)
        let progress = device(cloud: nil)
        progress.earnPearls(300)
        #expect(!progress.buy(santa, today: day(2027, 6, 1)) && !progress.owns(santa) && progress.pearls == 300)
        #expect(progress.buy(santa, today: day(2026, 12, 10)) && progress.look[.hat] == santa && progress.pearls == 200)
        progress.wear(progress.look.without(.hat))
        progress.wear(progress.look.wearing(santa))
        #expect(progress.look[.hat] == santa)
    }

    /// A look that's earned is never sold: an Open Water run earns it (and says so), or a crown on the map does, judged from
    /// what's saved, so what was done before it existed counts. The gold crown, sold before it was earned, stays its
    /// buyers'.
    @Test func earnedLooksComeFromWhatYouveDone() throws {
        let progress = device(cloud: nil)
        progress.earnPearls(1000)
        let starfish = try item("hat.starfish"), shark = try item("hat.sharkfin"), comet = try item("trail.comet")
        let champion = try item("pattern.champion")
        let silver = try item("hat.crown.silver"), gold = try item("hat.crown"), diamond = try item("hat.crown.diamond")
        #expect(progress.earnedLooks.isEmpty && !progress.buy(shark) && !progress.owns(shark) && progress.pearls == 1000)
        #expect(progress.recordOpenWaterRun(fish: 49, furthest: 1).isEmpty)
        #expect(Set(progress.recordOpenWaterRun(fish: 50, furthest: 2).map(\.id)) == [starfish.id, shark.id])
        #expect(progress.owns(starfish) && progress.owns(shark) && !progress.owns(comet))
        progress.wear(progress.look.wearing(shark))
        #expect(progress.look[.hat] == shark)
        // A worse run earns nothing more; a better one, what's left.
        #expect(progress.recordOpenWaterRun(fish: 30, furthest: 1).isEmpty)
        #expect(Set(progress.recordOpenWaterRun(fish: 100, furthest: 5).map(\.id)) == [champion.id, comet.id])
        #expect(progress.pearls == 1000)

        // The crowns, from the map's: a world conquered, a Deep End, then every Deep End.
        #expect(!progress.owns(silver) && !progress.owns(gold) && !progress.owns(diamond))
        for index in 0..<ArcadeWorld.mainLevelCount { progress.clear(.shallowReef, index, seconds: 20) }
        #expect(progress.owns(silver) && !progress.owns(gold))
        for index in ArcadeWorld.mainLevelCount..<ArcadeWorld.shallowReef.levelCount { progress.clear(.shallowReef, index, seconds: 20) }
        #expect(progress.owns(gold) && !progress.owns(diamond))
        for world in ArcadeWorld.campaign {
            for index in 0..<world.levelCount { progress.clear(world, index, seconds: 20) }
        }
        #expect(progress.owns(diamond))

        // Bought before it was earned: still yours.
        let bought = device(#"{"ownedLooks":["hat.crown"],"pearlsEarned":{"a":200},"pearlsSpent":{"a":200}}"#, cloud: nil)
        #expect(bought.owns(gold) && !bought.owns(silver))
    }

    /// Looks added since the first shop are new until you've seen their shelf; what's been seen is kept and synced (both
    /// devices' seen looks together).
    @Test func newLooksStayNewUntilSeen() throws {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        let progress = ArcadeProgress(defaults: defaults, cloud: nil)
        let beanie = try item("hat.beanie"), tiara = try item("hat.tiara"), comet = try item("trail.comet")
        #expect(!progress.isNew(beanie) && progress.isNew(tiara) && progress.isNew(comet))
        progress.sawLooks(GameTuning.pearlShop.filter { $0.kind == .hat })
        #expect(!progress.isNew(tiara) && progress.isNew(comet))
        #expect(!ArcadeProgress(defaults: defaults, cloud: nil).isNew(tiara))
        let decoder = JSONDecoder()
        let phone = try decoder.decode(ArcadeSave.self, from: Data(#"{"seenLooks":["hat.tiara"]}"#.utf8))
        let pad = try decoder.decode(ArcadeSave.self, from: Data(#"{"seenLooks":["trail.comet"]}"#.utf8))
        #expect(phone.merged(withCloud: pad).seenLooks == ["hat.tiara", "trail.comet"])
        #expect(pad.merged(withCloud: phone).seenLooks == ["hat.tiara", "trail.comet"])
    }

    /// An outfit saves what you're wearing to put it all back on in a tap, as much of it as you still own; each slot keeps
    /// its latest save across devices.
    @Test func outfitsPutBackWhatYouWore() throws {
        let progress = device(cloud: nil)
        progress.earnPearls(500)
        let beanie = try item("hat.beanie"), ruby = try item("color.ruby"), bubbles = try item("trail.bubbles")
        for each in [beanie, ruby, bubbles] { #expect(progress.buy(each)) }
        let wearing = progress.look
        #expect(wearing[.hat] == beanie && wearing[.color] == ruby && wearing[.trail] == bubbles)
        #expect(progress.outfit(1) == nil)
        progress.saveOutfit(1)
        progress.wear(.plain)
        #expect(progress.look == .plain && progress.outfit(1) == wearing)
        progress.wear(try #require(progress.outfit(1)))
        #expect(progress.look == wearing)

        let decoder = JSONDecoder()
        let older = try decoder.decode(ArcadeSave.self, from: Data(#"{"savedOutfits":{"1":{"items":{"hat":"hat.beanie"},"changed":100},"2":{"items":{},"changed":5}}}"#.utf8))
        let newer = try decoder.decode(ArcadeSave.self, from: Data(#"{"savedOutfits":{"1":{"items":{"hat":"hat.flower"},"changed":200}}}"#.utf8))
        for merged in [older.merged(withCloud: newer), newer.merged(withCloud: older)] {
            #expect(merged.savedOutfits?["1"]?.items == ["hat": "hat.flower"] && merged.savedOutfits?["2"] != nil)
        }
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
        #expect(ArcadeResultAction.choices(passed: false, hasNext: true, shop: true, outOfRuns: true) == [.unlock, .shop, .levels])
        #expect(ArcadeResultAction.choices(passed: false, hasNext: true) == [.tryAgain, .levels])
    }
}
