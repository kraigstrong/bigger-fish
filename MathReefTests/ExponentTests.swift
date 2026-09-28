import FishKit
import Testing
@testable import MathReef

struct ExponentQuestionTests {
    private func q(_ base: Int, _ exponent: Int) -> ExponentQuestion {
        ExponentQuestion(base: base, exponent: exponent)
    }

    @Test func evaluatesExponents() {
        #expect(q(3, 2).correctAnswer == 9)
        #expect(q(8, 2).correctAnswer == 64)
        #expect(q(2, 3).correctAnswer == 8)
        #expect(q(3, 3).correctAnswer == 27)
        #expect(q(4, 3).correctAnswer == 64)
    }

    @Test func misconceptionIsBaseTimesExponent() {
        #expect(q(4, 2).misconceptionAnswer == 8)
        #expect(q(3, 3).misconceptionAnswer == 9)
        #expect(q(4, 3).misconceptionAnswer == 12)
    }

    /// The spec's answer table (plus 9², 10², 5³, 10³): correct, base × exponent, base + exponent.
    @Test func matchesSpecTable() {
        let table: [(ExponentQuestion, Int, Int, Int)] = [
            (q(3, 2), 9, 6, 5), (q(4, 2), 16, 8, 6), (q(5, 2), 25, 10, 7),
            (q(6, 2), 36, 12, 8), (q(7, 2), 49, 14, 9), (q(8, 2), 64, 16, 10),
            (q(9, 2), 81, 18, 11), (q(10, 2), 100, 20, 12),
            (q(2, 3), 8, 6, 5), (q(3, 3), 27, 9, 6), (q(4, 3), 64, 12, 7),
            (q(5, 3), 125, 15, 8), (q(10, 3), 1000, 30, 13),
        ]
        for (question, correct, misconception, other) in table {
            #expect(question.choices == [
                ExponentChoice(value: correct, kind: .correct),
                ExponentChoice(value: misconception, kind: .baseTimesExponent),
                ExponentChoice(value: other, kind: .otherDistractor),
            ])
        }
    }

    @Test func choicesAreThreeAndUnique() {
        for question in ExponentLevel.mixed.expressions + [q(2, 2)] {
            let values = question.choices.map(\.value)
            #expect(values.count == 3)
            #expect(Set(values).count == 3)
            #expect(values.contains(question.correctAnswer))
        }
    }

    /// 2² = 2 × 2, so the misconception can't be shown; two other distractors fill in.
    @Test func dropsMisconceptionWhenItEqualsCorrect() {
        let kinds = q(2, 2).choices.map(\.kind)
        #expect(!kinds.contains(.baseTimesExponent))
        #expect(kinds.filter { $0 == .otherDistractor }.count == 2)
    }

    @Test func formatsExpandedExpression() {
        #expect(q(4, 2).prompt == "4²")
        #expect(q(4, 2).expandedExpression == "4² = 4 × 4 = 16")
        #expect(q(3, 3).expandedExpression == "3³ = 3 × 3 × 3 = 27")
        // One consistent message for every wrong answer.
        #expect(q(4, 2).wrongAnswerFeedback(chosen: 8) == ["Not 8", "² means two 4s:", "4 × 4 = 16"])
        #expect(q(4, 2).wrongAnswerFeedback(chosen: 6) == ["Not 6", "² means two 4s:", "4 × 4 = 16"])
        #expect(q(2, 3).wrongAnswerFeedback(chosen: 6) == ["Not 6", "³ means three 2s:", "2 × 2 × 2 = 8"])
    }

    @Test func classifiesAnswers() {
        let question = q(4, 2)
        #expect(question.kind(of: 16) == .correct)
        #expect(question.kind(of: 8) == .baseTimesExponent)
        #expect(question.kind(of: 6) == .otherDistractor)
    }
}

