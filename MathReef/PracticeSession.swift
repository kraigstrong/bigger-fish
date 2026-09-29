import Foundation

struct SessionResult: Equatable {
    var correctAnswers = 0
    var totalAttempts = 0

    var percent: Int { PassRule.percent(correct: correctAnswers, attempts: totalAttempts) }
    var passed: Bool { PassRule.passes(correct: correctAnswers, attempts: totalAttempts) }
}

/// One round of a level: every question in the level once, plus a few review questions from earlier
/// levels, and at least `minimumRound` questions. It ends once `targetCorrect` answers are right;
/// missed questions return after `requeueGap` others.
struct PracticeSession {
    let targetCorrect: Int
    let requeueGap: Int
    /// `upcoming[0]` is the current fact.
    private(set) var upcoming: [Fact]
    private(set) var result = SessionResult()
    private(set) var streak = 0
    private let pool: [Fact]
    private var fillerCursor = 0

    static let minimumRound = 10

    /// - Parameters:
    ///   - review: questions from earlier levels; `reviewCount` of them are mixed into the round.
    init<G: RandomNumberGenerator>(
        level: Level, review: [Fact] = [], reviewCount: Int = 0, requeueGap: Int = 2, using rng: inout G
    ) {
        let round = Self.roundOrder(level.facts, review: review, reviewCount: reviewCount, using: &rng)
        let pool = round.reduce(into: [Fact]()) { unique, fact in if !unique.contains(fact) { unique.append(fact) } }
        self.init(facts: round, pool: pool, targetCorrect: round.count, requeueGap: requeueGap)
    }

    init(facts: [Fact], pool: [Fact], targetCorrect: Int = 10, requeueGap: Int = 2) {
        self.targetCorrect = targetCorrect
        self.requeueGap = requeueGap
        self.pool = pool
        upcoming = facts
        while upcoming.count < targetCorrect && appendFiller(avoiding: nil) {}
    }

    var isComplete: Bool { result.correctAnswers >= targetCorrect }
    var current: Fact? { isComplete ? nil : upcoming.first }

    /// Records an attempt at the current fact and advances the queue.
    mutating func record(correct: Bool) {
        guard let fact = current else { return }
        result.totalAttempts += 1
        upcoming.removeFirst()
        if correct {
            result.correctAnswers += 1
            streak += 1
        } else {
            streak = 0
            requeue(fact)
        }
    }

    /// Every level question once, `reviewCount` distinct review questions, then extra level
    /// questions up to `minimumRound`, shuffled so the same question never appears twice in a row.
    static func roundOrder<G: RandomNumberGenerator>(
        _ facts: [Fact], review: [Fact], reviewCount: Int, using rng: inout G
    ) -> [Fact] {
        let extras = review.filter { !facts.contains($0) }.shuffled(using: &rng).prefix(reviewCount)
        var round = facts + extras
        if round.count < minimumRound {
            round += dealOrder(facts, count: minimumRound - round.count, using: &rng)
        }
        // Reshuffle until the same question never appears twice in a row (a repeat only exists when
        // a tiny level is padded up to `minimumRound`, so this settles in a few tries).
        var order = round.shuffled(using: &rng)
        for _ in 0..<50 where zip(order, order.dropFirst()).contains(where: { $0 == $1 }) {
            order.shuffle(using: &rng)
        }
        return order
    }

    /// Shuffled decks: no fact repeats until every fact has been used, never twice in a row.
    static func dealOrder<G: RandomNumberGenerator>(_ facts: [Fact], count: Int, using rng: inout G) -> [Fact] {
        var order: [Fact] = []
        while order.count < count && !facts.isEmpty {
            var deck = facts.shuffled(using: &rng)
            if deck.count > 1, deck.first == order.last {
                deck.swapAt(0, Int.random(in: 1..<deck.count, using: &rng))
            }
            order += deck
        }
        return Array(order.prefix(count))
    }

    private mutating func requeue(_ fact: Fact) {
        // Near the end of the queue, pad with other facts so a miss never repeats immediately.
        while upcoming.count < requeueGap && appendFiller(avoiding: fact) {}
        // Don't land next to another copy of the same fact.
        var index = requeueGap
        while index < upcoming.count && (upcoming[index] == fact || upcoming[index - 1] == fact) {
            index += 1
        }
        upcoming.insert(fact, at: min(index, upcoming.count))
    }

    /// Returns false if the pool has nothing usable (e.g. a single-fact pool).
    @discardableResult
    private mutating func appendFiller(avoiding fact: Fact?) -> Bool {
        for _ in 0..<pool.count {
            let candidate = pool[fillerCursor % pool.count]
            fillerCursor += 1
            if candidate != fact && candidate != upcoming.last {
                upcoming.append(candidate)
                return true
            }
        }
        return false
    }
}
