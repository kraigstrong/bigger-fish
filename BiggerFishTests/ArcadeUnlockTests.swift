import Foundation
import Testing
@testable import BiggerFish

/// Free to try: Shallow Reef's ten levels and a taste of every other world. The unlock opens every world from the
/// start, and each world's Deep End still opens with its level 10.
struct ArcadeUnlockTests {
    private func fresh() -> ArcadeProgress {
        ArcadeProgress(defaults: UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!)
    }

    @Test func shallowReefsTenLevelsAreFreeButNotItsDeepEnd() {
        for index in 0..<ArcadeWorld.mainLevelCount {
            #expect(!ArcadeUnlock.needsUnlock(.shallowReef, index, unlocked: false, selling: true))
        }
        for index in ArcadeWorld.mainLevelCount..<ArcadeWorld.shallowReef.levelCount {
            #expect(ArcadeUnlock.needsUnlock(.shallowReef, index, unlocked: false, selling: true))
        }
    }

    @Test func everyOtherWorldHasATasteThenTheUnlock() {
        for world in ArcadeWorld.campaign where world != .shallowReef {
            let free = ArcadeUnlock.freeLevels(in: world)
            #expect(free == GameTuning.freeLevelsPerWorld && free < ArcadeWorld.mainLevelCount)
            // With no free levels, the world is locked whole until the unlock.
            #expect(ArcadeUnlock.isWorldOpen(world, unlocked: false, selling: true) == (free > 0))
            if free > 0 { #expect(!ArcadeUnlock.needsUnlock(world, free - 1, unlocked: false, selling: true)) }
            #expect(ArcadeUnlock.needsUnlock(world, free, unlocked: false, selling: true))
            #expect(ArcadeUnlock.needsUnlock(world, ArcadeWorld.mainLevelCount, unlocked: false, selling: true))
        }
        #expect(ArcadeUnlock.worldsItOpens == [.jellyBloom, .kelpForest, .sunsetCove, .midnightZone])
        #expect(ArcadeUnlock.deepEndLevels == 25)
    }

    /// The unlock screen plays a clip of each world it opens (`WorldClip`); a world without one shows a still picture.
    @Test func everyWorldTheUnlockOpensHasAClip() {
        for world in ArcadeUnlock.worldsItOpens {
            #expect(Bundle.main.url(forResource: "clip-\(world.rawValue)", withExtension: "mp4") != nil, "\(world.rawValue)")
        }
    }

    @Test func theUnlockOpensEverythingAndSoDoesNotSellingIt() {
        for world in ArcadeWorld.campaign {
            #expect(ArcadeUnlock.isWorldOpen(world, unlocked: true, selling: true))
            #expect(ArcadeUnlock.isWorldOpen(world, unlocked: false, selling: false))
            for index in 0..<world.levelCount {
                #expect(!ArcadeUnlock.needsUnlock(world, index, unlocked: true, selling: true))
                #expect(!ArcadeUnlock.needsUnlock(world, index, unlocked: false, selling: false))
            }
        }
    }

    /// Every world is open from the start, but its levels still open in order, and its Deep End with level 10.
    @Test func everyWorldStartsAtLevelOneAndItsDeepEndWaitsForLevelTen() {
        let progress = fresh()
        for world in ArcadeWorld.campaign {
            #expect(progress.isOpen(world, 0) && !progress.isOpen(world, 1))
            #expect(!progress.isOpen(world, ArcadeWorld.mainLevelCount))
        }
        for index in 0..<ArcadeWorld.mainLevelCount { progress.clear(.kelpForest, index, seconds: 30) }
        #expect(progress.isOpen(.kelpForest, ArcadeWorld.mainLevelCount))
        #expect(!progress.isOpen(.midnightZone, 1))
    }

    /// The unlock is cached on the device so the maps draw right at launch and offline, apart from saved progress.
    /// Without the unlock, the Open Water has its free runs a day on each device, back each new day where the player is.
    @Test func freeOpenWaterRunsComeBackEachDay() {
        #expect(ArcadeUnlock.limitsOpenWater(unlocked: false, selling: true))
        #expect(!ArcadeUnlock.limitsOpenWater(unlocked: true, selling: true) && !ArcadeUnlock.limitsOpenWater(unlocked: false, selling: false))
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func at(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }
        let runs = OpenWaterRuns(defaults: defaults)
        let free = GameTuning.freeOpenWaterRunsPerDay
        #expect(free == 5 && runs.left(at: at(3, 9)) == free)
        for _ in 0..<free - 1 { runs.use(at: at(3, 9)) }
        #expect(runs.left(at: at(3, 23)) == 1)
        runs.use(at: at(3, 23))
        runs.use(at: at(3, 23))
        #expect(runs.left(at: at(3, 23)) == 0)
        // Kept on the device, and back the next day.
        #expect(OpenWaterRuns(defaults: defaults).left(at: at(3, 23)) == 0)
        #expect(runs.left(at: at(4, 0)) == free)
        runs.use(at: at(4, 8))
        #expect(OpenWaterRuns(defaults: defaults).left(at: at(4, 8)) == free - 1)
        // Its day is the Gregorian one, whatever calendar the player prefers.
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = .current
        #expect(OpenWaterRuns.day(of: at(4, 8), calendar: hebrew) == "2026-11-04")
    }

    @Test func purchasesStartLockedAndKeepTheirOwnKey() async {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        let purchases = await ArcadePurchases(defaults: defaults, syncWithAppStore: {})
        #expect(await !purchases.isUnlocked)
        defaults.set(true, forKey: "biggerFish.unlocked")
        #expect(await ArcadePurchases(defaults: defaults, syncWithAppStore: {}).isUnlocked)
        #expect(defaults.data(forKey: ArcadeProgress.key) == nil)
    }
}
