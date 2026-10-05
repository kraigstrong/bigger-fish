import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

@MainActor
struct ArcadeMetricsTests {
    @Test func growthBudgetHandlesTiesMissingFoodAndUnknownSwallows() {
        #expect(ArcadeGrowthSnapshot.measure(player: 10, opponents: [10], efficiency: 0.495).path == .available)
        #expect(ArcadeGrowthSnapshot.measure(player: 10, opponents: [20], efficiency: 0.495).path == .noPath)
        #expect(ArcadeGrowthSnapshot.measure(player: 10, opponents: [20], efficiency: 0.495, inFlight: true).path == .unknown)
        #expect(ArcadeGrowthSnapshot.measure(player: 10, opponents: [9, 11], efficiency: 0.495).path == .available)
        #expect(ArcadeGrowthSnapshot.measure(player: 10, opponents: [9, 11], efficiency: 0).path == .noPath)
    }
    @Test func summariesSeparateGrowthDeadEndsCleanupAndNearEqualMeals() {
        var a = ArcadeMetricAccumulator()
        a.observe(.measure(player: 10, opponents: [20], efficiency: 0.495))
        a.advance(seconds: 5, circuits: 0.5)
        a.observe(.measure(player: 30, opponents: [20], efficiency: 0.495))
        a.advance(seconds: 9, circuits: 1)
        a.meal(player: true, ratio: 0.99)
        a.fatal(ratio: 1.2)
        #expect(a.summary.noPathSeconds == 5)
        #expect(a.summary.cleanupSeconds == 4)
        #expect(a.summary.pathRecovered)
        #expect(a.summary.nearEqualMeals == 1)
        #expect(a.summary.fatalRatio == 1.2)
    }
    final class Sender: ArcadeMetricSender {
        var batches: [ArcadeMetricBatch] = []
        func send(_ batch: ArcadeMetricBatch) { batches.append(batch) }
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "metrics.tests.\(UUID().uuidString)")! }
    private let context = ArcadeMetricContext(world: "future-world", level: 500, setup: 500, seed: "20261477", revision: "future.1")

    @Test func abandonedRunIsReportedOnceAndNoIdentifiersAreEncoded() throws {
        let d = defaults(), sender = Sender()
        let a = ArcadeAnalytics(defaults: d, sender: sender, enabled: true)
        a.launched(); a.start(context)
        var summary = ArcadeRunMetrics(); summary.seconds = 12
        a.checkpoint(summary)
        let resumed = ArcadeAnalytics(defaults: d, sender: sender, enabled: true)
        resumed.launched(); resumed.launched()
        let abandoned = resumed.queue.filter { $0.outcome == "abandoned" }
        #expect(abandoned.count == 1)
        #expect(abandoned[0].summary?.seconds == 12)
        resumed.flush()
        let data = try JSONEncoder().encode(sender.batches[0])
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(root.keys) == ["schema", "appVersion", "build", "channel", "events"])
        for key in ["playerID", "installID", "sessionID", "timestamp", "device", "position"] {
            #expect(!String(decoding: data, as: UTF8.self).contains("\"\(key)\""))
        }
        #expect(resumed.queue.isEmpty)
    }
    @Test func attemptsFirstClearReplayAndDecisionsStayLocalAndExpandPastTen() {
        let d = defaults(), sender = Sender()
        let a = ArcadeAnalytics(defaults: d, sender: sender, enabled: true)
        a.start(context, worldLevelCount: 500)
        a.finish("death", cause: "predator", summary: ArcadeRunMetrics())
        a.start(context, worldLevelCount: 500)
        a.finish("win", summary: ArcadeRunMetrics())
        a.start(context, worldLevelCount: 500)
        a.finish("quit", summary: ArcadeRunMetrics())
        let runs = a.queue.filter { $0.kind == .run }
        #expect(runs.map(\.attempt) == [1, 2, 0])
        #expect(runs.map(\.replay) == [false, false, true])
        #expect(a.queue.filter { $0.name == "level_cleared" }.count == 1)
        #expect(!a.queue.contains { $0.name == "world_cleared" })
        #expect(a.queue.contains { $0.kind == .decision && $0.name == "retry" })
    }
    @Test func queuedAndAbandonedEventsKeepTheirOriginatingBuild() throws {
        let d = defaults(), sender = Sender()
        let a = ArcadeAnalytics(defaults: d, sender: sender, enabled: true)
        a.start(context)
        let key = "biggerFish.metrics.v1.pending"
        var pending = try #require(JSONSerialization.jsonObject(with: d.data(forKey: key)!) as? [String: Any])
        pending["appVersion"] = "0.0"; pending["build"] = "99"; pending["channel"] = "testflight"
        d.set(try JSONSerialization.data(withJSONObject: pending), forKey: key)
        let recovered = ArcadeAnalytics(defaults: d, sender: sender, enabled: true)
        recovered.launched(); recovered.flush()
        let old = try #require(sender.batches.first { $0.build == "99" })
        #expect(old.appVersion == "0.0" && old.channel == "testflight")
        #expect(old.events.contains { $0.outcome == "abandoned" })
    }

    @MainActor @Test func fatalInteractionIsReportedBeforeAnimationAndCannotBecomeAQuit() async throws {
        let d = defaults(), sender = Sender()
        let a = ArcadeAnalytics(defaults: d, sender: sender, enabled: true)
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        scene.analytics = a
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        scene.debugCommitFatalSwallowForMetrics()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        scene.exitMetrics()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let runs = a.queue.filter { $0.kind == .run }
        // exitMetrics flushes; inspect the actual outgoing batch.
        let death = try #require(sender.batches.flatMap(\.events).first { $0.kind == .run })
        #expect(death.outcome == "death" && death.cause == "predator")
        #expect(death.summary?.fatalRatio == 2)
        #expect(death.summary?.snapshot.path != .unknown)
        #expect(runs.isEmpty)
        #expect(!sender.batches.flatMap(\.events).contains { $0.outcome == "quit" || $0.outcome == "abandoned" })
        withExtendedLifetime(view) {}
    }

    @MainActor @Test func sceneLifecycleKeepsSameStackRestartSeparate() async throws {
        let sender = Sender()
        let a = ArcadeAnalytics(defaults: defaults(), sender: sender, enabled: true)
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        scene.analytics = a
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        scene.debugCommitFatalSwallowForMetrics()
        scene.debugClearLevel() // End the fixture animation and enter a result state.
        scene.debugTapResult(.tryAgain)
        scene.debugStart()
        scene.exitMetrics()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let events = sender.batches.flatMap(\.events) + a.queue
        let runs = events.filter { $0.kind == .run }
        #expect(runs.map(\.outcome) == ["death", "quit"])
        #expect(runs.map(\.attempt) == [1, 2])
        #expect(events.contains { $0.kind == .decision && $0.name == "retry" })
        withExtendedLifetime(view) {}
    }

    @Test func payloadPinsTheApprovedGameplaySummaryKeys() throws {
        let d = defaults(), sender = Sender()
        let analytics = ArcadeAnalytics(defaults: d, sender: sender, enabled: true)
        analytics.start(context)
        var summary = ArcadeRunMetrics()
        summary.snapshot = .measure(player: 10, opponents: [9, 11], efficiency: 0.495)
        summary.fatalRatio = 1.2
        analytics.finish("death", cause: "predator", summary: summary)
        analytics.flush()
        let encoded = try JSONEncoder().encode(sender.batches[0])
        let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let events = try #require(root["events"] as? [[String: Any]])
        let run = try #require(events.first { $0["kind"] as? String == "run" })
        #expect(Set(run.keys) == ["kind", "context", "outcome", "cause", "replay", "attempt", "summary"])
        let c = try #require(run["context"] as? [String: Any])
        #expect(Set(c.keys) == ["world", "mode", "level", "setup", "seed", "revision"])
        let s = try #require(run["summary"] as? [String: Any])
        #expect(Set(s.keys) == ["seconds", "circuits", "playerMeals", "aiMeals", "closeMeals", "nearEqualMeals", "bounces", "cleanupSeconds", "longestMealGap", "noPathSeconds", "pathRecovered", "snapshot", "fatalRatio"])
        let shot = try #require(s["snapshot"] as? [String: Any])
        #expect(Set(shot.keys) == ["path", "playerRadius", "remaining", "edible", "largestRatio"])
        try encoded.write(to: URL(fileURLWithPath: "/private/tmp/arcade-real-contract.json"))
    }

    @Test func progressFromBeforeMetricsActivationIsAReplay() {
        let a = ArcadeAnalytics(defaults: defaults(), sender: Sender(), enabled: true)
        a.start(context, alreadyCleared: true)
        a.finish("win", summary: ArcadeRunMetrics())
        let run = a.queue.first { $0.kind == .run }
        #expect(run?.replay == true && run?.attempt == 0)
    }

    @Test func disabledCollectionWritesAndSendsNothing() {
        let d = defaults(), sender = Sender()
        let a = ArcadeAnalytics(defaults: d, sender: sender, enabled: false)
        let before = d.dictionaryRepresentation()
        a.launched(); a.start(context); a.checkpoint(ArcadeRunMetrics())
        a.finish("win", summary: ArcadeRunMetrics()); a.leave(); a.flush()
        #expect(a.queue.isEmpty)
        #expect(sender.batches.isEmpty)
        #expect(d.dictionaryRepresentation().keys.sorted() == before.keys.sorted())
    }
}
