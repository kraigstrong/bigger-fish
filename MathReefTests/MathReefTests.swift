import FishKit
import Foundation
import Testing
@testable import MathReef

private func fact(_ op: MathOp, _ a: Int, _ b: Int) -> Fact { Fact(op: op, a: a, b: b) }

struct FactTests {
    @Test func evaluatesEveryOperation() {
        #expect(fact(.add, 27, 15).answer == 42)
        #expect(fact(.subtract, 52, 17).answer == 35)
        #expect(fact(.multiply, 7, 8).answer == 56)
        #expect(fact(.divide, 56, 8).answer == 7)
        #expect(fact(.power, 4, 3).answer == 64)
        #expect(fact(.power, 10, 3).answer == 1000)
    }

    @Test func formatsPromptsAndSolutions() {
        #expect(fact(.add, 27, 15).prompt == "27 + 15")
        #expect(fact(.subtract, 52, 17).prompt == "52 − 17")
        #expect(fact(.divide, 56, 8).solution == "56 ÷ 8 = 7")
        #expect(fact(.power, 4, 2).solution == "4² = 4 × 4 = 16")
        #expect(fact(.power, 3, 3).solution == "3³ = 3 × 3 × 3 = 27")
    }

    /// Wrong answers show just the solution; exponents also restate what the small number means.
    @Test func wrongAnswerFeedbackIsSimple() {
        #expect(fact(.add, 9, 4).wrongAnswerFeedback(chosen: 12) == ["Not 12", "9 + 4 = 13"])
        #expect(fact(.subtract, 52, 17).wrongAnswerFeedback(chosen: 45) == ["Not 45", "52 − 17 = 35"])
        #expect(fact(.divide, 56, 8).wrongAnswerFeedback(chosen: 48) == ["Not 48", "56 ÷ 8 = 7"])
        #expect(fact(.power, 4, 2).wrongAnswerFeedback(chosen: 8) == ["Not 8", "² means two 4s:", "4 × 4 = 16"])
    }

    /// Classic slips are in the wrong-answer pool (they just aren't labeled specially).
    @Test func wrongCandidatesIncludeClassicSlips() {
        #expect(fact(.add, 27, 15).wrongCandidates.contains(32))        // forgot to carry
        #expect(fact(.subtract, 52, 17).wrongCandidates.contains(45))   // smaller from larger
        #expect(fact(.multiply, 7, 8).wrongCandidates.contains(15))     // added instead
        #expect(fact(.divide, 56, 8).wrongCandidates.contains(48))      // subtracted instead
        #expect(fact(.power, 4, 2).wrongCandidates.contains(8))         // base × exponent
    }
}

struct ChoiceTests {
    @Test func everyFactGetsThreeUniqueChoicesWithOneCorrect() {
        var rng = SeededGenerator(seed: 7)
        for fact in Curriculum.worlds.flatMap(\.levels).flatMap(\.facts) {
            for _ in 0..<20 {
                let choices = fact.choices(using: &rng)
                #expect(choices.count == 3)
                #expect(Set(choices.map(\.value)).count == 3)
                #expect(choices.allSatisfy { $0.value >= 0 })
                #expect(choices.filter(\.isCorrect).map(\.value) == [fact.answer])
            }
        }
    }

    /// Single-digit questions never get far-off answers like 19 for 7 + 2 (adding instead of
    /// subtracting is the one exception: it's a real sign mix-up).
    @Test func smallQuestionsGetCloseWrongAnswers() {
        var rng = SeededGenerator(seed: 11)
        for level in [Curriculum.addPlus12, Curriculum.addWithin10, Curriculum.subMinus12, Curriculum.subWithin10] {
            for fact in level.facts {
                for _ in 0..<20 {
                    let signMixUp = fact.op == .subtract ? fact.a + fact.b : nil
                    #expect(fact.choices(using: &rng).allSatisfy { abs($0.value - fact.answer) < 10 || $0.value == signMixUp },
                            "\(fact.prompt)")
                }
            }
        }
    }

    /// The correct answer must not always be the biggest (or smallest) number on screen.
    @Test func correctAnswerIsNotAlwaysTheExtreme() {
        var rng = SeededGenerator(seed: 9)
        for level in Curriculum.worlds.flatMap(\.levels) {
            var biggest = 0, smallest = 0, total = 0
            for fact in level.facts {
                for _ in 0..<20 {
                    let values = fact.choices(using: &rng).map(\.value)
                    if values.max() == fact.answer { biggest += 1 }
                    if values.min() == fact.answer { smallest += 1 }
                    total += 1
                }
            }
            #expect(biggest < total, "\(level.id): correct answer was always the biggest")
            #expect(smallest < total, "\(level.id): correct answer was always the smallest")
        }
    }
}

