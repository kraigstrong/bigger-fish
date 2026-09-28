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

    /// One consistent shape for every wrong answer: "Not X", then the worked steps.
    @Test func wrongAnswerFeedbackShowsWorkedSteps() {
        #expect(fact(.power, 4, 2).wrongAnswerFeedback(chosen: 8) == ["Not 8", "² means two 4s:", "4 × 4 = 16"])
        #expect(fact(.add, 27, 15).wrongAnswerFeedback(chosen: 32) == ["Not 32", "20 + 10 = 30 and 7 + 5 = 12", "30 + 12 = 42"])
        #expect(fact(.add, 9, 4).wrongAnswerFeedback(chosen: 12) == ["Not 12", "Make a ten: 9 + 1 = 10", "10 + 3 = 13"])
        #expect(fact(.subtract, 52, 17).wrongAnswerFeedback(chosen: 45) == ["Not 45", "52 − 10 = 42", "42 − 7 = 35"])
        #expect(fact(.subtract, 13, 4).wrongAnswerFeedback(chosen: 8) == ["Not 8", "Back to ten: 13 − 3 = 10", "10 − 1 = 9"])
        #expect(fact(.divide, 56, 8).wrongAnswerFeedback(chosen: 48) == ["Not 48", "7 × 8 = 56", "so 56 ÷ 8 = 7"])
    }

    @Test func keyMistakesProduceTheClassicErrors() {
        var rng = SeededGenerator(seed: 1)
        #expect(KeyMistake.forgotToCarry.value(for: fact(.add, 27, 15), using: &rng) == 32)
        #expect(KeyMistake.smallerFromLarger.value(for: fact(.subtract, 52, 17), using: &rng) == 45)
        #expect(KeyMistake.addedInstead.value(for: fact(.multiply, 7, 8), using: &rng) == 15)
        #expect(KeyMistake.subtractedInstead.value(for: fact(.divide, 56, 8), using: &rng) == 48)
        #expect(KeyMistake.baseTimesExponent.value(for: fact(.power, 4, 2), using: &rng) == 8)
        // 2² = 2 × 2: the misconception gives the right answer, so it isn't offered.
        #expect(KeyMistake.baseTimesExponent.value(for: fact(.power, 2, 2), using: &rng) == nil)
        // No carry needed: forgetting to carry changes nothing.
        #expect(KeyMistake.forgotToCarry.value(for: fact(.add, 32, 25), using: &rng) == nil)
    }
}

struct ChoiceTests {
    private var allPlayable: [(Level, Fact)] {
        Curriculum.worlds.flatMap(\.levels).flatMap { level in level.facts.map { (level, $0) } }
    }

