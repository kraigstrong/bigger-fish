import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The Open Water's and the pearl shop's stats: a summary of each run, what happened after it, shop visits, looks earned,
/// and what your fish wears. All behind `ArcadeAnalytics.sendsOpenWaterEvents`, silent while it's off. Also how events
/// go: in batches, not after every run.
@MainActor
struct ArcadeOpenWaterMetricsTests {
    private typealias Sender = ArcadeMetricsTests.Sender
    private typealias ShopVisit = ArcadeAnalytics.ShopVisit
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "open-water.tests.\(UUID().uuidString)")! }
    private func analytics(_ d: UserDefaults, _ sender: Sender = Sender(), paywall: Bool = false) -> ArcadeAnalytics {
        ArcadeAnalytics(defaults: d, sender: sender, enabled: true, paywallEvents: paywall, openWaterEvents: true)
    }
    private let reef = ArcadeMetricContext(world: "shallow-reef", level: 3, setup: 3, seed: "7", revision: "golden.1")
    /// Lets the scene's metric operations and any batch send (each queued on the main queue) run.
    private func settle() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }

    @Test func aRunsNumbersAddUpAcrossItsLevels() {
        var m = OpenWaterMetricAccumulator()
        m.planned(seconds: 0.8)
        m.cleared(at: 40)
        m.waiting(at: 50)
        m.waiting(at: 51)
        m.cleared(at: 52.5)
        m.planned(seconds: 2.5)
        m.planned(seconds: .nan)
        let run = m.summary(at: 10, fish: 31, pearls: 9, best: true, dressed: true)
        #expect(run == ArcadeOpenWaterMetrics(levels: 2, fish: 31, pearls: 9, seconds: 102.5, best: true, waits: 1,
                                              waitSeconds: 2.5, slowestPlan: 2.5, dressed: true))
        // A wait still going when the run ends counts too, and nothing goes past the stats server's bounds.
        m.waiting(at: 12)
        let ended = m.summary(at: 20, fish: 20_000, pearls: -1, best: false, dressed: false)
        #expect(ended.waits == 2 && ended.waitSeconds == 10.5 && ended.fish == 10_000 && ended.pearls == 0)
        var long = OpenWaterMetricAccumulator()
        long.cleared(at: 3000)
        long.waiting(at: 0)
        let capped = long.summary(at: 3000, fish: 1, pearls: 1, best: false, dressed: false)
        #expect(capped.seconds == 3600 && capped.waitSeconds == 3000 && capped.waits == 1)
    }

    @Test func offItSendsAndSavesNothingNew() {
        let d = defaults(), sender = Sender()
        let a = ArcadeAnalytics(defaults: d, sender: sender, enabled: true, openWaterEvents: false)
        let before = d.dictionaryRepresentation().keys.sorted()
        a.wearing = ["hat.cone"]
        a.startOpenWater(); a.checkpointOpenWater(ArcadeOpenWaterMetrics(levels: 1)); a.openWaterWentRound()
        a.finishOpenWater("death", cause: "predator", run: ArcadeOpenWaterMetrics())
        var visit = ShopVisit(source: .map, wallet: 10, hadBought: false)
        visit.add("hat.cone")
        a.shopVisited(visit); a.earned(["hat.starfish"])
        #expect(!a.collectsOpenWater)
        #expect(a.queue.isEmpty)
        #expect(d.dictionaryRepresentation().keys.sorted() == before)
        a.start(reef); a.finish("win", summary: ArcadeRunMetrics())
        #expect(a.queue.allSatisfy { $0.dressed == nil && $0.kind != .outfit })
    }

    @Test func runsAreReportedWithTheirDecisionAndAnUnfinishedOneAtTheNextLaunch() {
        let d = defaults(), sender = Sender()
        let a = analytics(d, sender)
        a.startOpenWater()
        a.checkpointOpenWater(ArcadeOpenWaterMetrics(levels: 3, fish: 20, pearls: 4, seconds: 90))
        // The app is closed in the middle of the run.
        let next = analytics(d, sender)
        next.launched()
        let abandoned = next.queue.filter { $0.kind == .endless }
        #expect(abandoned.map(\.outcome) == ["abandoned"] && abandoned.first?.cause == "none")
        #expect(abandoned.first?.openWater == ArcadeOpenWaterMetrics(levels: 3, fish: 20, pearls: 4, seconds: 90))
        // Lost, then Retry; lost again, then leaving; and a quit, which has no decision after it.
        next.startOpenWater()
        next.finishOpenWater("death", cause: "tentacles", run: ArcadeOpenWaterMetrics(levels: 5, fish: 31))
        next.startOpenWater()
        next.finishOpenWater("death", cause: "hook", run: ArcadeOpenWaterMetrics(levels: 1))
        next.leave()
        next.startOpenWater()
        next.finishOpenWater("quit", cause: "predator", run: ArcadeOpenWaterMetrics())
        next.startOpenWater()
        let events = next.queue
        let runs = events.filter { $0.kind == .endless }
        #expect(runs.map(\.outcome) == ["abandoned", "death", "death", "quit"])
        #expect(runs.map(\.cause) == ["none", "tentacles", "hook", "none"])
        #expect(runs.allSatisfy { $0.context == ArcadeAnalytics.openWaterContext && $0.context?.seed == "0" })
        let decisions = events.filter { $0.kind == .decision }
        #expect(decisions.map(\.name) == ["retry", "leave"])
        #expect(decisions.allSatisfy { $0.context == ArcadeAnalytics.openWaterContext && $0.outcome == "death" })
        // Once per install: the first run, and the first time round the worlds.
        next.openWaterWentRound(); next.openWaterWentRound()
        #expect(next.queue.filter { $0.name == "open_water_started" }.count == 1)
        #expect(next.queue.filter { $0.name == "open_water_round" }.count == 1)
        // Never a campaign event.
        #expect(!next.queue.contains { $0.kind == .run || $0.name == "level_started" })
    }

    @Test func shopVisitsReportTheirDoorWalletPurchasesAndTheFirstPurchasesRuns() {
        let a = analytics(defaults())
        a.startOpenWater(); a.finishOpenWater("death", cause: "predator", run: ArcadeOpenWaterMetrics())
        a.startOpenWater(); a.finishOpenWater("quit", run: ArcadeOpenWaterMetrics())
        a.shopVisited(ShopVisit(source: .map, wallet: 12, hadBought: false))
        var first = ShopVisit(source: .runCard, wallet: 140, hadBought: false)
        first.add("hat.cone"); first.add("hat.cone"); first.add("trail.hearts")
        a.shopVisited(first)
        var later = ShopVisit(source: .map, wallet: 60, hadBought: true)
        later.add("color.mint")
        a.shopVisited(later)
        let visits = a.queue.filter { $0.kind == .shop }
        #expect(visits.map(\.source) == ["map", "run_card", "map"])
        #expect(visits.map(\.wallet) == [12, 140, 60])
        #expect(visits.map(\.bought) == [[], ["hat.cone", "trail.hearts"], ["color.mint"]])
        #expect(visits.map(\.firstPurchaseRuns) == [nil, 2, nil])
        // A player who bought a look before (on another device, or before these stats) has no first purchase to report.
        let b = analytics(defaults())
        var visit = ShopVisit(source: .map, wallet: 100, hadBought: true)
        visit.add("hat.cone")
        b.shopVisited(visit)
        #expect(b.queue.first?.firstPurchaseRuns == nil)
    }

    @Test func earnedLooksAreReportedOnceEach() {
        let a = analytics(defaults())
        a.earned(["hat.starfish"])
        a.earned(["hat.starfish", "hat.crown"])
        #expect(a.queue.filter { $0.kind == .earned }.map(\.id) == ["hat.starfish", "hat.crown"])
    }

    /// Runs say whether your fish wore any look. The launch's first run reports which, once, piece by piece; a launch
    /// whose first run is plain reports none.
    @Test func aLaunchsFirstRunReportsTheOutfitAndEveryRunWhetherDressed() {
        let a = analytics(defaults())
        a.wearing = ["trail.hearts", "hat.cone"]
        a.start(reef); a.finish("death", cause: "predator", summary: ArcadeRunMetrics())
        a.start(reef); a.finish("win", summary: ArcadeRunMetrics())
        a.startOpenWater()
        let outfits = a.queue.filter { $0.kind == .outfit }
        #expect(outfits.count == 1 && outfits.first?.pieces == ["hat.cone", "trail.hearts"])
        #expect(outfits.first?.context == nil)
        #expect(a.queue.filter { $0.kind == .run }.map(\.dressed) == [true, true])
        let b = analytics(defaults())
        b.start(reef); b.finish("quit", summary: ArcadeRunMetrics())
        b.wearing = ["hat.cone"]
        b.start(reef); b.finish("quit", summary: ArcadeRunMetrics())
        #expect(!b.queue.contains { $0.kind == .outfit })
        #expect(b.queue.filter { $0.kind == .run }.map(\.dressed) == [false, true])
    }

    /// Each send is a write to the stats server's Redis, billed per command: events wait for a full batch (or the
    /// background, or the next launch) rather than going after every run.
    @Test func eventsGoInFullBatchesNotAfterEveryRun() async {
        let sender = Sender()
        let a = ArcadeAnalytics(defaults: defaults(), sender: sender, enabled: true)
        a.start(reef); a.finish("death", cause: "predator", summary: ArcadeRunMetrics())
        await settle()
        #expect(sender.batches.isEmpty)
        while a.queue.count < ArcadeAnalytics.batchSize {
            a.start(reef); a.finish("quit", summary: ArcadeRunMetrics())
        }
        await settle()
        #expect(sender.batches.count == 1 && sender.batches.first?.events.count == ArcadeAnalytics.batchSize)
        #expect(a.queue.isEmpty)
        // What's left goes when the app goes to the background.
        a.start(reef); a.finish("quit", summary: ArcadeRunMetrics())
        a.backgrounded()
        #expect(sender.batches.count == 2 && a.queue.isEmpty)
    }

    /// Simulator builds (where these tests run) never collect.
    @Test func theSimulatorNeverCollects() {
        #expect(ArcadeAnalytics.isSimulator)
        #expect(!ArcadeAnalytics.defaultEnabled)
    }

    /// A run in the game: reported once, with its levels, its time, and its first level's plan; leaving after it is the
    /// decision; and it never reports as Shallow Reef's first level, which the Open Water's scene starts as.
    @Test func aRunInTheGameIsReportedOnceAndNeverAsACampaignLevel() async throws {
        let d = defaults(), sender = Sender()
        let a = analytics(d, sender)
        a.wearing = ["hat.cone"]
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.debugStartOpenWater(seed: 1, planSeconds: 0.75)
        scene.analytics = a
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        defer { withExtendedLifetime(view) {} }
        scene.debugStart()
        scene.debugAdvance(seconds: 2)
        scene.debugFinishOpenWaterLevel()
        await settle()
        // Closed now, the run would be reported as left unfinished, a level in.
        let pending = try #require(d.data(forKey: "biggerFish.metrics.v1.pendingOpenWater"))
        #expect(String(decoding: pending, as: UTF8.self).contains("\"levels\":1"))
        // Eaten by a fish half again your size, put right on you as soon as one is swimming (or stung first, in the
        // second level's Jelly Bloom).
        var placed = false
        for _ in 0..<40 where !placed && scene.debugPhase == .playing {
            scene.debugAdvance(seconds: 0.25)
            placed = scene.debugPutBiggerFishOnYou()
        }
        scene.debugAdvance(seconds: 2)
        await settle()
        #expect(scene.debugPhase == .lost)
        scene.exitMetrics()
        await settle()
        let events = a.queue + sender.batches.flatMap(\.events)
        let runs = events.filter { $0.kind == .endless }
        let run = try #require(runs.first)
        #expect(runs.count == 1)
        #expect(run.outcome == "death" && ["predator", "tentacles"].contains(run.cause))
        #expect(run.context == ArcadeAnalytics.openWaterContext)
        let numbers = try #require(run.openWater)
        #expect(numbers.levels == 1 && numbers.dressed && numbers.slowestPlan >= 0.75 && numbers.seconds >= 2)
        #expect(events.contains { $0.name == "open_water_started" })
        #expect(events.contains { $0.kind == .decision && $0.name == "leave" && $0.context == ArcadeAnalytics.openWaterContext })
        #expect(!events.contains { $0.kind == .run || $0.name == "level_started" || $0.name == "world_started" })
        #expect(d.data(forKey: "biggerFish.metrics.v1.pendingOpenWater") == nil)
    }

    /// These keys and values and no others: brightbench.app's fixture (bigger-fish-swift-open-water.json, copied from
    /// the file written here) proves its validator takes every kind and field.
    @Test func payloadPinsTheOpenWaterAndShopKeys() throws {
        let sender = Sender()
        let a = analytics(defaults(), sender, paywall: true)
        a.hasUnlock = false
        a.wearing = ["color.mint", "hat.cone", "trail.hearts"]
        a.startOpenWater()
        a.openWaterWentRound()
        a.finishOpenWater("death", cause: "tentacles", run: ArcadeOpenWaterMetrics(levels: 6, fish: 31, pearls: 9, seconds: 412.5,
            best: true, waits: 1, waitSeconds: 1.25, slowestPlan: 2.4, dressed: true))
        a.startOpenWater()
        a.finishOpenWater("quit", run: ArcadeOpenWaterMetrics(fish: 2, seconds: 20, dressed: true))
        a.start(reef); a.finish("win", summary: ArcadeRunMetrics())
        var visit = ShopVisit(source: .runCard, wallet: 140, hadBought: false)
        visit.add("hat.cone"); visit.add("trail.hearts")
        a.shopVisited(visit)
        a.shopVisited(ShopVisit(source: .map, wallet: 12, hadBought: true))
        a.earned(["hat.starfish"])
        a.flush()
        #expect(sender.batches.count == 1)
        let encoded = try JSONEncoder().encode(try #require(sender.batches.first))
        let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let events = try #require(root["events"] as? [[String: Any]])
        func sent(_ kind: String) -> [[String: Any]] { events.filter { $0["kind"] as? String == kind } }
        func keys(_ kind: String) -> Set<Set<String>> { Set(sent(kind).map { Set($0.keys) }) }
        #expect(keys("endless") == [["kind", "context", "outcome", "cause", "openWater", "unlocked"]])
        let numbers = try #require(sent("endless").first?["openWater"] as? [String: Any])
        #expect(Set(numbers.keys) == ["levels", "fish", "pearls", "seconds", "best", "waits", "waitSeconds", "slowestPlan", "dressed"])
        let context = try #require(sent("endless").first?["context"] as? [String: Any])
        #expect(context["seed"] as? String == "0" && context["mode"] as? String == "endless" && context["world"] as? String == "open-water")
        #expect(keys("shop") == [["kind", "source", "wallet", "bought", "firstPurchaseRuns"], ["kind", "source", "wallet", "bought"]])
        #expect(Set(sent("shop").compactMap { $0["source"] as? String }) == Set(ArcadeAnalytics.ShopSource.allCases.map(\.rawValue)))
        #expect(keys("earned") == [["kind", "id"]])
        #expect(keys("outfit") == [["kind", "pieces"]])
        #expect(keys("run") == [["kind", "context", "outcome", "cause", "replay", "attempt", "summary", "unlocked", "dressed"]])
        let milestones = sent("milestone").filter { ($0["name"] as? String)?.hasPrefix("open_water_") == true }
        #expect(Set(milestones.compactMap { $0["name"] as? String }) == ["open_water_started", "open_water_round"])
        #expect(sent("decision").contains { $0["name"] as? String == "retry" })
        try encoded.write(to: URL(fileURLWithPath: "/private/tmp/arcade-open-water-contract.json"))
    }
}
