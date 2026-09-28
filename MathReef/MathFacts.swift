import Foundation

// Math Reef facts: prompts, answers, worked solutions, and misconception-based wrong answers.
// Pure logic; the scene lives in PracticeScene.swift.

enum MathOp: String, Codable {
    case add, subtract, multiply, divide, power
}

enum AnswerKind: String, Codable, Equatable {
    case correct
    /// The level's key misconception (e.g. base × exponent, forgot to carry).
    case keyMistake
    case otherMistake
}

struct Choice: Equatable {
    let value: Int
    let kind: AnswerKind
}

/// The one mistake a level is trying to eliminate. Mastery requires it to be gone.
enum KeyMistake: String, Codable {
    case offByOne, tensSlip, forgotToCarry, smallerFromLarger, addedInstead, subtractedInstead, baseTimesExponent

    var summaryName: String {
        switch self {
        case .offByOne: "Off-by-one mistakes"
        case .tensSlip: "Off-by-ten mistakes"
        case .forgotToCarry: "Forgot-to-carry mistakes"
        case .smallerFromLarger: "Smaller-from-larger mistakes"
        case .addedInstead: "Added-instead mistakes"
        case .subtractedInstead: "Subtracted-instead mistakes"
        case .baseTimesExponent: "Base × exponent mistakes"
        }
    }

    /// The wrong answer this mistake produces for `fact`, if it differs from the correct one.
    func value<G: RandomNumberGenerator>(for fact: Fact, using rng: inout G) -> Int? {
        let a = fact.a, b = fact.b
        let value: Int
        switch self {
        case .offByOne: value = fact.answer + (Bool.random(using: &rng) ? 1 : -1)
        case .tensSlip: value = fact.answer + (Bool.random(using: &rng) || fact.answer < 10 ? 10 : -10)
        case .forgotToCarry: value = (a / 10 + b / 10) * 10 + (a % 10 + b % 10) % 10
        case .smallerFromLarger: value = (a / 10 - b / 10) * 10 + abs(a % 10 - b % 10)
        case .addedInstead: value = a + b
        case .subtractedInstead: value = a - b
        case .baseTimesExponent: value = a * b
        }
        return value >= 0 && value != fact.answer ? value : nil
    }
}

struct Fact: Hashable {
    let op: MathOp
    let a: Int
    let b: Int

    /// Stable identity for saved progress.
    var id: String { "\(op.rawValue):\(a):\(b)" }

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

    /// Shown on a correct answer: "27 + 15 = 42", "4² = 4 × 4 = 16"
    var solution: String {
        op == .power ? "\(prompt) = \(factors) = \(answer)" : "\(prompt) = \(answer)"
    }

    /// The same shape for every wrong answer: "Not 32", an optional hint, then the worked answer.
    func wrongAnswerFeedback(chosen: Int) -> [String] {
        ["Not \(chosen)"] + workedSteps
    }

    /// A short strategy for getting the answer, ending with the answer itself.
    var workedSteps: [String] {
        let ta = a / 10 * 10, oa = a % 10, tb = b / 10 * 10, ob = b % 10
        switch op {
        case .power:
            return ["\(Self.superscript(b)) means \(Self.countWord(b)) \(a)s:", "\(factors) = \(answer)"]
        case .add where a >= 10 || b >= 10:
            return ["\(ta) + \(tb) = \(ta + tb) and \(oa) + \(ob) = \(oa + ob)", "\(ta + tb) + \(oa + ob) = \(answer)"]
        case .add where a + b > 10:
            // Make a ten: 9 + 4 → 9 + 1 = 10, then 10 + 3.
            let big = max(a, b), small = min(a, b), toTen = 10 - big
            return ["Make a ten: \(big) + \(toTen) = 10", "10 + \(small - toTen) = \(answer)"]
        case .subtract where b >= 10 && ob > 0:
            return ["\(a) − \(tb) = \(a - tb)", "\(a - tb) − \(ob) = \(answer)"]
        case .subtract where a > 10 && b < 10 && b > a - 10:
            // Back to ten: 13 − 4 → 13 − 3 = 10, then 10 − 1.
            return ["Back to ten: \(a) − \(a - 10) = 10", "10 − \(b - (a - 10)) = \(answer)"]
        case .multiply:
            return ["\(a) groups of \(b)", "\(a) × \(b) = \(answer)"]
        case .divide:
            return ["\(answer) × \(b) = \(a)", "so \(a) ÷ \(b) = \(answer)"]
        default:
            return [solution]
        }
    }

    /// Plausible wrong answers on both sides of the correct one, so "pick the biggest" never works.
    var otherCandidates: [Int] {
        let n = answer
        switch op {
        case .add: return [n + 10, n - 10, n + 1, n - 1, n + 2, n - 2, abs(a - b)]
        case .subtract: return [a + b, n + 10, n - 10, n + 1, n - 1, n + 2, n - 2]
        case .multiply: return [a * (b + 1), a * (b - 1), (a + 1) * b, (a - 1) * b, n + 1, n - 1]
        case .divide: return [n + 1, n - 1, n + 2, n - 2, a + b]
        case .power:
            let up = Fact(op: .power, a: a + 1, b: b).answer
            let down = a > 2 ? Fact(op: .power, a: a - 1, b: b).answer : a + b - 1
            return [up, n + a, a + b, down]
        }
    }

    /// Three unique choices: the correct answer, the key mistake whenever it differs, and a
    /// distractor placed randomly above or below the correct answer.
    func choices<G: RandomNumberGenerator>(keyMistake: KeyMistake, using rng: inout G) -> [Choice] {
        var list = [Choice(value: answer, kind: .correct)]
        if let key = keyMistake.value(for: self, using: &rng) {
            list.append(Choice(value: key, kind: .keyMistake))
        }
        var pool = otherCandidates.filter { candidate in
            candidate >= 0 && !list.contains { $0.value == candidate }
        }
        pool = pool.reduce(into: []) { unique, value in if !unique.contains(value) { unique.append(value) } }

        while list.count < 3 {
            let wantAbove = Bool.random(using: &rng)
            let side = pool.filter { wantAbove ? $0 > answer : $0 < answer }
            if let pick = (side.isEmpty ? pool : side).randomElement(using: &rng) {
                list.append(Choice(value: pick, kind: .otherMistake))
                pool.removeAll { $0 == pick }
            } else {
                // Candidate pool exhausted: step outward from the answer.
                var step = 3
                while list.contains(where: { $0.value == answer + step }) { step += 1 }
                list.append(Choice(value: answer + step, kind: .otherMistake))
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
