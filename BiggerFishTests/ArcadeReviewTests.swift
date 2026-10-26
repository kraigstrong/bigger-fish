import Foundation
import Testing
@testable import BiggerFish

/// When Bigger Fish asks for a review: after a high point (a level hard won, or a first Deep End clear), only in App
/// Store builds, never after the unlock screen, at most twice and 90 days apart.
struct ArcadeReviewTests {
    private func fresh() -> (ArcadeReview, UserDefaults) {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        return (ArcadeReview(defaults: defaults), defaults)
    }

    /// A Deep End level beaten for the first time: a high point.
    private func deepEnd(_ review: ArcadeReview, now: Date = Date()) {
        review.firstCleared("shallow-reef.11", deepEnd: true, now: now)
    }

    @Test func asksOnlyAfterAHighPointAndOnlyInAppStoreBuilds() {
        let (review, _) = fresh()
        #expect(!review.shouldRequest(channel: "appstore"))
        deepEnd(review)
        #expect(review.shouldRequest(channel: "appstore"))
        #expect(!review.shouldRequest(channel: "testflight") && !review.shouldRequest(channel: "debug"))
    }

    @Test func aLevelBeatenAfterTenDeathsIsAHighPoint() {
        let (review, _) = fresh()
        for _ in 1..<GameTuning.reviewHardWonDeaths { review.died(on: "shallow-reef.8") }
        // Deaths on another level don't add up with this one's.
        review.died(on: "shallow-reef.7")
        review.firstCleared("shallow-reef.8", deepEnd: false)
        #expect(!review.shouldRequest(channel: "appstore"))

        for _ in 0..<GameTuning.reviewHardWonDeaths { review.died(on: "kelp-forest.4") }
        review.firstCleared("kelp-forest.4", deepEnd: false)
        #expect(review.shouldRequest(channel: "appstore"))
    }

    @Test func deathsCountAcrossLaunchesAndEndWithTheClear() {
        let (review, defaults) = fresh()
        for _ in 0..<5 { review.died(on: "jelly-bloom.6") }
        let relaunched = ArcadeReview(defaults: defaults)
        for _ in 0..<5 { relaunched.died(on: "jelly-bloom.6") }
        relaunched.firstCleared("jelly-bloom.6", deepEnd: false)
        #expect(relaunched.shouldRequest(channel: "appstore"))

        // Its deaths went with the clear.
        relaunched.didRequest(now: Date(timeIntervalSince1970: 0))
        relaunched.firstCleared("jelly-bloom.6", deepEnd: false)
        #expect(!relaunched.shouldRequest(channel: "appstore"))
    }

    @Test func aLevelBeatenWithoutManyDeathsIsNot() {
        let (review, _) = fresh()
        review.firstCleared("shallow-reef.10", deepEnd: false)
        #expect(!review.shouldRequest(channel: "appstore"))
    }

    @Test func theUnlockScreenCallsItOff() {
        let (review, _) = fresh()
        deepEnd(review)
        review.sawOffer()
        #expect(!review.shouldRequest(channel: "appstore"))
    }

    @Test func atMostTwiceNinetyDaysApartAndRemembered() {
        let (review, defaults) = fresh()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        deepEnd(review, now: start)
        review.didRequest(now: start)
        #expect(!review.shouldRequest(channel: "appstore", now: start))
        // A new high point too soon doesn't count.
        deepEnd(review, now: start.addingTimeInterval(30 * 86_400))
        #expect(!review.shouldRequest(channel: "appstore", now: start.addingTimeInterval(30 * 86_400)))
        let later = start.addingTimeInterval(GameTuning.reviewRetryInterval + 1)
        deepEnd(review, now: later)
        #expect(ArcadeReview(defaults: defaults).shouldRequest(channel: "appstore", now: later))
        review.didRequest(now: later)
        // That's two: never again.
        let much = later.addingTimeInterval(GameTuning.reviewRetryInterval * 3)
        deepEnd(review, now: much)
        #expect(!ArcadeReview(defaults: defaults).shouldRequest(channel: "appstore", now: much))
    }

    /// Saved before deaths were counted (1.0.1 and earlier): its requests still count.
    @Test func aStateSavedBeforeDeathsWereCountedStillLoads() {
        let (_, defaults) = fresh()
        defaults.set(Data(#"{"pending":false,"requestCount":2}"#.utf8), forKey: "biggerFish.review.v1")
        let review = ArcadeReview(defaults: defaults)
        deepEnd(review)
        #expect(!review.shouldRequest(channel: "appstore"))
    }
}