struct CurriculumTests {
    @Test func worldsAreInOrderWithFractionsComingSoon() {
        #expect(Curriculum.worlds.map(\.title) == [
            "Addition", "Subtraction", "Multiplication", "Division", "Fractions", "Exponents",
        ])
        #expect(Curriculum.worlds.filter(\.comingSoon).map(\.id) == ["fractions"])
    }

    @Test func levelIDsAreUniqueAndDecksAreSmallAndValid() {
        let levels = Curriculum.worlds.flatMap(\.levels)
        #expect(Set(levels.map(\.id)).count == levels.count)
        for level in levels {
            #expect((5...16).contains(level.facts.count), "\(level.id) has \(level.facts.count) facts")
            #expect(Set(level.facts).count == level.facts.count)
            #expect(level.facts.allSatisfy { $0.answer >= 0 })
            #expect(!level.facts.contains(fact(.power, 2, 2)))
        }
    }

    /// Each level's questions match the one strategy it practices.
    @Test func decksMatchTheirSkill() {
        typealias C = Curriculum
        #expect(C.addPlus12.facts.allSatisfy { [1, 2].contains($0.b) && $0.answer <= 10 })
        #expect(C.addMake10.facts.allSatisfy { $0.answer == 10 })
        #expect(C.addDoubles.facts.allSatisfy { $0.a == $0.b })
        #expect(C.addWithin10.facts.allSatisfy { $0.answer < 10 && $0.a >= 3 && $0.b >= 3 && $0.a != $0.b })
        #expect(C.addNearDoubles.facts.allSatisfy { abs($0.a - $0.b) == 1 })
        #expect(C.addCross10.facts.allSatisfy { $0.a < 10 && $0.b < 10 && $0.answer > 10 })
        #expect(C.addOnes.facts.allSatisfy { $0.b < 10 && $0.a % 10 + $0.b < 10 })
        #expect(C.addTens.facts.allSatisfy { $0.b % 10 == 0 && $0.answer < 100 })
        #expect(C.add2Digit.facts.allSatisfy { $0.b >= 10 && $0.a % 10 + $0.b % 10 < 10 })
        #expect(C.addCarryOnes.facts.allSatisfy { $0.b < 10 && $0.a % 10 + $0.b >= 10 && $0.answer < 100 })
        #expect(C.addCarry.facts.allSatisfy { $0.b >= 10 && $0.a % 10 + $0.b % 10 >= 10 && $0.answer < 100 })
        #expect(C.subMinus12.facts.allSatisfy { [1, 2].contains($0.b) })
        #expect(C.subFrom10.facts.allSatisfy { $0.a == 10 })
        #expect(C.subDoubles.facts.allSatisfy { $0.a == 2 * $0.b })
        #expect(C.subBack10.facts.allSatisfy { $0.a > 10 && $0.answer < 10 })
        #expect(C.subOnes.facts.allSatisfy { $0.b < 10 && $0.a % 10 >= $0.b })
        #expect(C.subTens.facts.allSatisfy { $0.b % 10 == 0 && $0.answer > 0 })
        #expect(C.sub2Digit.facts.allSatisfy { $0.b >= 10 && $0.a % 10 >= $0.b % 10 })
        #expect(C.subBorrowOnes.facts.allSatisfy { $0.b < 10 && $0.a % 10 < $0.b && $0.answer > 0 })
        #expect(C.subBorrow.facts.allSatisfy { $0.b >= 10 && $0.a % 10 < $0.b % 10 && $0.answer > 0 })
        #expect(C.divHard.facts.allSatisfy { $0.a % $0.b == 0 })
    }

    /// Addition and subtraction climb gradually: strategy levels, with checkpoints as skip tests.
    @Test func additionAndSubtractionHaveGradualProgressions() {
        for id in ["addition", "subtraction"] {
            let world = Curriculum.worlds.first { $0.id == id }!
            #expect(world.levels.count == 13)
            #expect(world.levels.indices.filter { world.levels[$0].isCheckpoint } == [6, 12])
            #expect(world.levels[0].facts.allSatisfy { $0.answer <= 10 })
        }
    }

    /// A checkpoint only asks questions from levels before it (subtraction's also mix in addition).
    @Test func checkpointsReviewEarlierLevels() {
        let addition = Curriculum.worlds[0], subtraction = Curriculum.worlds[1]
        for (world, index) in [(addition, 6), (addition, 12), (subtraction, 6), (subtraction, 12)] {
            let earlier = Set(world.reviewPool(before: index) + addition.levels.flatMap(\.facts))
            let checkpoint = world.levels[index]
            #expect(checkpoint.facts.count == 12)
            #expect(checkpoint.facts.allSatisfy { earlier.contains($0) }, "\(checkpoint.id)")
        }
    }

    @Test func exponentsAreSquaresThenCubesThenMixed() {
        let exponents = Curriculum.worlds.first { $0.id == "exponents" }!
        #expect(exponents.levels.map(\.title) == ["Squares", "Cubes", "Mixed"])
        #expect(exponents.levels[0].facts.map(\.prompt) == ["3²", "4²", "5²", "6²", "7²", "8²", "9²", "10²"])
        #expect(exponents.levels[1].facts.map(\.prompt) == ["2³", "3³", "4³", "5³", "10³"])
        #expect(exponents.levels[2].facts.count == 13)
    }

    @Test func onlyExponentsHaveIntroText() {
        for world in Curriculum.worlds where world.id != "exponents" {
            let empty = world.levels.allSatisfy { $0.intro.isEmpty }
            #expect(empty, "\(world.id) has intro text")
        }
    }

    @Test func mixedWorldsAreFoldedIn() {
        #expect(Curriculum.worlds[1].levels.last?.title == "+ and − review")
        #expect(Curriculum.worlds[3].levels.last?.title == "× and ÷")
    }
}