struct ExponentSessionTests {
    @Test func levelsAreSquaresThenCubesThenMixed() {
        #expect(ExponentLevel.all == [.squares, .cubes, .mixed])
        #expect(ExponentLevel.squares.expressions.map(\.prompt) == ["3²", "4²", "5²", "6²", "7²", "8²", "9²", "10²"])
        #expect(ExponentLevel.cubes.expressions.map(\.prompt) == ["2³", "3³", "4³", "5³", "10³"])
        #expect(ExponentLevel.mixed.expressions.count == 13)
        for level in ExponentLevel.all {
            #expect(!level.expressions.contains(ExponentQuestion(base: 2, exponent: 2)))
        }
    }

    /// No repeat until every expression has been used, and never twice in a row.
    @Test func randomOrderDealsFromShuffledDecks() {
        for seed in 0..<300 {
            var rng = SeededGenerator(seed: UInt64(seed))
            for level in ExponentLevel.all {
                let order = level.randomOrder(count: 10, using: &rng)
                let n = level.expressions.count
                #expect(order.count == 10)
                #expect(!zip(order, order.dropFirst()).contains { $0 == $1 })
                for deckStart in stride(from: 0, to: order.count, by: n) {
                    let deck = order[deckStart..<min(deckStart + n, order.count)]
                    #expect(Set(deck.map(\.prompt)).count == deck.count)
                }
            }
        }
    }

    @Test func randomOrderVaries() {
        var a = SeededGenerator(seed: 1), b = SeededGenerator(seed: 2)
        #expect(ExponentLevel.mixed.randomOrder(count: 10, using: &a) != ExponentLevel.mixed.randomOrder(count: 10, using: &b))
    }

    @Test func cubesLevelRequeuesWithinItsOwnPool() {
        var rng = SeededGenerator(seed: 3)
        var session = ExponentSession(level: .cubes, using: &rng)
        let missed = session.current!
        session.answer(missed.misconceptionAnswer)
        #expect(session.upcoming.allSatisfy { $0.exponent == 3 })
        #expect(session.upcoming[0] != missed && session.upcoming[1] != missed)
    }

    @Test func completesOnlyAfterTenCorrect() {
        var rng = SeededGenerator(seed: 7)
        var session = ExponentSession(level: .mixed, using: &rng)
        for _ in 0..<9 {
            let question = session.current!
            session.answer(question.misconceptionAnswer)
            session.answer(session.current!.correctAnswer)
        }
        #expect(!session.isComplete)
        #expect(session.result.correctAnswers == 9)
        session.answer(session.current!.correctAnswer)
        #expect(session.isComplete)
        #expect(session.current == nil)
        #expect(session.result.correctAnswers == 10)
        #expect(session.result.totalAttempts == 19)
    }

    @Test func missedQuestionReturnsAfterTwoOthers() {
        var rng = SeededGenerator(seed: 7)
        var session = ExponentSession(level: .mixed, using: &rng)
        let missed = session.current!
        session.answer(missed.misconceptionAnswer)
        #expect(session.current != missed)
        session.answer(session.current!.correctAnswer)
        #expect(session.current != missed)
        session.answer(session.current!.correctAnswer)
        #expect(session.current == missed)
    }

    @Test func missNearTheEndStillWaitsTwoQuestions() {
        var session = ExponentSession(
            questions: [ExponentQuestion(base: 5, exponent: 2)], pool: ExponentLevel.squares.expressions, targetCorrect: 1
        )
        let missed = session.current!
        session.answer(missed.correctAnswer + 100)
        let next = session.upcoming
        #expect(next.count == 3)
        #expect(next[0] != missed && next[1] != missed)
        #expect(next[2] == missed)
    }

    @Test func separatesMisconceptionFromOtherMistakes() {
        var rng = SeededGenerator(seed: 7)
        var session = ExponentSession(level: .mixed, using: &rng)
        let first = session.current!
        session.answer(first.misconceptionAnswer)
        let second = session.current!
        session.answer(second.choices.first { $0.kind == .otherDistractor }!.value)
        session.answer(session.current!.correctAnswer)

        let result = session.result
        #expect(result.baseTimesExponentMistakes == 1)
        #expect(result.otherMistakes == 1)
        #expect(result.correctAnswers == 1)
        #expect(result.totalAttempts == 3)
        #expect(abs(result.accuracy - 1.0 / 3.0) < 1e-9)
        #expect(session.streak == 1)
    }
}
