import Foundation

// Math Reef facts: prompts, answers, solutions, and plausible wrong answers.
// Pure logic; the scene lives in PracticeScene.swift.

enum MathOp: String, Codable {
    case add, subtract, multiply, divide, power
}

struct Choice: Equatable {
    let value: Int
    let isCorrect: Bool
}

struct Fact: Hashable {
    let op: MathOp
    let a: Int
    let b: Int

    var answer: Int {
        switch op {
        case .add: a + b
        case .subtract: a - b
        case .multiply: a * b
        case .divide: a / b
        case .power: (0..<b).reduce(1) { product, _ in product * a }
        }
    }

    /// "27 + 15", "4²"
    var prompt: String {
        switch op {
        case .add: "\(a) + \(b)"
        case .subtract: "\(a) − \(b)"
        case .multiply: "\(a) × \(b)"
        case .divide: "\(a) ÷ \(b)"
        case .power: "\(a)\(Self.superscript(b))"
        }
    }

    /// "27 + 15 = 42", "4² = 4 × 4 = 16"
    var solution: String {
        op == .power ? "\(prompt) = \(factors) = \(answer)" : "\(prompt) = \(answer)"
    }

    /// Shown after a wrong answer: "Not 12" then the solution. Exponents also restate what the
    /// small number means, since that's the notation itself rather than a tip.
    func wrongAnswerFeedback(chosen: Int) -> [String] {
        if op == .power {
            return ["Not \(chosen)", "\(Self.superscript(b)) means \(Self.countWord(b)) \(a)s:", "\(factors) = \(answer)"]
        }
        return ["Not \(chosen)", solution]
    }

    /// Plausible wrong answers, including the classic slips for each operation
    /// (forgetting to carry, adding instead of multiplying, 4² → 8, ...).
    var wrongCandidates: [Int] {
        let n = answer
        switch op {
        case .add:
            let noCarry = (a / 10 + b / 10) * 10 + (a % 10 + b % 10) % 10
            return [noCarry, n + 1, n - 1, n + 2, n - 2, n + 10, n - 10, abs(a - b)]
        case .subtract:
            let smallerFromLarger = (a / 10 - b / 10) * 10 + abs(a % 10 - b % 10)
            return [smallerFromLarger, a + b, n + 1, n - 1, n + 2, n - 2, n + 10, n - 10]
        case .multiply:
            return [a + b, a * (b + 1), a * (b - 1), (a + 1) * b, (a - 1) * b, n + 1, n - 1]
        case .divide:
            return [a - b, n + 1, n - 1, n + 2, n - 2]
        case .power:
            let up = Fact(op: .power, a: a + 1, b: b).answer
            let down = a > 2 ? Fact(op: .power, a: a - 1, b: b).answer : a + b - 1
            return [a * b, up, n + a, a + b, down]
        }
    }

    /// The correct answer plus two different wrong answers, each placed randomly above or below
    /// the correct one so "pick the biggest" never works.
    func choices<G: RandomNumberGenerator>(using rng: inout G) -> [Choice] {
        var list = [Choice(value: answer, isCorrect: true)]
        var pool = wrongCandidates.filter { $0 >= 0 && $0 != answer }
        pool = pool.reduce(into: []) { unique, value in if !unique.contains(value) { unique.append(value) } }

        while list.count < 3 {
            let wantAbove = Bool.random(using: &rng)
            let side = pool.filter { wantAbove ? $0 > answer : $0 < answer }
            if let pick = (side.isEmpty ? pool : side).randomElement(using: &rng) {
                list.append(Choice(value: pick, isCorrect: false))
                pool.removeAll { $0 == pick }
            } else {
                // Candidate pool exhausted: step outward from the answer.
                var step = 3
                while list.contains(where: { $0.value == answer + step }) { step += 1 }
                list.append(Choice(value: answer + step, isCorrect: false))
            }
        }
        return list
    }

    private var factors: String {
        Array(repeating: "\(a)", count: b).joined(separator: " × ")
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
