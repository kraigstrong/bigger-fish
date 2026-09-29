import Foundation
import Testing
@testable import MathReef

/// What the results screen says after a round: title, outcome line, stars that pop in, and whether
/// the crown presentation plays.
struct RoundSummaryTests {
    private let exponents = Curriculum.worlds.first { $0.id == "exponents" }!
    private let addition = Curriculum.worlds.first { $0.id == "addition" }!

    private func freshStore() -> ProgressStore {
        let name = "RoundSummaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ProgressStore(defaults: defaults)
    }

    @Test func firstPassUnlocksTheNextLevel() {
        let summary = freshStore().recordRound(0, in: exponents, correct: 10, attempts: 12)
        #expect(summary == RoundSummary(
            title: "Level passed!", percent: 83, correct: 10, attempts: 12,
            outcome: "Level 2 unlocked!", passed: true, stars: 2, newStars: 2, newCrown: nil
        ))
    }

    @Test func replayingOnlyPopsTheStarsThatBeatTheBest() {
        let store = freshStore()
        store.recordRound(0, in: exponents, correct: 10, attempts: 12)
        let perfect = store.recordRound(0, in: exponents, correct: 12, attempts: 12)
        #expect(perfect.outcome == "Next level is open.")
        #expect(perfect.stars == 3 && perfect.newStars == 1)
        let worse = store.recordRound(0, in: exponents, correct: 10, attempts: 12)
        #expect(worse.passed && worse.newStars == 0)
    }

    @Test func missesAreEncouragingAndSayWhatsNeeded() {
        let store = freshStore()
        let oneStar = store.recordRound(0, in: exponents, correct: 7, attempts: 10)  // 70%
        #expect(oneStar.title == "Nice try!")
        #expect(!oneStar.passed && oneStar.stars == 1)
        #expect(oneStar.outcome == "Get 80% to unlock the next level.")
        let noStars = store.recordRound(0, in: exponents, correct: 5, attempts: 10)
        #expect(noStars.title == "Keep practicing" && noStars.stars == 0)
    }

    @Test func passingACheckpointEarlySkipsAhead() {
        let summary = freshStore().recordRound(6, in: addition, correct: 12, attempts: 12)  // "All to 20"
        #expect(summary.outcome == "You skipped ahead!")
        #expect(summary.newCrown == nil)
    }

    @Test func passingTheFinalReviewEarlyEarnsTheSilverCrown() {
        let last = addition.levels.count - 1
        let summary = freshStore().recordRound(last, in: addition, correct: 10, attempts: 12)
        #expect(summary.outcome == "You skipped ahead!")
        #expect(summary.newCrown == .silver)
    }

    @Test func crownsPlayOnceWhenEarnedAndAgainForGold() {
        let store = freshStore()
        #expect(store.recordRound(0, in: exponents, correct: 10, attempts: 12).newCrown == nil)
        #expect(store.recordRound(1, in: exponents, correct: 10, attempts: 12).newCrown == nil)
        let finish = store.recordRound(2, in: exponents, correct: 10, attempts: 12)
        #expect(finish.outcome == "Exponents complete!")
        #expect(finish.newCrown == .silver)

        // Silver again is not new; the last perfect level upgrades to gold, once.
        #expect(store.recordRound(2, in: exponents, correct: 10, attempts: 12).newCrown == nil)
        #expect(store.recordRound(0, in: exponents, correct: 12, attempts: 12).newCrown == nil)
        #expect(store.recordRound(1, in: exponents, correct: 12, attempts: 12).newCrown == nil)
        #expect(store.recordRound(2, in: exponents, correct: 12, attempts: 12).newCrown == .gold)
        #expect(store.recordRound(2, in: exponents, correct: 12, attempts: 12).newCrown == nil)
    }
}
