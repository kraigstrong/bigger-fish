import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The paywall funnel (#123): offers, purchases, restores, the conquered milestone, and runs with the unlock. All of it
/// goes on with the unlock's sale (`ArcadeAnalytics.sendsPaywallEvents`, #156), and stays silent while it's off.
@MainActor
struct ArcadePaywallMetricsTests {
    private typealias Sender = ArcadeMetricsTests.Sender
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "paywall.tests.\(UUID().uuidString)")! }
    private func analytics(_ d: UserDefaults, _ sender: Sender = Sender(), paywall: Bool = true) -> ArcadeAnalytics {
        ArcadeAnalytics(defaults: d, sender: sender, enabled: true, paywallEvents: paywall)
    }
    private func reef(_ level: Int, mode: String = "campaign") -> ArcadeMetricContext {
        ArcadeMetricContext(world: "shallow-reef", level: level, setup: level, seed: "7", mode: mode, revision: "golden.1")
    }

    /// The funnel goes on in the same release as the sale: not before (nothing to count), and not after (an offer
    /// shown before it's on isn't remembered, so a later one would be reported as the install's first).
    @Test func paywallEventsGoOnWithTheSale() {
        #expect(ArcadeAnalytics.sendsPaywallEvents == ArcadeUnlock.isSelling)
    }

    @Test func paywallEventsStaySilentWhileOff() {
        let a = ArcadeAnalytics(defaults: defaults(), sender: Sender(), enabled: true, paywallEvents: false)
        a.hasUnlock = true
        a.offerShown(.padlockedLevel); a.purchase(.unlocked, from: .padlockedLevel); a.restoreInSettings(found: true)
        a.start(reef(10)); a.finish("win", summary: ArcadeRunMetrics())
        #expect(!a.queue.contains { [.offer, .purchase, .restore].contains($0.kind) || $0.name == "world_conquered" })
        #expect(a.queue.allSatisfy { $0.unlocked == nil && $0.source == nil && $0.first == nil })
    }

    /// One install's events from before the paywall funnel existed, captured from main at f4dc032 with their keys
    /// sorted. With the switch off, the same play with every paywall call mixed in must still send exactly these and
    /// save exactly the same markers on the device.
    private static let eventsBeforeThePaywallFunnel = """
    [{"kind":"milestone","name":"first_launch"},\
    {"context":{"level":10,"mode":"campaign","revision":"golden.1","seed":"7","setup":10,"world":"shallow-reef"},"kind":"milestone","name":"level_started"},\
    {"context":{"level":10,"mode":"campaign","revision":"golden.1","seed":"7","setup":10,"world":"shallow-reef"},"kind":"milestone","name":"world_started"},\
    {"attempt":1,"cause":"predator","context":{"level":10,"mode":"campaign","revision":"golden.1","seed":"7","setup":10,"world":"shallow-reef"},"kind":"run","outcome":"death","replay":false,"summary":{"aiMeals":0,"bounces":0,"circuits":0,"cleanupSeconds":0,"closeMeals":0,"fatalRatio":1.5,"longestMealGap":0,"nearEqualMeals":0,"noPathSeconds":0,"pathRecovered":false,"playerMeals":2,"seconds":12,"snapshot":{"edible":0,"largestRatio":0,"path":"unknown","playerRadius":0,"remaining":0}}},\
    {"context":{"level":10,"mode":"campaign","revision":"golden.1","seed":"7","setup":10,"world":"shallow-reef"},"kind":"decision","name":"retry","outcome":"death"},\
    {"attempt":2,"cause":"none","context":{"level":10,"mode":"campaign","revision":"golden.1","seed":"7","setup":10,"world":"shallow-reef"},"kind":"run","outcome":"win","replay":false,"summary":{"aiMeals":0,"bounces":0,"circuits":0,"cleanupSeconds":0,"closeMeals":0,"longestMealGap":0,"nearEqualMeals":0,"noPathSeconds":0,"pathRecovered":false,"playerMeals":0,"seconds":0,"snapshot":{"edible":0,"largestRatio":0,"path":"unknown","playerRadius":0,"remaining":0}}},\
    {"context":{"level":10,"mode":"campaign","revision":"golden.1","seed":"7","setup":10,"world":"shallow-reef"},"kind":"milestone","name":"level_cleared"},\
    {"context":{"level":10,"mode":"campaign","revision":"golden.1","seed":"7","setup":10,"world":"shallow-reef"},"kind":"decision","name":"next","outcome":"win"},\
    {"context":{"level":11,"mode":"campaign","revision":"golden.1","seed":"7","setup":11,"world":"shallow-reef"},"kind":"milestone","name":"level_started"},\
    {"attempt":1,"cause":"none","context":{"level":11,"mode":"campaign","revision":"golden.1","seed":"7","setup":11,"world":"shallow-reef"},"kind":"run","outcome":"quit","replay":false,"summary":{"aiMeals":0,"bounces":0,"circuits":0,"cleanupSeconds":0,"closeMeals":0,"longestMealGap":0,"nearEqualMeals":0,"noPathSeconds":0,"pathRecovered":false,"playerMeals":0,"seconds":0,"snapshot":{"edible":0,"largestRatio":0,"path":"unknown","playerRadius":0,"remaining":0}}}]
    """
    private static let markersBeforeThePaywallFunnel = [
        "attempt.golden.1.campaign.shallow-reef.10", "attempt.golden.1.campaign.shallow-reef.11",
        "cleared.golden.1.campaign.shallow-reef.10", "milestone.first_launch.install",
        "milestone.level_cleared.golden.1.campaign.shallow-reef.10", "milestone.level_started.golden.1.campaign.shallow-reef.10",
        "milestone.level_started.golden.1.campaign.shallow-reef.11", "milestone.world_started.golden.1.campaign.shallow-reef",
        "world.golden.1.campaign.shallow-reef",
    ].map { "biggerFish.metrics.v1." + $0 }

    /// Plays Shallow Reef's level 10 (a death, then the conquering win) and quits level 11, with every paywall call
    /// along the way, then sends. Returns the sent events, keys sorted, and the markers saved.
    private func playConqueringShallowReef(paywall: Bool) throws -> (events: String, markers: [String]) {
        let d = defaults(), sender = Sender()
        let a = analytics(d, sender, paywall: paywall)
        var fatal = ArcadeRunMetrics(); fatal.seconds = 12; fatal.playerMeals = 2; fatal.fatalRatio = 1.5
        a.hasUnlock = false
        a.launched()
        a.offerShown(.unlockAll); a.restoreInSettings(found: false)
        a.start(reef(10), worldLevelCount: 15)
        a.finish("death", cause: "predator", summary: fatal)
        a.start(reef(10), worldLevelCount: 15)
        a.finish("win", summary: ArcadeRunMetrics())
        a.offerShown(.conquered); a.purchase(.cancelled, from: .conquered); a.purchase(.unlocked, from: .conquered)
        a.restore(found: true, from: .conquered)
        a.hasUnlock = true
        a.start(reef(11), worldLevelCount: 15)
        a.finish("quit", summary: ArcadeRunMetrics())
        a.leave()
        a.flush()
        let events = try sender.batches.flatMap { batch -> [Any] in
            let root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(batch)) as? [String: Any])
            return try #require(root["events"] as? [Any])
        }
        // JSONEncoder's key order can differ from one encoding to the next, so compare with the keys sorted.
        let canonical = try JSONSerialization.data(withJSONObject: events, options: [.sortedKeys])
        return (String(decoding: canonical, as: UTF8.self),
                d.dictionaryRepresentation().keys.filter { $0.hasPrefix("biggerFish.") }.sorted())
    }

    @Test func withTheSwitchOffThePayloadIsByteForByteWhatItWas() throws {
        let off = try playConqueringShallowReef(paywall: false)
        #expect(off.events == Self.eventsBeforeThePaywallFunnel)
        #expect(off.markers == Self.markersBeforeThePaywallFunnel)
        // With it on, the same play adds the funnel's events and its two markers.
        let on = try playConqueringShallowReef(paywall: true)
        #expect(on.events != off.events)
        #expect(on.markers == (Self.markersBeforeThePaywallFunnel + [
            "biggerFish.metrics.v1.milestone.world_conquered.golden.1.campaign.shallow-reef", "biggerFish.metrics.v1.offerShown",
        ]).sorted())
    }

    @Test func paywallEventsNeedCollectionOnToo() {
        let d = defaults(), sender = Sender()
        let before = d.dictionaryRepresentation().keys.sorted()
        let a = ArcadeAnalytics(defaults: d, sender: sender, enabled: false, paywallEvents: true)
        a.hasUnlock = true
        a.offerShown(.nextLevel); a.purchase(.failed, from: .nextLevel); a.restore(found: false, from: .nextLevel)
        a.restoreInSettings(found: true)
        a.start(reef(10)); a.finish("win", summary: ArcadeRunMetrics()); a.flush()
        #expect(a.queue.isEmpty && sender.batches.isEmpty)
        #expect(d.dictionaryRepresentation().keys.sorted() == before)
    }

    @Test func everyShowOfTheOfferCountsAndTheInstallsFirstIsMarked() {
        let d = defaults()
        let a = analytics(d)
        a.offerShown(.padlockedLevel); a.offerShown(.padlockedLevel); a.offerShown(.conquered)
        let offers = a.queue.filter { $0.kind == .offer }
        #expect(offers.map(\.source) == ["padlocked_level", "padlocked_level", "conquered"])
        #expect(offers.map(\.first) == [true, false, false])
        #expect(offers.allSatisfy { $0.context == nil && $0.outcome == nil })
        // The marker belongs to the install: after a relaunch the next offer still isn't the first.
        let relaunched = analytics(d)
        relaunched.offerShown(.unlockAll)
        #expect(relaunched.queue.last?.first == false)
        #expect(ArcadeAnalytics.OfferSource.allCases.map(\.rawValue)
                == ["padlocked_level", "next_level", "unlock_all", "locked_world", "conquered"])
    }

    @Test func purchaseOutcomesAreReportedWithTheScreenTheyWereOn() {
        let a = analytics(defaults())
        for outcome in ArcadePurchases.PurchaseOutcome.allCases { a.purchase(outcome, from: .nextLevel) }
        let purchases = a.queue.filter { $0.kind == .purchase }
        #expect(purchases.map(\.outcome) == ["unlocked", "pending", "cancelled", "failed"])
        #expect(purchases.allSatisfy { $0.source == "next_level" && $0.context == nil && $0.first == nil })
    }

    @Test func restoresReportWhatTheyFoundAndWhere() {
        let a = analytics(defaults())
        a.restore(found: true, from: .unlockAll)
        a.restoreInSettings(found: false)
        let restores = a.queue.filter { $0.kind == .restore }
        #expect(restores.map(\.outcome) == ["restored", "not_found"])
        #expect(restores.map(\.source) == ["unlock_all", "settings"])
    }

    /// What happens on the maps is sent when the app goes to the background, not left for the next run or launch.
    @Test func goingToTheBackgroundSendsTheMapsEventsOnlyWithTheFunnelOn() {
        for paywall in [true, false] {
            let sender = Sender()
            let a = analytics(defaults(), sender, paywall: paywall)
            a.launched()
            a.offerShown(.unlockAll); a.purchase(.cancelled, from: .unlockAll)
            a.backgrounded()
            let sent = sender.batches.flatMap(\.events)
            #expect(sent.map(\.kind) == (paywall ? [.milestone, .offer, .purchase] : []))
            #expect(a.queue.map(\.name) == (paywall ? [] : ["first_launch"]))
        }
    }

    @Test func aWorldIsConqueredOnceWhenItsTenthLevelIsFirstBeaten() {
        let a = analytics(defaults())
        func play(_ context: ArcadeMetricContext, _ outcome: String = "win") {
            a.start(context, worldLevelCount: 15)
            a.finish(outcome, cause: outcome == "death" ? "predator" : "none", summary: ArcadeRunMetrics())
        }
        func conquered() -> [ArcadeMetricEvent] { a.queue.filter { $0.name == "world_conquered" } }
        play(reef(9))
        play(reef(10), "death")
        play(reef(10), "quit")
        #expect(conquered().isEmpty)
        play(reef(10))
        #expect(conquered().map(\.context) == [reef(10)])
        // Beaten again, or the Deep End after it: still once.
        play(reef(10)); play(reef(11)); play(reef(15))
        #expect(conquered().count == 1)
        // Another world counts for itself.
        play(ArcadeMetricContext(world: "jelly-bloom", level: 10, setup: 10, seed: "1", revision: "golden.1"))
        #expect(conquered().map(\.context?.world) == ["shallow-reef", "jelly-bloom"])
    }

    @Test func aTenthLevelAlreadyBeatenIsNotAConquest() {
        let a = analytics(defaults())
        // Cleared in saved progress before metrics knew of it: a replay, so not conquered again.
        a.start(reef(10), alreadyCleared: true)
        a.finish("win", summary: ArcadeRunMetrics())
        // Endless isn't the campaign.
        a.start(reef(10, mode: "endless"))
        a.finish("win", summary: ArcadeRunMetrics())
        #expect(!a.queue.contains { $0.name == "world_conquered" })
    }

    @Test func runsSayWhetherTheyWerePlayedWithTheUnlockWhileItIsOnSale() {
        let d = defaults()
        let a = analytics(d)
        for owned in [nil, false, true] as [Bool?] {
            a.hasUnlock = owned
            a.start(reef(1))
            a.finish("quit", summary: ArcadeRunMetrics())
        }
        #expect(a.queue.filter { $0.kind == .run }.map(\.unlocked) == [nil, false, true])
        // A run left unfinished keeps what it started with.
        a.hasUnlock = true
        a.start(reef(2))
        let relaunched = analytics(d)
        relaunched.launched()
        let abandoned = relaunched.queue.last { $0.kind == .run }
        #expect(abandoned?.outcome == "abandoned" && abandoned?.unlocked == true)
        // Only runs carry it.
        #expect(relaunched.queue.filter { $0.kind != .run }.allSatisfy { $0.unlocked == nil })
    }

    /// Beating Shallow Reef's tenth level in the real scene is the milestone, unless saved progress already had it.
    @Test func theScenesConqueringWinIsTheMilestone() async {
        for alreadyCleared in [false, true] {
            let sender = Sender()
            let a = analytics(defaults(), sender)
            a.hasUnlock = false
            let scene = GameScene(world: .shallowReef, levelIndex: ArcadeWorld.mainLevelCount - 1)
            scene.analytics = a
            scene.hasCleared = { _ in alreadyCleared }
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            scene.debugStart(); scene.debugClearLevel()
            // The scene hands its metrics to the main queue, and a win sends them.
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            let events = sender.batches.flatMap(\.events) + a.queue
            #expect(events.contains { $0.kind == .run && $0.outcome == "win" && $0.unlocked == false })
            #expect(events.filter { $0.name == "world_conquered" }.map(\.context?.level) == (alreadyCleared ? [] : [10]))
            withExtendedLifetime(view) {}
        }
    }
}
