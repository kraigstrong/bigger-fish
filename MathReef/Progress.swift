import Foundation

// Passing a level: answer every question in a round and get at least 90% right
// (right answers out of tries). Passing unlocks the next level in the world. Checkpoint levels are
// skip tests: always playable, and passing one also passes every level before it.

enum PassRule {
    static let requiredAccuracy = 0.9

    static func passes(correct: Int, attempts: Int) -> Bool {
        attempts > 0 && Double(correct) / Double(attempts) >= requiredAccuracy
    }

    /// 0...100, rounded down so 89.9% never displays as a passing 90%.
    static func percent(correct: Int, attempts: Int) -> Int {
        attempts == 0 ? 0 : correct * 100 / attempts
    }
}

struct LevelRecord: Codable, Equatable {
    var passed = false
    /// Best round score, 0...100.
    var bestPercent = 0
    var hasPlayed = false
    /// Rounds passed (a checkpoint skip passes a level without playing it).
    var passCount = 0
    /// A round with no misses.
    var perfect = false

    /// ★ pass the level · ★★ pass it again · ★★★ a perfect round.
    var stars: Int {
        !passed ? 0 : perfect ? 3 : passCount >= 2 ? 2 : 1
    }
}

extension LevelRecord {
    /// Records saved before stars existed are missing the newer fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        passed = try container.decodeIfPresent(Bool.self, forKey: .passed) ?? false
        bestPercent = try container.decodeIfPresent(Int.self, forKey: .bestPercent) ?? 0
        hasPlayed = try container.decodeIfPresent(Bool.self, forKey: .hasPlayed) ?? false
        passCount = try container.decodeIfPresent(Int.self, forKey: .passCount) ?? 0
        perfect = try container.decodeIfPresent(Bool.self, forKey: .perfect) ?? false
    }
}

/// On-device progress for one learner. No accounts, nothing leaves the device.
final class ProgressStore {
    private let defaults: UserDefaults
    private let key = "mathReef.progress.v2"
    private var records: [String: LevelRecord]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: LevelRecord].self, from: data) {
            records = saved
        } else {
            records = [:]
        }
    }

    func record(for level: Level) -> LevelRecord {
        records[level.id] ?? LevelRecord()
    }

    /// Saves a finished round; returns true if it passed. A pass is never taken away. Passing a
    /// checkpoint also passes every earlier level in the world.
    @discardableResult
    func finishRound(_ index: Int, in world: World, correct: Int, attempts: Int) -> Bool {
        let level = world.levels[index]
        var record = record(for: level)
        let passed = PassRule.passes(correct: correct, attempts: attempts)
        record.passed = record.passed || passed
        record.bestPercent = max(record.bestPercent, PassRule.percent(correct: correct, attempts: attempts))
        record.hasPlayed = true
        if passed {
            record.passCount += 1
            if correct == attempts { record.perfect = true }
        }
        records[level.id] = record
        if passed && level.isCheckpoint {
            for earlier in world.levels.prefix(index) { records[earlier.id, default: LevelRecord()].passed = true }
        }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
        return passed
    }

    /// Open if it's the first level, the previous level is passed, or it's a checkpoint (skip test).
    func isUnlocked(_ index: Int, in world: World) -> Bool {
        guard world.levels.indices.contains(index) else { return false }
        return index == 0 || world.levels[index].isCheckpoint || record(for: world.levels[index - 1]).passed
    }

    /// Stars earned in `world`, out of three per level.
    func stars(in world: World) -> (earned: Int, total: Int) {
        (world.levels.reduce(0) { $0 + record(for: $1).stars }, world.levels.count * 3)
    }

    /// Silver for passing every level in the world, gold for three stars on every level.
    func crown(for world: World) -> Crown {
        guard !world.levels.isEmpty else { return .none }
        let records = world.levels.map { record(for: $0) }
        if records.allSatisfy({ $0.stars == 3 }) { return .gold }
        return records.allSatisfy(\.passed) ? .silver : .none
    }

    /// Unlocked only because it's a checkpoint: playing it is a skip test.
    func isSkipTest(_ index: Int, in world: World) -> Bool {
        world.levels[index].isCheckpoint && index > 0 && !record(for: world.levels[index - 1]).passed
    }
}