struct PassRuleTests {
    @Test func needsNinetyPercent() {
        #expect(PassRule.passes(correct: 9, attempts: 10))
        #expect(PassRule.passes(correct: 10, attempts: 11))    // 90.9%
        #expect(!PassRule.passes(correct: 16, attempts: 18))   // 88.9%
        #expect(!PassRule.passes(correct: 0, attempts: 0))
        #expect(PassRule.percent(correct: 16, attempts: 18) == 88)  // never rounds up to a pass
    }
}

struct ProgressStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "MathReefTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func passingUnlocksTheNextLevel() {
        let store = ProgressStore(defaults: freshDefaults())
        let world = Curriculum.worlds.first { $0.id == "exponents" }!
        #expect(store.isUnlocked(0, in: world))
        #expect(!store.isUnlocked(1, in: world))
        #expect(!store.finishRound(0, in: world, correct: 10, attempts: 12))  // 83%
        #expect(!store.isUnlocked(1, in: world))
        #expect(store.finishRound(0, in: world, correct: 10, attempts: 11))   // 90%
        #expect(store.isUnlocked(1, in: world))
        #expect(!store.isUnlocked(2, in: world))
    }

    @Test func keepsBestScoreAndNeverUnpasses() {
        let store = ProgressStore(defaults: freshDefaults())
        let world = Curriculum.worlds.first { $0.id == "exponents" }!, level = world.levels[0]
        store.finishRound(0, in: world, correct: 10, attempts: 10)
        store.finishRound(0, in: world, correct: 10, attempts: 20)
        #expect(store.record(for: level) == LevelRecord(passed: true, bestPercent: 100, hasPlayed: true, passCount: 1, perfect: true))
    }

    /// Checkpoints are skip tests: always playable, and passing one passes everything before it.
    @Test func checkpointsAreSkipTests() {
        let store = ProgressStore(defaults: freshDefaults())
        let world = Curriculum.worlds[0]
        #expect(!store.isUnlocked(5, in: world))
        #expect(store.isUnlocked(6, in: world) && store.isSkipTest(6, in: world))
        #expect(!store.isUnlocked(7, in: world))
        #expect(!store.finishRound(6, in: world, correct: 12, attempts: 15))  // failed: nothing changes
        #expect(!store.record(for: world.levels[0]).passed)
        #expect(store.finishRound(6, in: world, correct: 12, attempts: 13))
        #expect((0...6).allSatisfy { store.record(for: world.levels[$0]).passed })
        #expect(store.isUnlocked(7, in: world) && !store.isSkipTest(6, in: world))
        #expect(!store.record(for: world.levels[7]).passed)
    }

    /// ★ pass · ★★ pass again · ★★★ perfect round; silver crown = every level passed, gold = all ★★★.
    @Test func starsAndCrowns() {
        let store = ProgressStore(defaults: freshDefaults())
        let world = Curriculum.worlds.first { $0.id == "exponents" }!
        store.finishRound(0, in: world, correct: 10, attempts: 11)
        #expect(store.record(for: world.levels[0]).stars == 1)
        store.finishRound(0, in: world, correct: 10, attempts: 11)
        #expect(store.record(for: world.levels[0]).stars == 2)
        store.finishRound(0, in: world, correct: 10, attempts: 10)
        #expect(store.record(for: world.levels[0]).stars == 3)
        #expect(store.crown(for: world) == .none)
        store.finishRound(1, in: world, correct: 10, attempts: 11)
        store.finishRound(2, in: world, correct: 13, attempts: 14)
        #expect(store.crown(for: world) == .silver)
        #expect(store.stars(in: world) == (5, 9))
        store.finishRound(1, in: world, correct: 10, attempts: 10)
        store.finishRound(2, in: world, correct: 13, attempts: 13)
        #expect(store.crown(for: world) == .gold)
    }

    /// Records saved before stars existed still load (missing fields default to zero).
    @Test func decodesOlderRecords() throws {
        let old = #"{"exp.1":{"passed":true,"bestPercent":92,"hasPlayed":true}}"#
        let records = try JSONDecoder().decode([String: LevelRecord].self, from: Data(old.utf8))
        #expect(records["exp.1"] == LevelRecord(passed: true, bestPercent: 92, hasPlayed: true, passCount: 0, perfect: false))
        #expect(records["exp.1"]?.stars == 1)
    }

    @Test func persistsAcrossLaunches() {
        let defaults = freshDefaults()
        let world = Curriculum.worlds.first { $0.id == "exponents" }!, level = world.levels[0]
        ProgressStore(defaults: defaults).finishRound(0, in: world, correct: 9, attempts: 10)
        #expect(ProgressStore(defaults: defaults).record(for: level) == LevelRecord(passed: true, bestPercent: 90, hasPlayed: true, passCount: 1))
    }
}