    @Test func everyFactGetsThreeUniqueChoicesWithTheKeyMistake() {
        var rng = SeededGenerator(seed: 7)
        for (level, fact) in allPlayable {
            let key = level.keyMistake(for: fact)
            for _ in 0..<20 {
                let choices = fact.choices(keyMistake: key, using: &rng)
                #expect(choices.count == 3)
                #expect(Set(choices.map(\.value)).count == 3)
                #expect(choices.allSatisfy { $0.value >= 0 })
                #expect(choices.filter { $0.kind == .correct }.map(\.value) == [fact.answer])
                // Deterministic key mistakes must always be on screen when they differ from the answer.
                let deterministic: [KeyMistake] = [.forgotToCarry, .smallerFromLarger, .addedInstead, .subtractedInstead, .baseTimesExponent]
                if deterministic.contains(key), key.value(for: fact, using: &rng) != nil {
                    #expect(choices.contains { $0.kind == .keyMistake })
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
                    let values = fact.choices(keyMistake: level.keyMistake(for: fact), using: &rng).map(\.value)
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

    @Test func mixedLevelsKeepEachOperationsKeyMistake() {
        let carryBorrow = Curriculum.worlds.first { $0.id == "addsub" }!.levels[2]
        #expect(carryBorrow.keyMistake(for: fact(.add, 27, 15)) == .forgotToCarry)
        #expect(carryBorrow.keyMistake(for: fact(.subtract, 52, 17)) == .smallerFromLarger)
    }
}

struct MasteryTests {
    private let level = Curriculum.cubes  // 5 facts

    /// Answers every fact correctly `times` times.
    private func coverAll(_ progress: inout LevelProgress, times: Int = 2) {
        for _ in 0..<times { for fact in level.facts { progress.record(.correct, factID: fact.id, level: level) } }
    }

    @Test func needsEveryFactTwice() {
        var progress = LevelProgress()
        for _ in 0..<20 { progress.record(.correct, factID: level.facts[0].id, level: level) }
        #expect(!progress.mastered)
        #expect(Mastery.coverage(progress, level: level) == (2, 10))
        coverAll(&progress)
        #expect(progress.mastered)
    }

    @Test func needsEighteenOfTheLastTwenty() {
        var progress = LevelProgress()
        for _ in 0..<3 { progress.record(.otherMistake, factID: level.facts[0].id, level: level) }
        coverAll(&progress)  // 13 answers: window not full yet
        #expect(!progress.mastered)
        for _ in 0..<7 { progress.record(.correct, factID: level.facts[0].id, level: level) }
        #expect(!progress.mastered)  // 17 of the last 20
        progress.record(.correct, factID: level.facts[0].id, level: level)
        #expect(progress.mastered)  // 18 of the last 20
    }

    @Test func keyMistakeInLastTenBlocksMastery() {
        var progress = LevelProgress()
        coverAll(&progress)
        progress.record(.keyMistake, factID: level.facts[0].id, level: level)
        for _ in 0..<9 { progress.record(.correct, factID: level.facts[0].id, level: level) }
        #expect(!progress.mastered)  // key mistake is 10th from the end
        progress.record(.correct, factID: level.facts[0].id, level: level)
        #expect(progress.mastered)  // now 11th from the end, and 19 of 20 correct
    }

    @Test func masteryIsSticky() {
        var progress = LevelProgress()
        coverAll(&progress, times: 4)
        #expect(progress.mastered)
        for _ in 0..<10 { progress.record(.keyMistake, factID: level.facts[0].id, level: level) }
        #expect(progress.mastered)
    }
}

struct ProgressStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "MathReefTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func unlocksNextLevelOnlyAfterMastery() {
        let store = ProgressStore(defaults: freshDefaults())
        let world = Curriculum.worlds.first { $0.id == "exponents" }!
        #expect(store.isUnlocked(0, in: world))
        #expect(!store.isUnlocked(1, in: world))
        var justMastered = false
        for _ in 0..<3 {
            for fact in world.levels[0].facts where store.record(.correct, fact: fact, level: world.levels[0]) {
                justMastered = true
            }
        }
        #expect(justMastered)
        #expect(store.isUnlocked(1, in: world))
        #expect(!store.isUnlocked(2, in: world))
    }

    @Test func persistsAcrossLaunches() {
        let defaults = freshDefaults()
        let level = Curriculum.squares
        ProgressStore(defaults: defaults).record(.correct, fact: level.facts[0], level: level)
        let reloaded = ProgressStore(defaults: defaults).progress(for: level)
        #expect(reloaded.correctCounts[level.facts[0].id] == 1)
        #expect(reloaded.recent == [.correct])
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

    @Test func unmasteredFactsComeFirst() {
        var rng = SeededGenerator(seed: 3)
        let level = Curriculum.squares
        let priority = Set(level.facts.suffix(3).map(\.id))
        let order = PracticeSession.dealOrder(level.facts, count: 10, priority: priority, using: &rng)
        #expect(Set(order.prefix(3).map(\.id)) == priority)
    }

    @Test func completesOnlyAfterTenCorrect() {
        var rng = SeededGenerator(seed: 5)
        var session = PracticeSession(level: Curriculum.mulHard, using: &rng)
        for _ in 0..<9 {
            session.record(.keyMistake)
            session.record(.correct)
        }
        #expect(!session.isComplete)
        session.record(.correct)
        #expect(session.isComplete)
        #expect(session.current == nil)
        #expect(session.result == SessionResult(correctAnswers: 10, totalAttempts: 19, keyMistakes: 9, otherMistakes: 0))
    }

    @Test func missedFactReturnsAfterTwoOthers() {
        var rng = SeededGenerator(seed: 8)
        var session = PracticeSession(level: Curriculum.addCarry, using: &rng)
        let missed = session.current!
        session.record(.otherMistake)
        #expect(session.current != missed)
        session.record(.correct)
        #expect(session.current != missed)
        session.record(.correct)
        #expect(session.current == missed)
    }

    @Test func missNearTheEndStillWaitsTwoFacts() {
        var session = PracticeSession(facts: [fact(.power, 5, 2)], pool: Curriculum.squares.facts, targetCorrect: 1)
        let missed = session.current!
        session.record(.keyMistake)
        #expect(session.upcoming.count == 3)
        #expect(session.upcoming[0] != missed && session.upcoming[1] != missed)
        #expect(session.upcoming[2] == missed)
    }
}
