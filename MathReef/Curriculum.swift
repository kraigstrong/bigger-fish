import FishKit
import Foundation

// Math Reef curriculum for grades 1–5: worlds of small levels that unlock in order.
//
// Addition and subtraction follow the usual fluency progression: foundation facts (+1/+2, pairs that
// make 10, doubles), then derived facts (near doubles, crossing 10), then place value up to 2-digit
// carrying/borrowing. Each level holds about 8 questions; `Level.isCheckpoint` levels are skip tests
// that are always playable and pass every level before them.
//
// Level IDs are the keys for saved progress; never rename them. Generated decks use fixed seeds so
// they never change between launches.

struct Level: Equatable {
    /// Stable identity for saved progress; never rename.
    let id: String
    let title: String
    let facts: [Fact]
    /// Optional intro lines; a line starting with "=" is shown large as an example. Most levels have
    /// none: do the math, eat the answer.
    var intro: [String] = []
    /// Always playable; passing it also passes every earlier level in the world.
    var isCheckpoint = false
}

struct World: Equatable {
    let id: String
    let title: String
    let levels: [Level]
    /// Shown on the world picker but not playable yet.
    var comingSoon: Bool { levels.isEmpty }

    /// Every question from the levels before `index`, for review mixed into later rounds.
    func reviewPool(before index: Int) -> [Fact] {
        levels.prefix(index).flatMap(\.facts).reduce(into: []) { unique, fact in
            if !unique.contains(fact) { unique.append(fact) }
        }
    }
}

enum Curriculum {
    static let worlds: [World] = [
        World(id: "addition", title: "Addition", levels: addition),
        World(id: "subtraction", title: "Subtraction", levels: subtraction),
        World(id: "multiplication", title: "Multiplication", levels: [mulEasy, mulMedium, mulHard]),
        World(id: "division", title: "Division", levels: [
            divEasy, divMedium, divHard,
            checkpoint("div.mixed", "× and ÷", sample(from: [mulEasy, mulMedium, mulHard], count: 6, seed: 30)
                + sample(from: [divEasy, divMedium, divHard], count: 6, seed: 31)),
        ]),
        World(id: "fractions", title: "Fractions", levels: []),
        World(id: "exponents", title: "Exponents", levels: [squares, cubes, powersMixed]),
    ]

    // MARK: Addition

    static let addPlus12 = Level(id: "add.plus12", title: "+1 and +2", facts: pairs(.add, [
        (3, 1), (5, 1), (7, 1), (8, 1), (4, 2), (6, 2), (7, 2), (8, 2),
    ]))
    static let addMake10 = Level(id: "add.make10", title: "Make 10", facts: pairs(.add, [
        (1, 9), (2, 8), (3, 7), (4, 6), (6, 4), (7, 3), (8, 2), (9, 1),
    ]))
    static let addDoubles = Level(id: "add.doubles", title: "Doubles", facts: (3...10).map { Fact(op: .add, a: $0, b: $0) })
    static let addWithin10 = Level(id: "add.within10", title: "Up to 10", facts: pairs(.add, [
        (3, 4), (3, 5), (3, 6), (4, 5), (4, 3), (5, 3), (6, 3), (5, 4),
    ]))
    static let addNearDoubles = Level(id: "add.nearDoubles", title: "Near doubles", facts: pairs(.add, [
        (5, 6), (6, 7), (7, 8), (8, 9), (6, 5), (7, 6), (8, 7), (9, 8),
    ]))
    static let addCross10 = Level(id: "add.cross10", title: "Past 10", facts: pairs(.add, [
        (9, 2), (9, 4), (9, 6), (8, 3), (8, 4), (8, 5), (7, 4), (7, 5),
    ]))
    static let addOnes = Level(id: "add.ones", title: "Add ones", facts: generated(.add, seed: 11, a: 11...88, b: 1...9) { a, b in
        a % 10 != 0 && a % 10 + b < 10
    })
    static let addTens = Level(id: "add.tens", title: "Add tens", facts: generated(.add, seed: 12, a: 11...79, b: 10...50) { a, b in
        a % 10 != 0 && b % 10 == 0 && a + b < 100
    })
    static let add2Digit = Level(id: "add.2digit", title: "2-digit", facts: generated(.add, seed: 13, a: 11...89, b: 11...89) { a, b in
        a % 10 != 0 && b % 10 != 0 && a % 10 + b % 10 < 10 && a + b < 100
    })
    static let addCarryOnes = Level(id: "add.carryOnes", title: "Carry the 1", facts: generated(.add, seed: 14, a: 11...89, b: 2...9) { a, b in
        a % 10 != 0 && a % 10 + b >= 10 && a + b < 100
    })
    static let addCarry = Level(id: "add.carry", title: "Carrying", facts: generated(.add, seed: 15, a: 11...89, b: 11...89) { a, b in
        a % 10 != 0 && b % 10 != 0 && a % 10 + b % 10 >= 10 && a + b < 100
    })

