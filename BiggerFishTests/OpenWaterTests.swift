import CoreGraphics
import FishKit
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The Open Water, the endless run: round the worlds a stage at a time, each world a new level made at that stage's
/// difficulty, planned as the run reaches it; eat a level's last gate and you shrink back to your starting size for the
/// next; being eaten ends the run.
@MainActor
struct OpenWaterTests {
    /// A stage goes round every world at one difficulty: each world's level 5 on stage 1, level 6 on stage 2.
    @Test func aStageGoesRoundEveryWorld() {
        let worlds = GameTuning.openWaterWorlds
        #expect(worlds == ArcadeWorld.campaign)
        for (index, world) in worlds.enumerated() {
            #expect(OpenWater.leg(index) == OpenWater.Leg(stage: 1, world: world, level: 5))
            #expect(OpenWater.leg(worlds.count + index) == OpenWater.Leg(stage: 2, world: world, level: 6))
        }
    }

    /// A level is made at the settings of its world's own level of that number: speeds, sizes, margins, and the
    /// world's hazards. Past the Deep End, its five again, faster each time round, up to a limit.
    @Test func eachLevelIsMadeAtItsWorldsOwnSettings() {
        func numbers(_ spec: MeetingSpec) -> [Double] {
            [spec.crossSeconds, spec.aiSpeed.lowerBound, spec.aiSpeed.upperBound, spec.gateMargin, spec.dangerGap,
             spec.threatClearance, spec.spacing, spec.foodSize.lowerBound, spec.worldScreens, Double(spec.extraThreats)]
        }
        let shallow = GameTuning.reefLabSpecs[GameTuning.shallowReefOrder[4]]
        #expect(numbers(OpenWater.template(.shallowReef, level: 5)) == numbers(shallow))
        #expect(OpenWater.template(.jellyBloom, level: 5).jellies == GameTuning.jellyLabSpecs[4].jellies)
        #expect(OpenWater.template(.kelpForest, level: 5).kelp == GameTuning.kelpSpecs[4].kelp)
        #expect(OpenWater.template(.sunsetCove, level: 5).hooks == GameTuning.sunsetSpecs[4].hooks)
        #expect(numbers(OpenWater.template(.midnightZone, level: 6)) == numbers(GameTuning.midnightSpecs[5]))
        let deepEnd = GameTuning.kelpSpecs[10], past = OpenWater.template(.kelpForest, level: 16)
        #expect(past.segments == deepEnd.segments && past.kelp == deepEnd.kelp)
        #expect(abs(past.crossSeconds - deepEnd.crossSeconds / 1.05) < 1e-9)
        #expect(abs(past.aiSpeed.upperBound - deepEnd.aiSpeed.upperBound * 1.05) < 1e-9)
        let far = OpenWater.template(.kelpForest, level: 400)
        let farSource = GameTuning.kelpSpecs[10 + (400 - 16) % 5]
        #expect(abs(far.crossSeconds - farSource.crossSeconds / (1 + GameTuning.openWaterSpeedUpLimit)) < 1e-9)
    }

