import FishKit
import Testing
@testable import MathReef

/// Checks everything a kid reads during play, round by round, the way the scene builds rounds:
/// every question dealt (level, review, and padding), its answer choices, and the worked examples and
/// explanations shown on screen. Per-level deck rules live in `CurriculumTests`.
struct ContentAuditTests {
    /// The rounds a kid could see: many shuffles of every level, built as `PracticeScene` builds them.
    private func rounds(perLevel count: Int = 40) -> [(world: World, index: Int, questions: [Fact])] {
        var rng = SeededGenerator(seed: 2026)
        var result: [(World, Int, [Fact])] = []
        for world in Curriculum.worlds {
            for index in world.levels.indices {
                let level = world.levels[index]
                for _ in 0..<count {
                    var session = PracticeSession(
                        level: level,
                        review: world.reviewPool(before: index),
                        reviewCount: level.isCheckpoint ? 0 : ReefTuning.reviewPerRound,
                        requeueGap: ReefTuning.requeueGap,
                        using: &rng
                    )
                    var asked: [Fact] = []
                    while let fact = session.current, asked.count < 200 {
                        asked.append(fact)
                        session.record(correct: true)
                    }
                    result.append((world, index, asked))
                }
            }
        }
        return result
    }

    @Test func everyQuestionInEveryRoundIsValid() {
        for (world, index, questions) in rounds() {
            let id = world.levels[index].id
            #expect(!questions.isEmpty, "\(id): empty round")
            for fact in questions {
                #expect(fact.answer >= 0, "\(id): \(fact.prompt) has a negative answer")
                if fact.op == .divide {
                    #expect(fact.b != 0 && fact.a % fact.b == 0, "\(id): \(fact.prompt) doesn't divide evenly")
                }
            }
        }
    }

    /// Choices for every question as actually dealt, review and padding included.
    @Test func everyDealtQuestionHasThreeGoodChoices() {
        var rng = SeededGenerator(seed: 99)
        for (world, index, questions) in rounds(perLevel: 10) {
            for fact in questions {
                let choices = fact.choices(using: &rng)
                let values = choices.map(\.value)
                let where_ = "\(world.levels[index].id): \(fact.prompt)"
                #expect(choices.count == 3, "\(where_)")
                #expect(Set(values).count == 3, "\(where_) has duplicate choices \(values)")
                #expect(values.allSatisfy { $0 >= 0 }, "\(where_) has a negative choice \(values)")
                #expect(choices.filter(\.isCorrect).map(\.value) == [fact.answer], "\(where_)")
            }
        }
    }

    /// A round asks only its own level and earlier levels in the same world, and asks every one of
    /// its own facts.
    @Test func roundsStayInTheirWorldAndCoverTheLevel() {
        for (world, index, questions) in rounds() {
            let level = world.levels[index]
            let allowed = Set(level.facts + world.reviewPool(before: index))
            let strays = questions.filter { !allowed.contains($0) }
            #expect(strays.isEmpty, "\(level.id) asked \(strays.map(\.prompt)) from outside the level and earlier levels")
            #expect(Set(level.facts).isSubset(of: Set(questions)), "\(level.id) skipped some of its facts")
            let reviewShare = Double(questions.filter { !level.facts.contains($0) }.count) / Double(questions.count)
            #expect(reviewShare <= 0.3, "\(level.id): \(Int(reviewShare * 100))% of the round is review")
        }
    }

    /// The worked examples on intro panels ("= 3² = 3 × 3 = 9") are arithmetically right.
    @Test func introExamplesAreCorrect() {
        for level in Curriculum.worlds.flatMap(\.levels) {
            for line in level.intro where line.hasPrefix("= ") {
                #expect(allSidesEqual(String(line.dropFirst(2))), "\(level.id): \"\(line)\"")
            }
        }
    }

    /// The explanation after a wrong answer ("9 + 4 = 13", "4 × 4 = 16") is right for every fact.
    @Test func wrongAnswerExplanationsAreCorrect() {
        for fact in Set(Curriculum.worlds.flatMap(\.levels).flatMap(\.facts)) {
            #expect(allSidesEqual(fact.solution), "\(fact.solution)")
            let feedback = fact.wrongAnswerFeedback()
            #expect(feedback.first == "Oops!")
            #expect(allSidesEqual(feedback.last!), "\(feedback)")
            if fact.op == .power {
                // "² means two 4s:" names the right count and base.
                #expect(feedback[1].contains("\(fact.a)s"), "\(feedback)")
            }
        }
    }

    // MARK: A tiny evaluator for what's printed on screen

    /// "3² = 3 × 3 = 9": every side evaluates to the same number.
    private func allSidesEqual(_ text: String) -> Bool {
        let values = text.components(separatedBy: " = ").map(evaluate)
        return values.count >= 2 && !values.contains(nil) && Set(values.compactMap { $0 }).count == 1
    }

    /// Evaluates one side: whole numbers with +, −, ×, ÷ (left to right, × and ÷ first) and
    /// superscript exponents like 4² or 10³.
    private func evaluate(_ side: String) -> Int? {
        let superscripts: [Character: Int] = ["⁰": 0, "¹": 1, "²": 2, "³": 3, "⁴": 4, "⁵": 5, "⁶": 6, "⁷": 7, "⁸": 8, "⁹": 9]
        func term(_ token: String) -> Int? {
            let digits = token.prefix { $0.isASCII && $0.isNumber }
            guard let base = Int(digits) else { return nil }
            let power = token.dropFirst(digits.count)
            guard !power.isEmpty else { return base }
            let exponent = power.reduce(0) { $0 * 10 + (superscripts[$1] ?? 0) }
            return (0..<exponent).reduce(1) { acc, _ in acc * base }
        }
        let tokens = side.split(separator: " ").map(String.init)
        guard tokens.count % 2 == 1 else { return nil }
        // First pass: × and ÷.
        var sums: [Int] = []
        var signs: [String] = []
        guard var current = term(tokens[0]) else { return nil }
        var i = 1
        while i < tokens.count {
            let op = tokens[i]
            guard let next = term(tokens[i + 1]) else { return nil }
            switch op {
            case "×": current *= next
            case "÷":
                guard next != 0, current % next == 0 else { return nil }
                current /= next
            case "+", "−":
                sums.append(current)
                signs.append(op)
                current = next
            default: return nil
            }
            i += 2
        }
        sums.append(current)
        return zip(signs, sums.dropFirst()).reduce(sums[0]) { $0 + ($1.0 == "+" ? $1.1 : -$1.1) }
    }

    @Test func theEvaluatorItselfWorks() {
        #expect(allSidesEqual("27 + 15 = 42"))
        #expect(allSidesEqual("52 − 17 = 35"))
        #expect(allSidesEqual("4² = 4 × 4 = 16"))
        #expect(allSidesEqual("10³ = 10 × 10 × 10 = 1000"))
        #expect(allSidesEqual("56 ÷ 8 = 7"))
        #expect(!allSidesEqual("9 + 4 = 12"))
        #expect(!allSidesEqual("3² = 3 × 3 = 6"))
    }
}
