import FishKit
import Foundation

// Math Reef curriculum: worlds, each with levels that unlock by mastery.
// Every level has a small fixed fact deck (5–16 facts). Two-digit decks are generated once from a
// fixed seed so they never change between launches.

struct Level: Equatable {
    /// Stable identity for saved progress; never rename.
    let id: String
    let title: String
    let facts: [Fact]
    /// Optional intro lines; a line starting with "=" is shown large as an example. Most levels have
    /// none: do the math, eat the answer.
    var intro: [String] = []

    /// One round asks every fact at least once, and at least `minimumRound` questions.
    static let minimumRound = 10
    var roundLength: Int { max(facts.count, Self.minimumRound) }
}

struct World: Equatable {
    let id: String
    let title: String
    let levels: [Level]
    /// Shown on the world picker but not playable yet.
    var comingSoon: Bool { levels.isEmpty }
}

enum Curriculum {
    static let worlds: [World] = [
        World(id: "addition", title: "Addition", levels: [addFacts, addNoCarry, addCarry]),
        World(id: "subtraction", title: "Subtraction", levels: [subFacts, subNoBorrow, subBorrow]),
        World(id: "addsub", title: "Mixed + −", levels: [
            mixed("addsub.1", "Up to 20", addFacts, subFacts),
            mixed("addsub.2", "2-digit", addNoCarry, subNoBorrow),
            mixed("addsub.3", "Carry & borrow", addCarry, subBorrow),
        ]),
        World(id: "multiplication", title: "Multiplication", levels: [mulEasy, mulMedium, mulHard]),
        World(id: "division", title: "Division", levels: [divEasy, divMedium, divHard]),
        World(id: "muldiv", title: "Mixed × ÷", levels: [
            mixed("muldiv.1", "×÷ 2, 5, 10", mulEasy, divEasy),
            mixed("muldiv.2", "×÷ 3, 4, 6", mulMedium, divMedium),
            mixed("muldiv.3", "×÷ 7, 8, 9, 12", mulHard, divHard),
        ]),
        World(id: "fractions", title: "Fractions", levels: []),
        World(id: "exponents", title: "Exponents", levels: [squares, cubes, powersMixed]),
    ]

    // MARK: Addition

    static let addFacts = Level(
        id: "add.1", title: "Up to 20",
        facts: pairs(.add, [(9, 2), (9, 4), (9, 7), (8, 3), (8, 5), (8, 7), (7, 4), (7, 6), (6, 5), (6, 8), (5, 7), (4, 9)])
    )
    static let addNoCarry = Level(
        id: "add.2", title: "2-digit",
        facts: twoDigit(.add, seed: 1) { a, b in a % 10 + b % 10 < 10 && a + b < 100 }
    )
    static let addCarry = Level(
        id: "add.3", title: "Carrying",
        facts: twoDigit(.add, seed: 2) { a, b in a % 10 + b % 10 >= 10 && a + b < 100 }
    )

    // MARK: Subtraction

    static let subFacts = Level(
        id: "sub.1", title: "Up to 20",
        facts: pairs(.subtract, [(11, 2), (13, 4), (16, 7), (11, 3), (13, 5), (15, 7), (11, 4), (13, 6), (11, 5), (14, 8), (12, 7), (13, 9)])
    )
    static let subNoBorrow = Level(
        id: "sub.2", title: "2-digit",
        facts: twoDigit(.subtract, seed: 3) { a, b in a % 10 >= b % 10 && a > b }
    )
    static let subBorrow = Level(
        id: "sub.3", title: "Borrowing",
        facts: twoDigit(.subtract, seed: 4) { a, b in a % 10 < b % 10 && a > b }
    )

    // MARK: Multiplication and division

    static let mulEasy = Level(
        id: "mul.1", title: "× 2, 5, 10",
        facts: products([2, 5, 10], by: [3, 4, 7, 8])
    )
    static let mulMedium = Level(
        id: "mul.2", title: "× 3, 4, 6",
        facts: products([3, 4, 6], by: [4, 6, 7, 8])
    )
    static let mulHard = Level(
        id: "mul.3", title: "× 7, 8, 9, 12",
        facts: pairs(.multiply, [(7, 6), (7, 8), (7, 9), (8, 6), (8, 8), (8, 9), (9, 6), (9, 7), (9, 9), (12, 6), (12, 7), (12, 8)])
    )
    static let divEasy = Level(id: "div.1", title: "÷ 2, 5, 10",
                               facts: quotients(of: mulEasy))
    static let divMedium = Level(id: "div.2", title: "÷ 3, 4, 6",
                                 facts: quotients(of: mulMedium))
    static let divHard = Level(id: "div.3", title: "÷ 7, 8, 9, 12",
                               facts: quotients(of: mulHard))

    // MARK: Exponents

    static let squares = Level(
        id: "exp.1", title: "Squares",
        facts: (3...10).map { Fact(op: .power, a: $0, b: 2) },
        intro: ["The small number tells how many copies", "of the big number are multiplied.", "= 3² = 3 × 3 = 9"]
    )
    static let cubes = Level(
        id: "exp.2", title: "Cubes",
        facts: [2, 3, 4, 5, 10].map { Fact(op: .power, a: $0, b: 3) },
        intro: ["The small number tells how many copies", "of the big number are multiplied.", "= 2³ = 2 × 2 × 2 = 8"]
    )
    static let powersMixed = Level(
        id: "exp.3", title: "Mixed",
        facts: squares.facts + cubes.facts
    )

    // MARK: Helpers

    private static func pairs(_ op: MathOp, _ list: [(Int, Int)]) -> [Fact] {
        list.map { Fact(op: op, a: $0.0, b: $0.1) }
    }

    private static func products(_ factors: [Int], by others: [Int]) -> [Fact] {
        factors.flatMap { f in others.map { Fact(op: .multiply, a: $0, b: f) } }
    }

    /// 56 ÷ 8 for each 7 × 8.
    private static func quotients(of level: Level) -> [Fact] {
        level.facts.map { Fact(op: .divide, a: $0.answer, b: $0.b) }
    }

    /// 12 distinct two-digit problems (both numbers 11–89) matching `rule`, from a fixed seed.
    private static func twoDigit(_ op: MathOp, seed: UInt64, count: Int = 12, where rule: (Int, Int) -> Bool) -> [Fact] {
        var rng = SeededGenerator(seed: seed)
        var facts: [Fact] = []
        while facts.count < count {
            let a = Int.random(in: 11...89, using: &rng), b = Int.random(in: 11...89, using: &rng)
            let fact = Fact(op: op, a: a, b: b)
            if a % 10 != 0, b % 10 != 0, rule(a, b), !facts.contains(fact) { facts.append(fact) }
        }
        return facts
    }

    /// Half of each level's deck, interleaved.
    private static func mixed(_ id: String, _ title: String, _ x: Level, _ y: Level) -> Level {
        Level(id: id, title: title, facts: zip(x.facts.prefix(6), y.facts.prefix(6)).flatMap { [$0, $1] })
    }
}
