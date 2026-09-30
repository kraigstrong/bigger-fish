import FishKit
import Foundation

// Math Reef curriculum for grades 1–5: worlds of small levels that unlock in order.
//
// Addition and subtraction follow the usual fluency progression: foundation facts (+1/+2, pairs that
// make 10, doubles), then derived facts (near doubles, crossing 10), then place value up to 2-digit
// carrying/borrowing. Multiplication and division go table by table, easy tables first and × 7 last
// (by then it's mostly facts turned around), then × tens and 2-digit × 1-digit. Division never has
// remainders, since every answer is one whole number. Each level holds about 8 questions;
// `Level.isCheckpoint` levels are skip tests that are always playable and pass every level before them.
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
    /// Whether rounds mix in review questions from earlier levels. Off where a level introduces new
    /// notation and the earlier levels are a different kind of question (Exponents: squares in a
    /// Cubes round read as mistakes, and its Mixed level already reviews both).
    var mixesInReview = true
    /// Shown on the world picker but not playable yet.
    var comingSoon: Bool { levels.isEmpty }

    /// Review questions mixed into a round of the level at `index`: none for checkpoints (they are
    /// the review) or in worlds that don't mix in review.
    func reviewCount(forLevelAt index: Int) -> Int {
        levels[index].isCheckpoint || !mixesInReview ? 0 : ReefTuning.reviewPerRound
    }

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
        World(id: "multiplication", title: "Multiplication", levels: multiplication),
        World(id: "division", title: "Division", levels: division),
        World(id: "exponents", title: "Exponents", levels: [squares, cubes, powersMixed], mixesInReview: false),
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
        checkpoint("add.review", "Review", sample(from: [addOnes, addTens, add2Digit, addCarryOnes, addCarry], count: 12, seed: 17)),
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

    // MARK: Multiplication

    static let mulX2 = Level(id: "mul.x2", title: "× 2", facts: table(2, seed: 40))
    static let mulX10 = Level(id: "mul.x10", title: "× 10", facts: table(10, seed: 41))
    static let mulX5 = Level(id: "mul.x5", title: "× 5", facts: table(5, seed: 42))
    static let mulX01 = Level(id: "mul.x01", title: "× 0 and × 1", facts: pairs(.multiply, [
        (7, 0), (0, 4), (9, 0), (0, 6), (6, 1), (1, 8), (5, 1), (1, 9),
    ]))
    static let mulX3 = Level(id: "mul.x3", title: "× 3", facts: table(3, seed: 43))
    static let mulX4 = Level(id: "mul.x4", title: "× 4", facts: table(4, seed: 44))
    static let mulSame = Level(id: "mul.same", title: "Same × same", facts: (3...10).map { Fact(op: .multiply, a: $0, b: $0) })
    static let mulX9 = Level(id: "mul.x9", title: "× 9", facts: table(9, seed: 45))
    static let mulX6 = Level(id: "mul.x6", title: "× 6", facts: table(6, seed: 46))
    static let mulX8 = Level(id: "mul.x8", title: "× 8", facts: table(8, seed: 47))
    static let mulX7 = Level(id: "mul.x7", title: "× 7", facts: table(7, seed: 48))
    static let mulX1112 = Level(id: "mul.x1112", title: "× 11 and × 12",
                                facts: table(11, by: [3, 5, 7, 9], seed: 49) + table(12, by: [3, 4, 6, 7, 8, 9], seed: 50))
    static let mulTens = Level(id: "mul.tens", title: "× tens", facts: generated(.multiply, seed: 51, a: 2...9, b: 20...90) { _, b in
        b % 10 == 0
    })
    static let mul2Digit = Level(id: "mul.2digit", title: "2-digit × 1", facts: generated(.multiply, seed: 52, a: 13...49, b: 2...4) { a, b in
        a % 10 != 0 && (a % 10) * b < 10 && (a / 10) * b < 10
    })
    static let mulCarry = Level(id: "mul.carry", title: "Carry in ×", facts: generated(.multiply, seed: 53, a: 13...59, b: 3...9) { a, b in
        a % 10 != 0 && (a % 10) * b >= 10
    })

    static let multiplication: [Level] = [
        mulX2, mulX10, mulX5, mulX01, mulX3, mulX4,
        checkpoint("mul.easy", "Easy tables", sample(from: [mulX2, mulX10, mulX5, mulX01, mulX3, mulX4], count: 12, seed: 54)),
        mulSame, mulX9, mulX6, mulX8, mulX7, mulX1112,
        checkpoint("mul.tables", "All the tables", sample(from: [mulSame, mulX9, mulX6, mulX8, mulX7, mulX1112], count: 12, seed: 55)),
        mulTens, mul2Digit, mulCarry,
        checkpoint("mul.review", "Review", sample(from: [mulTens, mul2Digit, mulCarry], count: 12, seed: 56)),
    ]

    // MARK: Division

    static let divX2 = Level(id: "div.x2", title: "÷ 2", facts: dividing(table(2)))
    static let divX10 = Level(id: "div.x10", title: "÷ 10", facts: dividing(table(10)))
    static let divX5 = Level(id: "div.x5", title: "÷ 5", facts: dividing(table(5)))
    static let divX3 = Level(id: "div.x3", title: "÷ 3", facts: dividing(table(3)))
    static let divX4 = Level(id: "div.x4", title: "÷ 4", facts: dividing(table(4)))
    static let divSame = Level(id: "div.same", title: "÷ same", facts: dividing(mulSame.facts))
    static let divX9 = Level(id: "div.x9", title: "÷ 9", facts: dividing(table(9)))
    static let divX6 = Level(id: "div.x6", title: "÷ 6", facts: dividing(table(6)))
    static let divX8 = Level(id: "div.x8", title: "÷ 8", facts: dividing(table(8)))
    static let divX7 = Level(id: "div.x7", title: "÷ 7", facts: dividing(table(7)))
    static let divX1112 = Level(id: "div.x1112", title: "÷ 11 and ÷ 12",
                                facts: dividing(table(11, by: [3, 5, 7, 9]) + table(12, by: [3, 4, 6, 7, 8, 9])))
    static let divTens = Level(id: "div.tens", title: "÷ into tens", facts: dividing(generated(.multiply, seed: 71, a: 2...9, b: 20...90) { _, b in
        b % 10 == 0
    }))
    static let div2Digit = Level(id: "div.2digit", title: "2-digit ÷ 1", facts: dividing(generated(.multiply, seed: 72, a: 2...4, b: 11...49) { a, b in
        b % 10 != 0 && (b / 10) * a < 10 && (b % 10) * a < 10
    }))
    static let divRegroup = Level(id: "div.regroup", title: "Split and ÷", facts: dividing(generated(.multiply, seed: 73, a: 3...6, b: 12...29) { a, b in
        b % 10 != 0 && (b * a) / 10 % a != 0 && b * a < 100
    }))

    static let division: [Level] = [
        divX2, divX10, divX5, divX3, divX4,
        checkpoint("div.easy", "Easy × and ÷", sample(from: [mulX2, mulX10, mulX5, mulX3, mulX4], count: 6, seed: 74)
            + sample(from: [divX2, divX10, divX5, divX3, divX4], count: 6, seed: 75)),
        divSame, divX9, divX6, divX8, divX7, divX1112,
        checkpoint("div.tables", "All ÷ facts", sample(from: [divSame, divX9, divX6, divX8, divX7, divX1112], count: 12, seed: 76)),
        divTens, div2Digit, divRegroup,
        checkpoint("div.mixed", "× and ÷ review", sample(from: [mulTens, mul2Digit, mulCarry], count: 6, seed: 77)
            + sample(from: [divTens, div2Digit, divRegroup], count: 6, seed: 78)),
    ]

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

    /// `n` times each of `others`, with `n` first. With a seed, some are turned around (7 × n) from
    /// that fixed seed so kids see both orders; without one, `dividing` can rely on `n` coming first.
    private static func table(_ n: Int, by others: [Int] = Array(2...9), seed: UInt64? = nil) -> [Fact] {
        var rng = SeededGenerator(seed: seed ?? 0)
        return others.map { other in
            seed != nil && Bool.random(using: &rng) ? Fact(op: .multiply, a: other, b: n) : Fact(op: .multiply, a: n, b: other)
        }
    }

    /// 56 ÷ 7 for each 7 × 8: divide the product by the first factor.
    private static func dividing(_ products: [Fact]) -> [Fact] {
        products.map { Fact(op: .divide, a: $0.answer, b: $0.a) }
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
