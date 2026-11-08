import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// Once every fish left is too big for you to eat, the level can't be won, and the round ends with a tip (Kraig,
/// 2026-11-07: players left swimming round with nothing they could eat took it for a bug).
@MainActor
struct TooSmallToWinTests {
    private func level(_ world: ArcadeWorld, _ index: Int = 0) -> (GameScene, SKView) {
        let scene = GameScene(world: world, levelIndex: index, showsJellyLesson: false)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        return (scene, view)
    }

    /// Too small to win is every fish left too big to eat. The near-equal band is yours, as when you meet one: a fish
    /// a hair bigger is still a meal. No fish left at all is a win.
    @Test func tooSmallToWinIsEveryFishLeftTooBigToEat() {
        #expect(GameRules.isTooSmallToWin(player: 10, others: [20, 15]))
        #expect(!GameRules.isTooSmallToWin(player: 10, others: [20, 9]))
        #expect(!GameRules.isTooSmallToWin(player: 10, others: [10.05]))
        #expect(GameRules.isTooSmallToWin(player: 10, others: [10.2]))
        #expect(!GameRules.isTooSmallToWin(player: 10, others: []))
    }

    /// With only bigger fish left, the round ends at once: a loss, not a death to any of them, your fish held still
    /// while the water dims, then the card says why and how to do better. Retry plays the level as new.
    @Test func theRoundEndsWithATip() {
        let (scene, view) = level(.shallowReef)
        var deaths = 0, clears = 0
        scene.onDeath = { _ in deaths += 1 }
        scene.onClear = { _, _ in clears += 1 }
        scene.debugRemoveFishYouCanEat()
        scene.debugAdvance(seconds: 0.1)
        #expect(scene.debugPhase == .lost && scene.debugEndedTooSmall)
        #expect(deaths == 1 && clears == 0)
        #expect(scene.debugLossReason == "Every fish left is bigger than you.")
        // The card waits while the water dims; your fish waits with it.
        #expect(scene.debugResultHeading == nil)
        let held = scene.debugPlayerPosition
        scene.debugAdvance(seconds: GameTuning.tooSmallResultDelay + 0.1)
        #expect(scene.debugResultHeading == "Too small to win")
        #expect(scene.debugResultNote == "Tip: eat more fish early to grow big enough.")
        #expect(scene.debugResultTitles == ["Retry", "Levels"])
        #expect(scene.debugPlayerPosition == held)

        scene.debugAdvance(seconds: GameTuning.restartDelay)
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugPhase == .ready && !scene.debugEndedTooSmall)
        scene.debugStart()
        scene.debugLose()
        scene.debugAdvance(seconds: 0.5)
        #expect(scene.debugResultHeading == "Try again!" && scene.debugResultNote == nil)
        withExtendedLifetime(view) {}
    }

    /// One fish you can still eat keeps the round going, and so does one still to swim in: Kelp Forest 1 starts with
    /// most of its fish yet to come.
    @Test(arguments: [ArcadeWorld.shallowReef, .kelpForest]) func aFishYouCanEatKeepsItGoing(_ world: ArcadeWorld) throws {
        let (scene, view) = level(world)
        if world == .kelpForest {
            let plan = try #require(scene.debugMeetingPlan)
            #expect(plan.fish.contains { ($0.appearsAt ?? 0) > 0 })
        }
        scene.debugRemoveFishYouCanEat(keeping: 1)
        scene.debugAdvance(seconds: 0.5)
        #expect(scene.debugPhase == .playing && !scene.debugEndedTooSmall)
        withExtendedLifetime(view) {}
    }

    /// A fish still to swim in counts even when every fish already here is too big: in the first Kelp Forest level that
    /// starts with a fish too big to eat in the water and one you could eat on its way.
    @Test func aFishStillToSwimInKeepsItGoing() throws {
        var tried = 0
        for index in 0..<ArcadeWorld.kelpForest.levelCount {
            let (scene, view) = level(.kelpForest, index)
            defer { withExtendedLifetime(view) {} }
            let plan = try #require(scene.debugMeetingPlan)
            let you = scene.debugPlayerRadius
            func edible(_ radius: CGFloat) -> Bool { GameRules.playerEncounter(you, radius) == .firstEatsSecond }
            guard plan.fish.contains(where: { ($0.appearsAt ?? 0) <= 0 && !edible($0.radius) }),
                  plan.fish.contains(where: { ($0.appearsAt ?? 0) > 0 && edible($0.radius) }) else { continue }
            tried += 1
            scene.debugRemoveFishYouCanEat(stillToSwimIn: false)
            scene.debugAdvance(seconds: 0.1)
            #expect(scene.debugPhase == .playing && !scene.debugEndedTooSmall, "Kelp Forest \(index + 1)")
            break
        }
        #expect(tried == 1)
    }

    /// The Open Water ends the run the same way: its card keeps the run's score and best, under a heading that says why.
    @Test func theOpenWaterEndsTheRun() {
        let run = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        run.startOpenWater(seed: 1)
        _ = run.debugPlayOpenWater(untilLevel: 0)
        #expect(run.debugPhase == .playing)
        run.debugRemoveFishYouCanEat()
        run.debugAdvance(seconds: GameTuning.tooSmallResultDelay + 0.2)
        #expect(run.debugPhase == .lost && run.debugEndedTooSmall)
        #expect(run.debugResultHeading == "Too small to go on")
        #expect(run.debugResultDetail?.hasPrefix("Stage 1") == true)
        #expect(run.debugResultNote == nil)
    }

    /// The tutorial brings a fish you missed back round, so it never ends this way.
    @Test func theTutorialNeverEndsThisWay() {
        let tutorial = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(tutorial)
        tutorial.debugStartTutorial(at: .eatEnough)
        tutorial.debugAdvance(seconds: 1)
        tutorial.debugRemoveFishYouCanEat()
        tutorial.debugAdvance(seconds: 1)
        #expect(!tutorial.debugEndedTooSmall && tutorial.debugPhase != .lost)
        withExtendedLifetime(view) {}
    }

    /// The stats count it as a loss of its own: cause "stuck", which the stats server takes.
    @Test func theStatsCountItAsStuck() async {
        let sender = ArcadeMetricsTests.Sender()
        let defaults = UserDefaults(suiteName: "metrics.tests.\(UUID().uuidString)")!
        let analytics = ArcadeAnalytics(defaults: defaults, sender: sender, enabled: true)
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.analytics = analytics
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        scene.debugRemoveFishYouCanEat()
        scene.debugAdvance(seconds: GameTuning.tooSmallResultDelay + GameTuning.restartDelay + 0.2)
        scene.debugTapResult(.tryAgain)
        scene.debugStart()
        scene.exitMetrics()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let events = analytics.queue + sender.batches.flatMap(\.events)
        #expect(events.contains { $0.kind == .run && $0.outcome == "death" && $0.cause == "stuck" })
        withExtendedLifetime(view) {}
    }
}
