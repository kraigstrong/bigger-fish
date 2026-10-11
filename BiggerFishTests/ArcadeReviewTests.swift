import Foundation
import Testing
@testable import BiggerFish

/// When Bigger Fish asks for a review: after a high point, only in App Store builds, never after the unlock screen,
/// at most twice and 90 days apart.
struct ArcadeReviewTests {
    private func fresh() -> (ArcadeReview, UserDefaults) {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        return (ArcadeReview(defaults: defaults), defaults)
    }

    @Test func asksOnlyAfterAHighPointAndOnlyInAppStoreBuilds() {
        let (review, _) = fresh()
        #expect(!review.shouldRequest(channel: "appstore"))
        review.earned()
        #expect(review.shouldRequest(channel: "appstore"))
        #expect(!review.shouldRequest(channel: "testflight") && !review.shouldRequest(channel: "debug"))
    }

    @Test func theUnlockScreenCallsItOff() {
        let (review, _) = fresh()
        review.earned()
        review.sawOffer()
        #expect(!review.shouldRequest(channel: "appstore"))
    }

    @Test func atMostTwiceNinetyDaysApartAndRemembered() {
        let (review, defaults) = fresh()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        review.earned(now: start)
        review.didRequest(now: start)
        #expect(!review.shouldRequest(channel: "appstore", now: start))
        // A new high point too soon doesn't count.
        review.earned(now: start.addingTimeInterval(30 * 86_400))
        #expect(!review.shouldRequest(channel: "appstore", now: start.addingTimeInterval(30 * 86_400)))
        let later = start.addingTimeInterval(GameTuning.reviewRetryInterval + 1)
        review.earned(now: later)
        #expect(ArcadeReview(defaults: defaults).shouldRequest(channel: "appstore", now: later))
        review.didRequest(now: later)
        // That's two: never again.
        let much = later.addingTimeInterval(GameTuning.reviewRetryInterval * 3)
        review.earned(now: much)
        #expect(!ArcadeReview(defaults: defaults).shouldRequest(channel: "appstore", now: much))
    }
}
