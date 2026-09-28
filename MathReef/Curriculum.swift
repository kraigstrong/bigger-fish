import FishKit
import Foundation

// Math Reef curriculum: worlds, each with levels that unlock by mastery.
// Every level has a small fixed fact deck (8–16 facts) so "every fact correct twice" is reachable
// over a few short sessions. Two-digit decks are generated once from a fixed seed.

struct Level: Equatable {
    /// Stable identity for saved progress; never rename.
    let id: String
    let title: String
    /// Mixed levels have one key mistake per operation (e.g. carrying and borrowing).
    let keyMistakes: [MathOp: KeyMistake]
    /// Summary label for key-mistake answers.
    let keyMistakeName: String
    let facts: [Fact]
    /// Intro screen lines; a line starting with "=" is shown large as a worked example.
    let intro: [String]

    init(id: String, title: String, keyMistake: KeyMistake, facts: [Fact], intro: [String]) {
        self.init(id: id, title: title, keyMistakes: Dictionary(uniqueKeysWithValues: Set(facts.map(\.op)).map { ($0, keyMistake) }),
                  keyMistakeName: keyMistake.summaryName, facts: facts, intro: intro)
    }

    init(id: String, title: String, keyMistakes: [MathOp: KeyMistake], keyMistakeName: String, facts: [Fact], intro: [String]) {
        self.id = id
        self.title = title
        self.keyMistakes = keyMistakes
        self.keyMistakeName = keyMistakeName
        self.facts = facts
        self.intro = intro
    }

