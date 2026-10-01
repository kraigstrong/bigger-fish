import Foundation
import Testing
@testable import MathReef

struct ReefReviewTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let name = "ReefReviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        test(defaults)
    }

    @Test func waitsForSuccessfulRoundWithACrown() {
        withDefaults { defaults in
            let review = ReefReview(defaults: defaults)
            #expect(!review.shouldRequest(now: start))
            review.finishedRound(passed: true, hasCrown: false, now: start)
            review.finishedRound(passed: false, hasCrown: true, now: start)
            #expect(!review.shouldRequest(now: start))
            review.finishedRound(passed: true, hasCrown: true, now: start)
            #expect(review.shouldRequest(now: start))
            // Visiting or cancelling the gate doesn't consume the pending opportunity.
            #expect(ReefReview(defaults: defaults).shouldRequest(now: start))
        }
    }

    @Test func repeatsOnlyAfterNinetyDaysAndAnotherSuccessfulRound() {
        withDefaults { defaults in
            let review = ReefReview(defaults: defaults)
            review.finishedRound(passed: true, hasCrown: true, now: start)
            review.didRequest(now: start)
            let early = start.addingTimeInterval(ReefTuning.reviewRetryInterval - 1)
            review.finishedRound(passed: true, hasCrown: true, now: early)
            #expect(!review.shouldRequest(now: early))
            let later = early.addingTimeInterval(1)
            #expect(!review.shouldRequest(now: later))
            review.finishedRound(passed: false, hasCrown: true, now: later)
            #expect(!review.shouldRequest(now: later))
            review.finishedRound(passed: true, hasCrown: true, now: later)
            #expect(review.shouldRequest(now: later))
        }
    }

    @Test func capsRequestsAtTwoAcrossLaunches() {
        withDefaults { defaults in
            let review = ReefReview(defaults: defaults)
            review.finishedRound(passed: true, hasCrown: true, now: start)
            review.didRequest(now: start)
            let later = start.addingTimeInterval(ReefTuning.reviewRetryInterval)
            let relaunched = ReefReview(defaults: defaults)
            #expect(!relaunched.shouldRequest(now: later))
            relaunched.finishedRound(passed: true, hasCrown: true, now: later)
            relaunched.didRequest(now: later)
            let muchLater = later.addingTimeInterval(ReefTuning.reviewRetryInterval * 5)
            let thirdLaunch = ReefReview(defaults: defaults)
            thirdLaunch.finishedRound(passed: true, hasCrown: true, now: muchLater)
            #expect(!thirdLaunch.shouldRequest(now: muchLater))
        }
    }

    @Test func clockGoingBackwardDoesNotBypassCooldown() {
        withDefaults { defaults in
            let review = ReefReview(defaults: defaults)
            review.finishedRound(passed: true, hasCrown: true, now: start)
            review.didRequest(now: start)
            let earlier = start.addingTimeInterval(-86400)
            review.finishedRound(passed: true, hasCrown: true, now: earlier)
            #expect(!review.shouldRequest(now: earlier))
        }
    }
}
