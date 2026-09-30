import Foundation
import Testing
@testable import MathReef

/// Anonymous analytics: milestones once per install, one outcome per round, a capped local queue,
/// and nothing sent while sending is off. The allowlist test pins every key a batch can contain.
struct ReefAnalyticsTests {
    private let exponents = Curriculum.worlds.first { $0.id == "exponents" }!
    private let multiplication = Curriculum.worlds.first { $0.id == "multiplication" }!

    private final class StubSender: AnalyticsSender {
        var batches: [AnalyticsBatch] = []
        func send(_ batch: AnalyticsBatch) { batches.append(batch) }
    }

    /// Fresh defaults for one test, removed afterwards.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ReefAnalyticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func milestones(_ analytics: ReefAnalytics) -> [String] {
        analytics.queue.filter { $0.kind == .milestone }.compactMap(\.name)
    }

    private func rounds(_ analytics: ReefAnalytics) -> [AnalyticsEvent] {
        analytics.queue.filter { $0.kind == .round }
    }

    /// Plays a whole round of `level` through the store and analytics, as the scene does.
    @discardableResult
    private func play(
        _ index: Int, in world: World, correct: Int, attempts: Int,
        store: ProgressStore, analytics: ReefAnalytics
    ) -> RoundSummary {
        let level = world.levels[index]
        analytics.roundStarted(level: level, target: correct)
        analytics.roundProgress(correct: correct)
        let summary = store.recordRound(index, in: world, correct: correct, attempts: attempts)
        analytics.roundFinished(summary, level: level, in: world)
        return summary
    }

    // MARK: Milestones

    @Test func milestonesAreReportedOncePerInstall() {
        withDefaults { defaults in
            let level = exponents.levels[0]
            let analytics = ReefAnalytics(defaults: defaults)
            analytics.appLaunched()
            analytics.roundStarted(level: level, target: 10)
            analytics.roundQuit()
            analytics.roundStarted(level: level, target: 10)
            analytics.roundQuit()
            analytics.appLaunched()

            // A relaunch on the same defaults.
            let relaunched = ReefAnalytics(defaults: defaults)
            relaunched.appLaunched()
            relaunched.roundStarted(level: level, target: 10)
            #expect(milestones(relaunched) == ["first_launch", "first_round", "level_started:exp.1"])

            relaunched.roundQuit()
            relaunched.roundStarted(level: exponents.levels[1], target: 10)
            #expect(milestones(relaunched).last == "level_started:exp.2")
        }
    }

    @Test func levelPassedIsOnlyForThePlayedLevel() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            let store = ProgressStore(defaults: defaults)
            let checkpoint = multiplication.levels.firstIndex { $0.isCheckpoint && $0.id == "mul.easy" }!
            #expect(store.isSkipTest(checkpoint, in: multiplication))

            play(checkpoint, in: multiplication, correct: 12, attempts: 12, store: store, analytics: analytics)
            #expect(store.record(for: multiplication.levels[0]).passed)
            #expect(milestones(analytics).filter { $0.hasPrefix("level_passed:") } == ["level_passed:mul.easy"])

            // A failed round doesn't pass; a second pass isn't reported again.
            play(0, in: multiplication, correct: 5, attempts: 10, store: store, analytics: analytics)
            play(checkpoint, in: multiplication, correct: 12, attempts: 12, store: store, analytics: analytics)
            #expect(milestones(analytics).filter { $0.hasPrefix("level_passed:") } == ["level_passed:mul.easy"])
        }
    }

    @Test func crownsAreReportedForNewOrBetterCrownsOnly() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            let store = ProgressStore(defaults: defaults)
            let last = exponents.levels.count - 1
            for index in 0..<last {
                play(index, in: exponents, correct: 10, attempts: 12, store: store, analytics: analytics)
            }
            #expect(!milestones(analytics).contains { $0.hasPrefix("crown:") })

            play(last, in: exponents, correct: 10, attempts: 12, store: store, analytics: analytics)
            #expect(milestones(analytics).filter { $0.hasPrefix("crown:") } == ["crown:exponents:silver"])

            // Replaying without improving the crown adds nothing.
            play(0, in: exponents, correct: 10, attempts: 12, store: store, analytics: analytics)
            #expect(milestones(analytics).filter { $0.hasPrefix("crown:") } == ["crown:exponents:silver"])

            for index in exponents.levels.indices {
                play(index, in: exponents, correct: 12, attempts: 12, store: store, analytics: analytics)
            }
            #expect(milestones(analytics).filter { $0.hasPrefix("crown:") } == ["crown:exponents:silver", "crown:exponents:gold"])
        }
    }

    // MARK: Round outcomes

    @Test func finishedRoundsCarryStars() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            play(0, in: exponents, correct: 10, attempts: 12, store: ProgressStore(defaults: defaults), analytics: analytics)
            #expect(rounds(analytics) == [.round(level: "exp.1", outcome: .finished, correct: 10, target: 10, stars: 2)])
        }
    }

    @Test func quittingMidRoundRecordsHowFarItGot() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            analytics.roundQuit()  // the close button on the instructions: not a round
            #expect(rounds(analytics).isEmpty)

            analytics.roundStarted(level: exponents.levels[1], target: 12)
            analytics.roundProgress(correct: 4)
            analytics.roundQuit()
            analytics.roundQuit()
            #expect(rounds(analytics) == [.round(level: "exp.2", outcome: .quit, correct: 4, target: 12)])
            #expect(rounds(analytics)[0].stars == nil)
        }
    }

    @Test func closingTheAppMidRoundIsAbandonedOnNextLaunch() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            analytics.appLaunched()
            analytics.roundStarted(level: exponents.levels[0], target: 10)
            analytics.roundProgress(correct: 3)
            analytics.appResignedActive()
            #expect(rounds(analytics).isEmpty)

            let relaunched = ReefAnalytics(defaults: defaults)
            relaunched.appLaunched()
            #expect(rounds(relaunched) == [.round(level: "exp.1", outcome: .abandoned, correct: 3, target: 10)])
            #expect(rounds(relaunched)[0].stars == nil)

            // Reported once, not again on the launch after.
            ReefAnalytics(defaults: defaults).appLaunched()
            #expect(rounds(relaunched).count == 1)
        }
    }

    @Test func comingBackMidRoundKeepsTheRoundGoing() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            analytics.roundStarted(level: exponents.levels[0], target: 10)
            analytics.roundProgress(correct: 2)
            analytics.appResignedActive()
            analytics.appBecameActive()
            analytics.roundProgress(correct: 5)
            analytics.roundQuit()

            ReefAnalytics(defaults: defaults).appLaunched()
            #expect(rounds(analytics) == [.round(level: "exp.1", outcome: .quit, correct: 5, target: 10)])
        }
    }

    @Test func leavingTheAppOutsideARoundRecordsNothing() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            analytics.appResignedActive()
            play(0, in: exponents, correct: 10, attempts: 10, store: ProgressStore(defaults: defaults), analytics: analytics)
            analytics.appResignedActive()

            let relaunched = ReefAnalytics(defaults: defaults)
            relaunched.appLaunched()
            #expect(rounds(relaunched).map(\.outcome) == [.finished])
        }
    }

    @Test func starsAreOnlyForFinishedRounds() {
        for outcome in [AnalyticsEvent.Outcome.quit, .abandoned] {
            #expect(AnalyticsEvent.round(level: "exp.1", outcome: outcome, correct: 3, target: 10, stars: 2).stars == nil)
        }
        #expect(AnalyticsEvent.round(level: "exp.1", outcome: .finished, correct: 10, target: 10, stars: 0).stars == 0)
    }

    // MARK: Payload

    /// Fails if anyone adds a field. A new field also needs the privacy policy and
    /// `PrivacyInfo.xcprivacy` updated before sending is turned on.
    @Test func payloadContainsOnlyAllowedKeys() throws {
        let batch = AnalyticsBatch(appVersion: "1.0", channel: "debug", events: [
            .milestone("first_launch"),
            .round(level: "exp.1", outcome: .finished, correct: 10, target: 10, stars: 3),
            .round(level: "exp.1", outcome: .quit, correct: 2, target: 10),
            .round(level: "exp.1", outcome: .abandoned, correct: 0, target: 10),
        ])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))

        func keys(_ value: Any) -> Set<String> {
            if let object = value as? [String: Any] {
                return object.reduce(into: Set(object.keys)) { $0.formUnion(keys($1.value)) }
            }
            if let array = value as? [Any] { return array.reduce(into: []) { $0.formUnion(keys($1)) } }
            return []
        }
        #expect(keys(json) == [
            "appVersion", "channel", "events",
            "kind", "name",
            "level", "outcome", "correct", "target", "stars",
        ])
    }

    @Test func milestonesCarryNoRoundFields() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnalyticsEvent.milestone("first_round")))
        #expect(Set((json as! [String: Any]).keys) == ["kind", "name"])
    }

    // MARK: Queue and sending

    @Test func sendingDisabledSendsNothingAndKeepsTheQueue() {
        withDefaults { defaults in
            let sender = StubSender()
            let analytics = ReefAnalytics(defaults: defaults, sender: sender, sendingEnabled: false)
            analytics.appLaunched()
            analytics.flush()
            analytics.appResignedActive()
            #expect(sender.batches.isEmpty)
            #expect(analytics.queue == [.milestone("first_launch")])
        }
    }

    @Test func sendingIsOffInThisBuild() {
        #expect(!ReefAnalytics.isSendingEnabled)
    }

    @Test func flushSendsOneBatchAndEmptiesTheQueue() {
        withDefaults { defaults in
            let sender = StubSender()
            let analytics = ReefAnalytics(defaults: defaults, sender: sender, sendingEnabled: true)
            analytics.flush()
            #expect(sender.batches.isEmpty)

            analytics.appLaunched()
            analytics.roundStarted(level: exponents.levels[0], target: 10)
            analytics.appResignedActive()
            #expect(sender.batches.count == 1)
            #expect(sender.batches[0].events.map(\.name) == ["first_launch", "first_round", "level_started:exp.1"])
            #expect(sender.batches[0].channel == "debug")
            #expect(analytics.queue.isEmpty)

            // A batch is never resent, whether or not its request succeeded.
            analytics.flush()
            #expect(sender.batches.count == 1)
        }
    }

    @Test func fullQueueDropsTheOldest() {
        withDefaults { defaults in
            let analytics = ReefAnalytics(defaults: defaults)
            let level = exponents.levels[0]
            for correct in 0..<(ReefAnalytics.queueLimit + 5) {
                analytics.roundStarted(level: level, target: 500)
                analytics.roundProgress(correct: correct)
                analytics.roundQuit()
            }
            let queue = analytics.queue
            #expect(queue.count == ReefAnalytics.queueLimit)
            // The two milestones and the first five rounds are gone.
            #expect(queue.first?.correct == 5)
            #expect(queue.last?.correct == ReefAnalytics.queueLimit + 4)
        }
    }
}
