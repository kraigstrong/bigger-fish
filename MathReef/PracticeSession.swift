import Foundation

struct SessionResult: Equatable {
    var correctAnswers = 0
    var totalAttempts = 0

    var percent: Int { PassRule.percent(correct: correctAnswers, attempts: totalAttempts) }
    var passed: Bool { PassRule.passes(correct: correctAnswers, attempts: totalAttempts) }
}

/// One round of a level: every fact at least once (and at least `Level.minimumRound` questions).
/// It ends once `targetCorrect` answers are right; missed facts return after `requeueGap` others.
struct PracticeSession {
    let targetCorrect: Int
    let requeueGap: Int
    /// `upcoming[0]` is the current fact.
    private(set) var upcoming: [Fact]
    private(set) var result = SessionResult()
    private(set) var streak = 0
    private let pool: [Fact]
    private var fillerCursor = 0

    init<G: RandomNumberGenerator>(level: Level, requeueGap: Int = 2, using rng: inout G) {
        self.init(
            facts: Self.dealOrder(level.facts, count: level.roundLength, using: &rng),
            pool: level.facts, targetCorrect: level.roundLength, requeueGap: requeueGap
        )
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
