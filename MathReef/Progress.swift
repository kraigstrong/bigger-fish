import Foundation

// Stars for a round (right answers out of tries): 60% ★ · 80% ★★ · 100% ★★★.
// Two stars passes a level and unlocks the next one. Checkpoint levels are skip tests: always
// playable, and passing one also passes every level before it.

enum PassRule {
    /// Minimum percent for 1, 2, and 3 stars.
    static let starThresholds = [60, 80, 100]
    static let starsToPass = 2

    /// 0...100, rounded down so 79.9% never displays (or counts) as 80%.
    static func percent(correct: Int, attempts: Int) -> Int {
        attempts == 0 ? 0 : correct * 100 / attempts
    }

    static func stars(percent: Int) -> Int {
        starThresholds.filter { percent >= $0 }.count
    }

    static func stars(correct: Int, attempts: Int) -> Int {
        stars(percent: percent(correct: correct, attempts: attempts))
    }

    static func passes(correct: Int, attempts: Int) -> Bool {
        stars(correct: correct, attempts: attempts) >= starsToPass
    }
}

struct LevelRecord: Codable, Equatable {
    var passed = false
    /// Best round score, 0...100.
    var bestPercent = 0
    var hasPlayed = false

    /// From the best round; a level passed by a skip test counts as two stars.
    var stars: Int {
        max(PassRule.stars(percent: bestPercent), passed ? PassRule.starsToPass : 0)
    }
}

extension LevelRecord {
    /// Tolerates missing fields so older saved records keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        passed = try container.decodeIfPresent(Bool.self, forKey: .passed) ?? false
        bestPercent = try container.decodeIfPresent(Int.self, forKey: .bestPercent) ?? 0
        hasPlayed = try container.decodeIfPresent(Bool.self, forKey: .hasPlayed) ?? false
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