    static let addition: [Level] = [
        addPlus12, addMake10, addDoubles, addWithin10, addNearDoubles, addCross10,
        checkpoint("add.review20", "All to 20", sample(from: [addPlus12, addMake10, addDoubles, addWithin10, addNearDoubles, addCross10], count: 12, seed: 16)),
        addOnes, addTens, add2Digit, addCarryOnes, addCarry,
        checkpoint("add.review", "Addition review", sample(from: [addOnes, addTens, add2Digit, addCarryOnes, addCarry], count: 12, seed: 17)),
    ]

    // MARK: Subtraction

    static let subMinus12 = Level(id: "sub.minus12", title: "−1 and −2", facts: pairs(.subtract, [
        (4, 1), (6, 1), (8, 1), (9, 1), (5, 2), (7, 2), (9, 2), (10, 2),
    ]))
    static let subFrom10 = Level(id: "sub.from10", title: "From 10", facts: pairs(.subtract, [
        (10, 3), (10, 4), (10, 6), (10, 7), (10, 8), (10, 9), (10, 5), (10, 1),
    ]))
    static let subDoubles = Level(id: "sub.doubles", title: "Doubles", facts: (3...10).map { Fact(op: .subtract, a: $0 * 2, b: $0) })
    static let subWithin10 = Level(id: "sub.within10", title: "Up to 10", facts: pairs(.subtract, [
        (7, 3), (8, 3), (9, 4), (8, 5), (9, 5), (7, 4), (9, 6), (8, 6),
    ]))
    static let subBack10 = Level(id: "sub.back10", title: "Back past 10", facts: pairs(.subtract, [
        (11, 2), (11, 3), (12, 3), (12, 5), (13, 4), (13, 5), (14, 6), (15, 7),
    ]))
    static let subWithin20 = Level(id: "sub.within20", title: "Up to 20", facts: pairs(.subtract, [
        (16, 7), (14, 8), (13, 9), (15, 8), (17, 9), (12, 7), (15, 6), (11, 4),
    ]))
    static let subOnes = Level(id: "sub.ones", title: "Take away ones", facts: generated(.subtract, seed: 21, a: 12...99, b: 1...9) { a, b in
        a % 10 != 0 && a % 10 >= b
    })
    static let subTens = Level(id: "sub.tens", title: "Take away tens", facts: generated(.subtract, seed: 22, a: 21...99, b: 10...80) { a, b in
        a % 10 != 0 && b % 10 == 0 && b < a
    })
    static let sub2Digit = Level(id: "sub.2digit", title: "2-digit", facts: generated(.subtract, seed: 23, a: 21...99, b: 11...89) { a, b in
        a % 10 != 0 && b % 10 != 0 && a % 10 >= b % 10 && a > b
    })
    static let subBorrowOnes = Level(id: "sub.borrowOnes", title: "Borrow a ten", facts: generated(.subtract, seed: 24, a: 21...99, b: 2...9) { a, b in
        a % 10 < b
    })
    static let subBorrow = Level(id: "sub.borrow", title: "Borrowing", facts: generated(.subtract, seed: 25, a: 21...99, b: 11...89) { a, b in
        a % 10 != 0 && b % 10 != 0 && a % 10 < b % 10 && a > b
    })