    /// A level isn't a copy of its template: its segments are dealt again, a meal either way, each gate keeping the
    /// template's slack on the short lanes and no more danger than it had.
    @Test func levelsAreNewDealsOfTheirTemplates() {
        var differ = 0, total = 0
        for seed in UInt64(1)...20 {
            for index in 0..<GameTuning.openWaterWorlds.count {
                let leg = OpenWater.leg(index), template = OpenWater.template(leg.world, level: leg.level)
                let spec = OpenWater.spec(index, seed: seed)
                total += 1
                if spec.segments != template.segments { differ += 1 }
                #expect(spec.segments.count == template.segments.count)
                #expect(spec.crossSeconds == template.crossSeconds && spec.jellies == template.jellies
                        && spec.kelp == template.kelp && spec.hooks == template.hooks)
                for (segment, base) in zip(spec.segments, template.segments) {
                    #expect((1...max(1, segment.mostMeals)).contains(segment.needed))
                    #expect(segment.dangerFoods <= base.dangerFoods)
                    #expect(segment.forks.allSatisfy { $0.long >= $0.short && $0.long <= 3 })
                    let slack = { (s: MeetingSpec.Segment) in s.singles + s.forks.reduce(0) { $0 + $1.short } - s.needed }
                    #expect(slack(segment) >= min(slack(base), slack(segment) + segment.needed - 1))
                }
            }
        }
        #expect(differ > total * 3 / 4, "only \(differ) of \(total) deals differ from their templates")
    }

    /// A run's levels plan the same every time, and another run's differently.
    @Test func aRunsSeedNamesItsLayouts() {
        let plan = OpenWater.plan(2, seed: 7)
        #expect(OpenWater.plan(2, seed: 7).fish == plan.fish)
        #expect(OpenWater.plan(2, seed: 8).fish != plan.fish)
    }

    /// Two stages' levels, every world twice, plan with nothing off (what the planner promises: placement, fit,
    /// clearances, not whether a bot could win), and each has a last gate to end it.
    @Test(arguments: [UInt64(1), 2, 3])
    func everyLevelPlansCleanly(seed: UInt64) {
        var slowest: [ArcadeWorld: Double] = [:]
        for index in 0..<(2 * GameTuning.openWaterWorlds.count) {
            let started = Date()
            let plan = OpenWater.plan(index, seed: seed)
            let world = OpenWater.leg(index).world
            slowest[world] = max(slowest[world] ?? 0, Date().timeIntervalSince(started))
            #expect(plan.issues.isEmpty, "level \(index) (\(world)): \(plan.issues)")
            #expect(!plan.hasGiantWall, "level \(index) (\(world)) has a wall of giants")
            #expect(OpenWater.finale(plan) != nil, "level \(index) (\(world)) has no gate")
            // Jelly Bloom's bells, planned just in time like the other worlds' fish.
            #expect((plan.jellies?.isEmpty == false) == (world == .jellyBloom), "level \(index) (\(world))")
            #expect(plan.fish.allSatisfy { $0.appearsAt != nil }, "level \(index) (\(world))")
        }
        print("[OpenWater] seed \(seed), slowest plan (ms): "
              + slowest.map { "\($0.key.rawValue) \(Int($0.value * 1000))" }.sorted().joined(separator: ", "))
    }

    /// A level none of whose first round of deals plans cleanly deals again rather than play one with an issue (Kraig,
    /// 2026-10-26: "fix the bad level problem"): run 1039's stage 3 Jelly Bloom, every first-round deal of which kept
    /// "gate 8 has one route", plans cleanly from its second round. A level that plans in the first round is as it was.
    @Test func aLevelThatWontPlanCleanlyDealsAgain() throws {
        func recipe(_ plan: MeetingPlan) throws -> Int { try #require(plan.spec.name.split(separator: ".").last.flatMap { Int($0) }) }
        #expect(OpenWater.leg(11).world == .jellyBloom)
        let plan = OpenWater.plan(11, seed: 1039)
        #expect(plan.issues.isEmpty && !plan.hasGiantWall && !plan.hasWall, "\(plan.issues)")
        #expect(try recipe(plan) >= GameTuning.openWaterDeals)
        #expect(try recipe(OpenWater.plan(0, seed: 1)) < GameTuning.openWaterDeals)
    }

    /// Jelly Bloom's levels plan just in time like the other worlds': its bells where the designer puts them, every
    /// fish's way in clear of them, three stages deep across a handful of runs, in a few seconds at most.
    @Test func jellyLevelsPlanInTime() {
        let worlds = GameTuning.openWaterWorlds, jelly = worlds.firstIndex(of: .jellyBloom)!
        var slowest = 0.0, fewer = 0, levels = 0
        for seed in UInt64(11)...16 {
            for stage in 0..<3 {
                let index = stage * worlds.count + jelly, started = Date()
                let plan = OpenWater.plan(index, seed: seed)
                slowest = max(slowest, Date().timeIntervalSince(started))
                levels += 1
                if plan.spec.extraThreats < OpenWater.spec(index, seed: seed).extraThreats { fewer += 1 }
                #expect(plan.issues.isEmpty && !plan.hasGiantWall, "seed \(seed), stage \(stage + 1): \(plan.issues)")
                #expect(plan.jellies?.isEmpty == false)
            }
        }
        print("[OpenWater] Jelly Bloom: slowest plan \(Int(slowest * 1000)) ms, \(fewer) of \(levels) with one fewer big fish")
    }

    /// Pearls sit beside danger, a few a level: each just outside a big fish's body where you pass it, never on top
    /// of it, and most levels have some.
    @Test func pearlsSitBesideDanger() {
        var levels = 0, withPearls = 0
        for seed in UInt64(1)...3 {
            for index in 0..<(2 * GameTuning.openWaterWorlds.count) {
                let plan = OpenWater.plan(index, seed: seed), pearls = OpenWater.pearls(plan)
                let world = WrappedWorld(width: GameTuning.playfieldSize.width * CGFloat(plan.spec.worldScreens))
                levels += 1
                if !pearls.isEmpty { withPearls += 1 }
                #expect(pearls.count <= GameTuning.openWaterPearlsPerLevel)
                let threats = Set(plan.fish.filter { $0.role == .threat }.map(\.id))
                for pearl in pearls {
                    let beside = plan.predicted.contains { crossing in
                        let off = abs(CGFloat(crossing.y) - pearl.position.y), r = CGFloat(crossing.radius)
                        return threats.contains(crossing.fishID)
                            && abs(world.delta(from: CGFloat(crossing.distance), to: pearl.position.x)) < 1
                            && off > r * GameTuning.collisionScale && off < 3 * r + 3 * GameTuning.openWaterPearlGap
                    }
                    #expect(beside, "level \(index), seed \(seed): a pearl at \(pearl.position) beside no big fish")
                }
            }
        }
        #expect(withPearls * 4 >= levels * 3, "only \(withPearls) of \(levels) levels have pearls")
        print("[OpenWater] pearls on \(withPearls) of \(levels) levels")
    }

    /// Eating a level's last gate starts the next at once, in one shot rather than a cut: your fish keeps its size and
    /// height on screen, the camera starting that much closer and easing back.
    @Test func theNextLevelStartsAtOnceWithTheCameraClose() throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 1)
        let played = scene.debugPlayOpenWater(untilLevel: 1, limit: 5, safeFromFish: true)
        #expect(played.index == 0 && !played.lost)
        let before = scene.debugYouOnScreen
        #expect(before.radius > GameTuning.baseRadius)
        scene.debugFinishOpenWaterLevel()
        #expect(scene.debugOpenWaterIndex == 1 && scene.arcadeWorld == GameTuning.openWaterWorlds[1])
        let closer = try #require(scene.debugOpenWaterWashCloser)
        let after = scene.debugYouOnScreen
        #expect(after.radius == GameTuning.baseRadius)
        #expect(abs(after.radius * closer - before.radius) < 0.01 && abs(after.height - before.height) < 0.01)
    }

    /// The run's card is just its name: a level here ends on its last gate, so Shallow Reef's "Be the last fish
    /// swimming." (its first level's card) doesn't belong on it.
    @Test func theRunsCardNamesNoRules() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 1)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        defer { withExtendedLifetime(view) {} }
        #expect(scene.debugCardTexts == ["Open Water", "Tap to start"])
    }

    /// Touching a pearl takes it: it counts, it's kept for the shop at once, and it doesn't grow you. The run's card
    /// offers the shop.
    @Test func takingAPearlCountsItWithoutGrowingYou() throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 1)
        var kept = 0, shopped = 0
        scene.onPearl = { kept += 1 }
        scene.onShop = { shopped += 1 }
        scene.pearlsToSpend = 10
        _ = scene.debugPlayOpenWater(untilLevel: 0)
        let count = scene.debugOpenWaterPearls.count
        let taken = try #require(scene.debugTakeFirstPearl())
        #expect(taken.pearls == 1 && taken.after == taken.before && kept == 1)
        #expect(scene.debugOpenWaterPearls.count == count - 1)
        scene.debugLose()
        #expect(scene.debugResultDetail?.hasSuffix("· 1 pearl") == true)
        // The run's pearl counts up into the rest on the Shop button.
        #expect(scene.debugResultShownShopPearls == 9 && scene.debugResultShopPearls == 10)
        #expect(scene.debugResultTitles == ["Retry", "Shop", "Home"])
        scene.debugTapResult(.shop)
        #expect(shopped == 1 && scene.debugResultTitles == ["Retry", "Shop", "Home"])
    }

    /// Without the unlock, a run is one of the day's free runs once it takes its first pearl (Kraig, 2026-10-26: "first
    /// pearl is a great compromise!"), counted once however many it takes. Its card says how many are left; with none, it
    /// offers the unlock in place of Retry, and Restart goes there too.
    @Test func aFreeRunCountsAtItsFirstPearl() throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 1)
        var left = 1, counted = 0, exits = 0
        scene.openWaterRunsLeft = { left }
        scene.onOpenWaterRunCounted = {
            counted += 1
            left -= 1
        }
        scene.onExit = { exits += 1 }
        _ = scene.debugPlayOpenWater(untilLevel: 0)
        #expect(counted == 0)
        _ = try #require(scene.debugTakeFirstPearl())
        if !scene.debugOpenWaterPearls.isEmpty { _ = scene.debugTakeFirstPearl() }
        #expect(counted == 1 && left == 0)
        scene.debugLose()
        #expect(scene.debugResultNote == "\(GameTuning.freeOpenWaterRunsPerDay) more runs tomorrow")
        #expect(scene.debugResultTitles == ["Unlock all", "Shop", "Home"])
        #expect(!scene.leftForUnlock)
        scene.debugTapResult(.unlock)
        #expect(exits == 1 && scene.leftForUnlock)

        // With runs left, the card says how many, and Retry starts the next.
        let another = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        another.startOpenWater(seed: 1)
        another.openWaterBest = 40
        another.openWaterRunsLeft = { 3 }
        _ = another.debugPlayOpenWater(untilLevel: 0, limit: 1)
        another.debugLose()
        #expect(another.debugResultNote == "Best: 40 fish · 3 runs left today")
        #expect(another.debugResultTitles == ["Retry", "Shop", "Home"])
        // None left now (as when a run's first pearl took the day's last): Restart, mid-run, goes to the unlock.
        var anotherExits = 0
        another.openWaterRunsLeft = { 0 }
        another.onExit = { anotherExits += 1 }
        another.debugRestart()
        #expect(anotherExits == 1 && another.leftForUnlock)

        // A card left up past midnight, its runs back: Unlock all brings Retry back, not the unlock's screen.
        let overnight = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        overnight.startOpenWater(seed: 1)
        var renewed = 0, overnightExits = 0
        overnight.openWaterRunsLeft = { renewed }
        overnight.onExit = { overnightExits += 1 }
        _ = overnight.debugPlayOpenWater(untilLevel: 0, limit: 1)
        overnight.debugLose()
        #expect(overnight.debugResultTitles == ["Unlock all", "Shop", "Home"])
        renewed = GameTuning.freeOpenWaterRunsPerDay
        overnight.debugTapResult(.unlock)
        #expect(overnightExits == 0 && !overnight.leftForUnlock)
        #expect(overnight.debugResultTitles == ["Retry", "Shop", "Home"])
        #expect(overnight.debugResultNote == "\(GameTuning.freeOpenWaterRunsPerDay) runs left today")

        // With the unlock, nothing's counted and the card says nothing of runs.
        let unlocked = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        unlocked.startOpenWater(seed: 1)
        unlocked.openWaterRunsLeft = { nil }
        _ = unlocked.debugPlayOpenWater(untilLevel: 0, limit: 1)
        unlocked.debugLose()
        #expect(unlocked.debugResultNote == nil && unlocked.debugResultTitles == ["Retry", "Shop", "Home"])
    }

    /// Each level ends once you eat its last gate, and the next world's begins the way a level does: you at your
    /// starting size with the camera all the way in, at the start of its lap and its clock, every fish its plan has
    /// on its way, and the world's own hazards. Nothing is ever won or cleared.
    @Test func eachLevelEndsOnItsLastGateAndStartsYouSmall() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 1)
        var cleared = false
        scene.onClear = { _, _ in cleared = true }
        let worlds = GameTuning.openWaterWorlds
        let run = scene.debugPlayOpenWater(untilLevel: worlds.count + 1, safeFromFish: true)
        #expect(run.index == worlds.count + 1 && !run.lost && !run.won && !cleared, "stopped at level \(run.index): \(run.reason)")
        #expect(run.starts.map(\.world) == worlds + [worlds[0], worlds[1]])
        for start in run.starts {
            let name = "level \(start.index) (\(start.world))"
            #expect(start.radius == GameTuning.baseRadius && start.zoom == 1, "\(name)")
            #expect(start.forwardDistance == 0 && start.clock == 0, "\(name)")
            #expect(start.fish == start.planned && start.planned > 0, "\(name)")
            #expect((start.jellies > 0) == (start.world == .jellyBloom), "\(name)")
            #expect((start.kelp > 0) == (start.world == .kelpForest), "\(name)")
            #expect((start.hooks > 0) == (start.world == .sunsetCove), "\(name)")
            #expect(start.dark == (start.world == .midnightZone), "\(name)")
        }
        #expect(run.largest > GameTuning.baseRadius * 1.5)
    }

    /// Being eaten ends the run, and its result says how far it got. Retry starts a new run, the next seed on, back
    /// at the first world.
    @Test func beingEatenEndsTheRun() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 5)
        #expect(scene.debugPlayOpenWater(untilLevel: 1, safeFromFish: true).index == 1)
        #expect(scene.arcadeWorld == GameTuning.openWaterWorlds[1])
        scene.debugLose()
        #expect(scene.debugResultDetail?.hasPrefix("Stage 1 · \(GameTuning.openWaterWorlds[1].title) · ") == true)
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugOpenWaterIndex == 0 && scene.debugOpenWaterSeed == 6)
        #expect(scene.arcadeWorld == GameTuning.openWaterWorlds[0])
    }

    /// A run's score is the fish it ate. Its card says "New best!" over a run that beats the best and shows the best
    /// under how far it got, and its Shop button shows the pearls you have to spend, kept up to date as they're spent.
    @Test func aRunsCardShowsTheBestAndYourPearls() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 1)
        scene.openWaterBest = 2
        scene.pearlsToSpend = 38
        var runs: [Int] = []
        scene.onOpenWaterRun = { fish, _ in
            runs.append(fish)
            return []
        }
        _ = scene.debugPlayOpenWater(untilLevel: 1, limit: 5, safeFromFish: true)
        let fish = scene.debugMealsEaten
        #expect(fish > 2)
        scene.debugLose()
        #expect(runs == [fish])
        #expect(scene.debugResultHeading == "New best!" && scene.debugResultNote == "Best: \(fish) fish")
        #expect(scene.debugResultShopPearls == 38)
        scene.pearlsToSpend = 12
        #expect(scene.debugResultShopPearls == 12)
        // A run that doesn't beat it: the usual heading, and still the best.
        scene.debugTapResult(.tryAgain)
        _ = scene.debugPlayOpenWater(untilLevel: 1, limit: 1, safeFromFish: true)
        let fewer = scene.debugMealsEaten
        #expect(fewer < fish)
        scene.debugLose()
        #expect(runs == [fish, fewer])
        #expect(scene.debugResultHeading == "Try again!" && scene.debugResultNote == "Best: \(fish) fish")
    }

    /// The best run is kept on the device and backed up to iCloud, where two devices' bests merge to the better one
    /// either way round. A save from before it has none, and takes nothing away.
    @Test func theBestRunIsKeptAndTheBetterOneSyncs() throws {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        let progress = ArcadeProgress(defaults: defaults, cloud: nil)
        #expect(progress.openWaterBest == 0)
        progress.recordOpenWaterRun(fish: 14)
        progress.recordOpenWaterRun(fish: 9)
        #expect(progress.openWaterBest == 14)
        #expect(ArcadeProgress(defaults: defaults, cloud: nil).openWaterBest == 14)
        let decoder = JSONDecoder()
        let old = try decoder.decode(ArcadeSave.self, from: Data(ArcadeCloudSaveTests.firstVersion.utf8))
        let phone = try decoder.decode(ArcadeSave.self, from: Data(#"{"openWaterBest":14}"#.utf8))
        let pad = try decoder.decode(ArcadeSave.self, from: Data(#"{"openWaterBest":31}"#.utf8))
        #expect(old.openWaterBest == nil)
        #expect(phone.merged(withCloud: pad).openWaterBest == 31 && pad.merged(withCloud: phone).openWaterBest == 31)
        #expect(phone.merged(withCloud: old).openWaterBest == 14 && old.merged(withCloud: phone).openWaterBest == 14)
        let far = try decoder.decode(ArcadeSave.self, from: Data(#"{"openWaterFurthest":6}"#.utf8))
        #expect(far.merged(withCloud: phone).openWaterFurthest == 6 && phone.merged(withCloud: far).openWaterFurthest == 6)
    }

    /// A run that earns a look says so over its card (it's the app that keeps what's earned), and tells the app how far
    /// it got.
    @Test func aRunsCardSaysWhatItEarned() throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 5)
        let shark = try #require(PearlItem.item("hat.sharkfin")), starfish = try #require(PearlItem.item("hat.starfish"))
        var earned = [shark], reached: [Int] = []
        scene.onOpenWaterRun = { _, furthest in
            reached.append(furthest)
            return earned
        }
        #expect(scene.debugPlayOpenWater(untilLevel: 1, safeFromFish: true).index == 1)
        scene.debugLose()
        #expect(reached == [1] && scene.debugResultHeading == "You earned the Shark fin!")
        earned = [shark, starfish]
        scene.debugTapResult(.tryAgain)
        scene.debugLose()
        #expect(reached == [1, 0] && scene.debugResultHeading == "You earned 2 new looks!")
    }

    /// The game plans each level off the main thread as the one before starts, never as it reaches it: that froze the
    /// game for seconds on a phone. Eat a level's last gate before the next is planned and the level plays on, with
    /// nothing able to catch you, until it is.
    @Test func aLevelDoneEarlyPlaysOnUntilTheNextIsPlanned() async throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 1)
        scene.debugPlansOpenWaterAhead = true
        // Played straight through, the next level's plan can't arrive: it comes back on the main thread.
        let played = scene.debugPlayOpenWater(untilLevel: 1, limit: 12)
        #expect(played.index == 0 && !played.lost, "\(played.reason)")
        #expect(scene.debugOpenWaterLevelDone && !scene.debugOpenWaterHasPlan(1))
        #expect(scene.debugPutBiggerFishOnYou())
        scene.debugAdvance(seconds: 0.5)
        #expect(scene.debugPhase == .playing && scene.debugOpenWaterIndex == 0)
        for _ in 0..<1500 where scene.debugOpenWaterIndex == 0 {
            try await Task.sleep(for: .milliseconds(20))
            scene.debugAdvance(seconds: GameTuning.simulationStep)
        }
        #expect(scene.debugOpenWaterIndex == 1 && scene.arcadeWorld == GameTuning.openWaterWorlds[1])
        #expect(!scene.debugOpenWaterLevelDone)
    }

    /// Retry waits for the new run's first level, planned off the main thread as the last run ended, rather than plan
    /// it on the main thread. Its second level, a Jelly Bloom one and the slowest to plan, was planned alongside.
    @Test func retryWaitsForTheNextRunsFirstLevel() async throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.startOpenWater(seed: 5)
        scene.debugPlansOpenWaterAhead = true
        _ = scene.debugPlayOpenWater(untilLevel: 1, limit: 3, safeFromFish: true)
        scene.debugLose()
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugOpenWaterSeed == 5 && scene.debugResultTitles == ["Retry", "Shop", "Home"])
        for _ in 0..<1500 where scene.debugOpenWaterSeed == 5 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(scene.debugOpenWaterSeed == 6 && scene.debugOpenWaterIndex == 0)
        #expect(scene.arcadeWorld == GameTuning.openWaterWorlds[0])
        for _ in 0..<1500 where !scene.debugOpenWaterHasPlan(1) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(scene.debugOpenWaterHasPlan(1))
    }
}
