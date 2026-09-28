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
            "Addition", "Subtraction", "Mixed + −", "Multiplication", "Division", "Mixed × ÷", "Fractions", "Exponents",
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

    @Test func twoDigitDecksMatchTheirSkill() {
        #expect(Curriculum.addNoCarry.facts.allSatisfy { $0.a % 10 + $0.b % 10 < 10 })
        #expect(Curriculum.addCarry.facts.allSatisfy { $0.a % 10 + $0.b % 10 >= 10 && $0.answer < 100 })
        #expect(Curriculum.subNoBorrow.facts.allSatisfy { $0.a % 10 >= $0.b % 10 })
        #expect(Curriculum.subBorrow.facts.allSatisfy { $0.a % 10 < $0.b % 10 && $0.answer > 0 })
        #expect(Curriculum.divHard.facts.allSatisfy { $0.a % $0.b == 0 })
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

    @Test func roundsAskEveryFactAndAtLeastTen() {
        #expect(Curriculum.cubes.roundLength == 10)           // 5 facts, each twice
        #expect(Curriculum.addCarry.roundLength == 12)
        #expect(Curriculum.powersMixed.roundLength == 13)
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
        #expect(!store.finishRound(world.levels[0], correct: 10, attempts: 12))  // 83%
        #expect(!store.isUnlocked(1, in: world))
        #expect(store.finishRound(world.levels[0], correct: 10, attempts: 11))   // 90%
        #expect(store.isUnlocked(1, in: world))
        #expect(!store.isUnlocked(2, in: world))
    }

    @Test func keepsBestScoreAndNeverUnpasses() {
        let store = ProgressStore(defaults: freshDefaults())
        let level = Curriculum.squares
        store.finishRound(level, correct: 10, attempts: 10)
        store.finishRound(level, correct: 10, attempts: 20)
        #expect(store.record(for: level) == LevelRecord(passed: true, bestPercent: 100, hasPlayed: true))
    }

    @Test func persistsAcrossLaunches() {
        let defaults = freshDefaults()
        let level = Curriculum.squares
        ProgressStore(defaults: defaults).finishRound(level, correct: 9, attempts: 10)
        #expect(ProgressStore(defaults: defaults).record(for: level) == LevelRecord(passed: true, bestPercent: 90, hasPlayed: true))
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
        var session = PracticeSession(level: Curriculum.addCarry, using: &rng)
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