    func keyMistake(for fact: Fact) -> KeyMistake {
        keyMistakes[fact.op] ?? .offByOne
    }
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
            mixed("addsub.1", "Facts", addFacts, subFacts),
            mixed("addsub.2", "2-digit", addNoCarry, subNoBorrow),
            mixed("addsub.3", "Carry & borrow", addCarry, subBorrow, name: "Carry & borrow mistakes"),
        ]),
        World(id: "multiplication", title: "Multiplication", levels: [mulEasy, mulMedium, mulHard]),
        World(id: "division", title: "Division", levels: [divEasy, divMedium, divHard]),
        World(id: "muldiv", title: "Mixed × ÷", levels: [
            mixed("muldiv.1", "×÷ 2, 5, 10", mulEasy, divEasy, name: "Wrong-operation mistakes"),
            mixed("muldiv.2", "×÷ 3, 4, 6", mulMedium, divMedium, name: "Wrong-operation mistakes"),
            mixed("muldiv.3", "×÷ 7, 8, 9, 12", mulHard, divHard, name: "Wrong-operation mistakes"),
        ]),
        World(id: "fractions", title: "Fractions", levels: []),
        World(id: "exponents", title: "Exponents", levels: [squares, cubes, powersMixed]),
    ]

    // MARK: Addition

    static let addFacts = Level(
        id: "add.1", title: "Facts to 20", keyMistake: .offByOne,
        facts: pairs(.add, [(9, 2), (9, 4), (9, 7), (8, 3), (8, 5), (8, 7), (7, 4), (7, 6), (6, 5), (6, 8), (5, 7), (4, 9)]),
        intro: ["Add the two numbers.", "Tip: make a ten first.", "= 9 + 4 = 10 + 3 = 13"]
    )
    static let addNoCarry = Level(
        id: "add.2", title: "2-digit", keyMistake: .tensSlip,
        facts: twoDigit(.add, seed: 1) { a, b in a % 10 + b % 10 < 10 && a + b < 100 },
        intro: ["Add the tens, then the ones.", "= 32 + 25 = 50 + 7 = 57"]
    )
    static let addCarry = Level(
        id: "add.3", title: "Carrying", keyMistake: .forgotToCarry,
        facts: twoDigit(.add, seed: 2) { a, b in a % 10 + b % 10 >= 10 && a + b < 100 },
        intro: ["When the ones make 10 or more,", "carry the ten.", "= 27 + 15 = 30 + 12 = 42"]
    )

    // MARK: Subtraction

    static let subFacts = Level(
        id: "sub.1", title: "Facts to 20", keyMistake: .offByOne,
        facts: pairs(.subtract, [(11, 2), (13, 4), (16, 7), (11, 3), (13, 5), (15, 7), (11, 4), (13, 6), (11, 5), (14, 8), (12, 7), (13, 9)]),
        intro: ["Take away the second number.", "Tip: go back to ten first.", "= 13 − 4 = 10 − 1 = 9"]
    )
    static let subNoBorrow = Level(
        id: "sub.2", title: "2-digit", keyMistake: .tensSlip,
        facts: twoDigit(.subtract, seed: 3) { a, b in a % 10 >= b % 10 && a > b },
        intro: ["Take away the tens, then the ones.", "= 58 − 23 = 38 − 3 = 35"]
    )
    static let subBorrow = Level(
        id: "sub.3", title: "Borrowing", keyMistake: .smallerFromLarger,
        facts: twoDigit(.subtract, seed: 4) { a, b in a % 10 < b % 10 && a > b },
        intro: ["When the ones are too small,", "borrow a ten. Don't flip the digits!", "= 52 − 17 = 42 − 7 = 35"]
    )

    // MARK: Multiplication and division

    static let mulEasy = Level(
        id: "mul.1", title: "× 2, 5, 10", keyMistake: .addedInstead,
        facts: products([2, 5, 10], by: [3, 4, 7, 8]),
        intro: ["Multiply means groups of.", "= 5 × 4 = 5 + 5 + 5 + 5 = 20"]
    )
    static let mulMedium = Level(
        id: "mul.2", title: "× 3, 4, 6", keyMistake: .addedInstead,
        facts: products([3, 4, 6], by: [4, 6, 7, 8]),
        intro: ["Multiply means groups of.", "Don't add the numbers!", "= 6 × 4 = 24, not 10"]
    )
    static let mulHard = Level(
        id: "mul.3", title: "× 7, 8, 9, 12", keyMistake: .addedInstead,
        facts: pairs(.multiply, [(7, 6), (7, 8), (7, 9), (8, 6), (8, 8), (8, 9), (9, 6), (9, 7), (9, 9), (12, 6), (12, 7), (12, 8)]),
        intro: ["The tricky facts.", "= 7 × 8 = 56"]
    )
    static let divEasy = Level(id: "div.1", title: "÷ 2, 5, 10", keyMistake: .subtractedInstead,
                               facts: quotients(of: mulEasy), intro: divisionIntro)
    static let divMedium = Level(id: "div.2", title: "÷ 3, 4, 6", keyMistake: .subtractedInstead,
                                 facts: quotients(of: mulMedium), intro: divisionIntro)
    static let divHard = Level(id: "div.3", title: "÷ 7, 8, 9, 12", keyMistake: .subtractedInstead,
                               facts: quotients(of: mulHard), intro: divisionIntro)
    private static let divisionIntro = ["Division undoes multiplication.", "Think: what times this makes that?", "= 56 ÷ 8 = 7, because 7 × 8 = 56"]

    // MARK: Exponents

    static let squares = Level(
        id: "exp.1", title: "Squares", keyMistake: .baseTimesExponent,
        facts: (3...10).map { Fact(op: .power, a: $0, b: 2) },
        intro: ["The small number tells how many copies", "of the big number are multiplied.", "= 3² = 3 × 3 = 9"]
    )
    static let cubes = Level(
        id: "exp.2", title: "Cubes", keyMistake: .baseTimesExponent,
        facts: [2, 3, 4, 5, 10].map { Fact(op: .power, a: $0, b: 3) },
        intro: ["Same rule as squares:", "the small number tells how many copies", "of the big number are multiplied.", "= 2³ = 2 × 2 × 2 = 8"]
    )
    static let powersMixed = Level(
        id: "exp.3", title: "Mixed", keyMistake: .baseTimesExponent,
        facts: squares.facts + cubes.facts,
        intro: ["Squares and cubes together.", "Check the small number every time."]
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

    /// Half of each level's deck, interleaved, keeping each operation's key mistake.
    private static func mixed(_ id: String, _ title: String, _ x: Level, _ y: Level, name: String? = nil) -> Level {
        let half = zip(x.facts.prefix(6), y.facts.prefix(6)).flatMap { [$0, $1] }
        return Level(
            id: id, title: title,
            keyMistakes: x.keyMistakes.merging(y.keyMistakes) { first, _ in first },
            keyMistakeName: name ?? x.keyMistakeName,
            facts: half,
            intro: ["Watch the sign each time!"] + [x.intro.last, y.intro.last].compactMap { $0 }
        )
    }
}
