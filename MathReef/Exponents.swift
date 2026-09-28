import Foundation

// Math Reef exponent practice: pure question/session logic. The scene lives in ExponentScene.swift.

enum ExponentAnswerKind: Equatable {
    case correct
    /// The misconception being tested: reading b^e as b × e.
    case baseTimesExponent
    case otherDistractor
}

struct ExponentChoice: Equatable {
    let value: Int
    let kind: ExponentAnswerKind
}

struct ExponentQuestion: Equatable {
    let base: Int
    let exponent: Int

    /// Integer power; the POC only uses small positive bases and exponents.
    var correctAnswer: Int {
        (0..<exponent).reduce(1) { product, _ in product * base }
    }

    var misconceptionAnswer: Int { base * exponent }

    /// Exactly three unique choices: the correct answer, the base × exponent answer whenever it
    /// differs from the correct one, and plausible distractors (preferably base + exponent).
    var choices: [ExponentChoice] {
        var list = [ExponentChoice(value: correctAnswer, kind: .correct)]
        if misconceptionAnswer != correctAnswer {
            list.append(ExponentChoice(value: misconceptionAnswer, kind: .baseTimesExponent))
        }
        let candidates = [
            base + exponent, correctAnswer + 1, correctAnswer - 1,
            correctAnswer + 2, correctAnswer - 2, misconceptionAnswer + 1,
        ]
        for candidate in candidates where list.count < 3 {
            if candidate > 0 && !list.contains(where: { $0.value == candidate }) {
                list.append(ExponentChoice(value: candidate, kind: .otherDistractor))
            }
        }
        return list
    }

    func kind(of answer: Int) -> ExponentAnswerKind {
        choices.first { $0.value == answer }?.kind ?? .otherDistractor
    }

    /// "4²"
    var prompt: String { "\(base)\(Self.superscript(exponent))" }

    /// "4 × 4"
    var factors: String {
        Array(repeating: "\(base)", count: exponent).joined(separator: " × ")
    }

    /// "4² = 4 × 4 = 16"
    var expandedExpression: String { "\(prompt) = \(factors) = \(correctAnswer)" }

    /// The same feedback for every wrong answer (base × exponent or otherwise):
    /// "Not 8" / "² means two 4s:" / "4 × 4 = 16"
    func wrongAnswerFeedback(chosen: Int) -> [String] {
        [
            "Not \(chosen)",
            "\(Self.superscript(exponent)) means \(Self.countWord(exponent)) \(base)s:",
            "\(factors) = \(correctAnswer)",
        ]
    }

    static func superscript(_ n: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return String(String(n).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    private static func countWord(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return words.indices.contains(n) ? words[n] : "\(n)"
    }
}

struct ExponentSessionResult: Equatable {
    var correctAnswers = 0
    var totalAttempts = 0
    var baseTimesExponentMistakes = 0
    var otherMistakes = 0
    var elapsedTime: TimeInterval = 0

    /// 0...1
    var accuracy: Double {
        totalAttempts == 0 ? 0 : Double(correctAnswers) / Double(totalAttempts)
    }
}

/// Lab levels: squares, then cubes, then both mixed.
struct ExponentLevel: Equatable {
    let title: String
    /// Each expression once. 2² is avoided everywhere because 2 × 2 = 2² hides the misconception.
    let expressions: [ExponentQuestion]

    static let squares = ExponentLevel(
        title: "Squares", expressions: (3...10).map { ExponentQuestion(base: $0, exponent: 2) }
    )
    static let cubes = ExponentLevel(
        title: "Cubes", expressions: [2, 3, 4, 5, 10].map { ExponentQuestion(base: $0, exponent: 3) }
    )
    static let mixed = ExponentLevel(title: "Mixed", expressions: squares.expressions + cubes.expressions)
    static let all: [ExponentLevel] = [squares, cubes, mixed]

    /// A random order dealt from shuffled decks: no expression repeats until every expression has
    /// been used, and the same expression never appears twice in a row.
    func randomOrder<G: RandomNumberGenerator>(count: Int, using rng: inout G) -> [ExponentQuestion] {
        var order: [ExponentQuestion] = []
        while order.count < count && !expressions.isEmpty {
            var deck = expressions.shuffled(using: &rng)
            if deck.count > 1, deck.first == order.last {
                deck.swapAt(0, Int.random(in: 1..<deck.count, using: &rng))
            }
            order += deck
        }
        return Array(order.prefix(count))
    }
}

/// A level session: ends after `targetCorrect` correct answers.
/// Missed questions return after at least `requeueGap` other questions.
struct ExponentSession {
    let targetCorrect: Int
    let requeueGap: Int
    /// `upcoming[0]` is the current question.
    private(set) var upcoming: [ExponentQuestion]
    private(set) var result = ExponentSessionResult()
    private(set) var streak = 0
    private let pool: [ExponentQuestion]
    private var fillerCursor = 0

    /// Random order for this level (see `ExponentLevel.randomOrder`).
    init(level: ExponentLevel = .mixed, targetCorrect: Int = 10, requeueGap: Int = 2) {
        var rng = SystemRandomNumberGenerator()
        self.init(level: level, targetCorrect: targetCorrect, requeueGap: requeueGap, using: &rng)
    }

    init<G: RandomNumberGenerator>(level: ExponentLevel, targetCorrect: Int = 10, requeueGap: Int = 2, using rng: inout G) {
        self.init(
            questions: level.randomOrder(count: targetCorrect, using: &rng), pool: level.expressions,
            targetCorrect: targetCorrect, requeueGap: requeueGap
        )
    }

    init(questions: [ExponentQuestion], pool: [ExponentQuestion], targetCorrect: Int = 10, requeueGap: Int = 2) {
        self.targetCorrect = targetCorrect
        self.requeueGap = requeueGap
        self.pool = pool
        upcoming = questions
        while upcoming.count < targetCorrect && appendFiller(avoiding: nil) {}
    }

    var isComplete: Bool { result.correctAnswers >= targetCorrect }
    var current: ExponentQuestion? { isComplete ? nil : upcoming.first }

    /// Records an attempt at the current question and advances the queue.
    @discardableResult
    mutating func answer(_ value: Int) -> ExponentAnswerKind {
        guard let question = current else { return .otherDistractor }
        let kind = question.kind(of: value)
        result.totalAttempts += 1
        upcoming.removeFirst()
        switch kind {
        case .correct:
            result.correctAnswers += 1
            streak += 1
        case .baseTimesExponent:
            result.baseTimesExponentMistakes += 1
            streak = 0
            requeue(question)
        case .otherDistractor:
            result.otherMistakes += 1
            streak = 0
            requeue(question)
        }
        return kind
    }

    private mutating func requeue(_ question: ExponentQuestion) {
        // Near the end of the queue, pad with other expressions so a miss never repeats immediately.
        while upcoming.count < requeueGap && appendFiller(avoiding: question) {}
        // Don't land next to another copy of the same expression.
        var index = requeueGap
        while index < upcoming.count && (upcoming[index] == question || upcoming[index - 1] == question) {
            index += 1
        }
        upcoming.insert(question, at: index)
    }

    /// Returns false if the pool has nothing usable (e.g. a single-expression pool).
    @discardableResult
    private mutating func appendFiller(avoiding question: ExponentQuestion?) -> Bool {
        for _ in 0..<pool.count {
            let candidate = pool[fillerCursor % pool.count]
            fillerCursor += 1
            if candidate != question && candidate != upcoming.last {
                upcoming.append(candidate)
                return true
            }
        }
        return false
    }
}
