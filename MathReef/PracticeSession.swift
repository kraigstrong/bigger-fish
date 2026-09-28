import Foundation

struct SessionResult: Equatable {
    var correctAnswers = 0
    var totalAttempts = 0
    var keyMistakes = 0
    var otherMistakes = 0
    var elapsedTime: TimeInterval = 0

    /// 0...1
    var accuracy: Double {
        totalAttempts == 0 ? 0 : Double(correctAnswers) / Double(totalAttempts)
    }
}

/// One short play session in a level: ends after `targetCorrect` correct answers.
/// Missed facts return after at least `requeueGap` other facts.
struct PracticeSession {
    let targetCorrect: Int
    let requeueGap: Int
    /// `upcoming[0]` is the current fact.
    private(set) var upcoming: [Fact]
    private(set) var result = SessionResult()
    private(set) var streak = 0
    private let pool: [Fact]
    private var fillerCursor = 0

    /// Deals from shuffled decks, with `priority` facts (not yet mastered) first in the first deck.
    init<G: RandomNumberGenerator>(
        level: Level, targetCorrect: Int = 10, requeueGap: Int = 2, priority: Set<String> = [], using rng: inout G
    ) {
        self.init(
            facts: Self.dealOrder(level.facts, count: targetCorrect, priority: priority, using: &rng),
            pool: level.facts, targetCorrect: targetCorrect, requeueGap: requeueGap
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
    mutating func record(_ kind: AnswerKind) {
        guard let fact = current else { return }
        result.totalAttempts += 1
        upcoming.removeFirst()
        switch kind {
        case .correct:
            result.correctAnswers += 1
            streak += 1
        case .keyMistake:
            result.keyMistakes += 1
            streak = 0
            requeue(fact)
        case .otherMistake:
            result.otherMistakes += 1
            streak = 0
            requeue(fact)
        }
    }

    /// Shuffled decks: no fact repeats until every fact has been used, never twice in a row.
    /// `priority` facts lead the first deck so unmastered facts come up sooner.
    static func dealOrder<G: RandomNumberGenerator>(
        _ facts: [Fact], count: Int, priority: Set<String> = [], using rng: inout G
    ) -> [Fact] {
        var order: [Fact] = []
        var first = true
        while order.count < count && !facts.isEmpty {
            var deck = facts.shuffled(using: &rng)
            if first {
                deck = deck.filter { priority.contains($0.id) } + deck.filter { !priority.contains($0.id) }
                first = false
            }
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