struct PracticeSessionTests {
    @Test func dealsWithoutRepeatsUntilTheDeckIsUsed() {
        for seed in 0..<200 {
            var rng = SeededGenerator(seed: UInt64(seed))
            for level in Curriculum.worlds.flatMap(\.levels) {
                let order = PracticeSession.dealOrder(level.facts, count: 10, using: &rng)
                let n = level.facts.count
                #expect(order.count == 10)
                #expect(!zip(order, order.dropFirst()).contains { $0 == $1 })
                for start in stride(from: 0, to: order.count, by: n) {
                    let deck = order[start..<min(start + n, order.count)]
                    #expect(Set(deck).count == deck.count)
                }
            }
        }
    }

    /// About 70% new, 30% review: every level question once plus review from earlier levels.
    @Test func roundMixesInReviewAndPadsToTen() {
        var rng = SeededGenerator(seed: 4)
        let world = Curriculum.worlds[0]
        for _ in 0..<50 {
            let review = world.reviewPool(before: 3)
            let round = PracticeSession.roundOrder(world.levels[3].facts, review: review, reviewCount: 3, using: &rng)
            #expect(round.count == 11)
            #expect(Set(world.levels[3].facts).isSubset(of: Set(round)))
            #expect(round.filter { !world.levels[3].facts.contains($0) }.count == 3)
            #expect(round.allSatisfy { world.levels[3].facts.contains($0) || review.contains($0) })
            #expect(!zip(round, round.dropFirst()).contains { $0 == $1 })
        }
        let first = PracticeSession.roundOrder(world.levels[0].facts, review: [], reviewCount: 3, using: &rng)
        #expect(first.count == PracticeSession.minimumRound)  // 8 facts padded to 10, no review available
    }

    @Test func roundAsksEveryFactAndEndsWhenAllAreRight() {
        var rng = SeededGenerator(seed: 5)
        var session = PracticeSession(level: Curriculum.mulHard, using: &rng)  // 12 facts
        #expect(Set(session.upcoming) == Set(Curriculum.mulHard.facts))
        for _ in 0..<2 { session.record(correct: false) }
        for _ in 0..<11 { session.record(correct: true) }
        #expect(!session.isComplete)
        session.record(correct: true)
        #expect(session.isComplete)
        #expect(session.current == nil)
        #expect(session.result == SessionResult(correctAnswers: 12, totalAttempts: 14))
        #expect(session.result.percent == 85)
        #expect(!session.result.passed)
    }

    @Test func missedFactReturnsAfterTwoOthers() {
        var rng = SeededGenerator(seed: 8)
        var session = PracticeSession(level: Curriculum.mulHard, using: &rng)
        let missed = session.current!
        session.record(correct: false)
        #expect(session.current != missed)
        session.record(correct: true)
        #expect(session.current != missed)
        session.record(correct: true)
        #expect(session.current == missed)
    }

    @Test func missNearTheEndStillWaitsTwoFacts() {
        var session = PracticeSession(facts: [fact(.power, 5, 2)], pool: Curriculum.squares.facts, targetCorrect: 1)
        let missed = session.current!
        session.record(correct: false)
        #expect(session.upcoming.count == 3)
        #expect(session.upcoming[0] != missed && session.upcoming[1] != missed)
        #expect(session.upcoming[2] == missed)
    }
}