    static let subtraction: [Level] = [
        subMinus12, subFrom10, subDoubles, subWithin10, subBack10, subWithin20,
        checkpoint("sub.mixed20", "+ and − to 20",
                   sample(from: [addPlus12, addMake10, addDoubles, addWithin10, addNearDoubles, addCross10], count: 6, seed: 26)
                   + sample(from: [subMinus12, subFrom10, subDoubles, subWithin10, subBack10, subWithin20], count: 6, seed: 27)),
        subOnes, subTens, sub2Digit, subBorrowOnes, subBorrow,
        checkpoint("sub.mixed", "+ and − review",
                   sample(from: [addOnes, addTens, add2Digit, addCarryOnes, addCarry], count: 6, seed: 28)
                   + sample(from: [subOnes, subTens, sub2Digit, subBorrowOnes, subBorrow], count: 6, seed: 29)),
    ]

    // MARK: Multiplication and division

    static let mulEasy = Level(id: "mul.1", title: "× 2, 5, 10", facts: products([2, 5, 10], by: [3, 4, 7, 8]))
    static let mulMedium = Level(id: "mul.2", title: "× 3, 4, 6", facts: products([3, 4, 6], by: [4, 6, 7, 8]))
    static let mulHard = Level(id: "mul.3", title: "× 7, 8, 9, 12", facts: pairs(.multiply, [
        (7, 6), (7, 8), (7, 9), (8, 6), (8, 8), (8, 9), (9, 6), (9, 7), (9, 9), (12, 6), (12, 7), (12, 8),
    ]))
    static let divEasy = Level(id: "div.1", title: "÷ 2, 5, 10", facts: quotients(of: mulEasy))
    static let divMedium = Level(id: "div.2", title: "÷ 3, 4, 6", facts: quotients(of: mulMedium))
    static let divHard = Level(id: "div.3", title: "÷ 7, 8, 9, 12", facts: quotients(of: mulHard))

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
    static let powersMixed = Level(id: "exp.3", title: "Mixed", facts: squares.facts + cubes.facts)

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

    /// `count` distinct problems with `a` and `b` drawn from the ranges and matching `rule`, from a
    /// fixed seed.
    private static func generated(
        _ op: MathOp, seed: UInt64, count: Int = 8, a aRange: ClosedRange<Int>, b bRange: ClosedRange<Int>,
        where rule: (Int, Int) -> Bool
    ) -> [Fact] {
        var rng = SeededGenerator(seed: seed)
        var facts: [Fact] = []
        while facts.count < count {
            let a = Int.random(in: aRange, using: &rng), b = Int.random(in: bRange, using: &rng)
            let fact = Fact(op: op, a: a, b: b)
            if rule(a, b), !facts.contains(fact) { facts.append(fact) }
        }
        return facts
    }

    /// A fixed, seeded sample of distinct questions from `levels`.
    private static func sample(from levels: [Level], count: Int, seed: UInt64) -> [Fact] {
        var rng = SeededGenerator(seed: seed)
        let all = levels.flatMap(\.facts).reduce(into: [Fact]()) { unique, fact in
            if !unique.contains(fact) { unique.append(fact) }
        }
        return Array(all.shuffled(using: &rng).prefix(count))
    }

    private static func checkpoint(_ id: String, _ title: String, _ facts: [Fact]) -> Level {
        Level(id: id, title: title, facts: facts, isCheckpoint: true)
    }
}
