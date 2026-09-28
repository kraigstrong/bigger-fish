import Foundation

// Mastery: a level is mastered when, across all sessions,
//   1. every fact has been answered correctly at least `correctPerFact` times,
//   2. at least `requiredInWindow` of the last `window` answers were correct, and
//   3. none of the last `cleanWindow` answers was the level's key mistake.
// Once mastered, a level stays mastered and unlocks the next level in its world.

enum Mastery {
    static let correctPerFact = 2
    static let window = 20
    static let requiredInWindow = 18
    static let cleanWindow = 10

    static func isMet(_ progress: LevelProgress, level: Level) -> Bool {
        let covered = level.facts.allSatisfy { progress.correctCounts[$0.id, default: 0] >= correctPerFact }
        let recent = progress.recent.suffix(window)
        let accurate = recent.count >= window && recent.filter { $0 == .correct }.count >= requiredInWindow
        let clean = !progress.recent.suffix(cleanWindow).contains(.keyMistake)
        return covered && accurate && clean
    }

    /// Facts answered correctly enough (each counts up to `correctPerFact`), out of the total needed.
    static func coverage(_ progress: LevelProgress, level: Level) -> (done: Int, total: Int) {
        let done = level.facts.reduce(0) { $0 + min(progress.correctCounts[$1.id, default: 0], correctPerFact) }
        return (done, level.facts.count * correctPerFact)
    }

    /// Correct answers among the last `window` (and how many answers that window holds so far).
    static func recentAccuracy(_ progress: LevelProgress) -> (correct: Int, of: Int) {
        let recent = progress.recent.suffix(window)
        return (recent.filter { $0 == .correct }.count, recent.count)
    }
}

struct LevelProgress: Codable, Equatable {
    var correctCounts: [String: Int] = [:]
    /// Oldest first, capped at `Mastery.window`.
    var recent: [AnswerKind] = []
    var mastered = false

    /// Records one answer; returns true if this answer just achieved mastery.
    @discardableResult
    mutating func record(_ kind: AnswerKind, factID: String, level: Level) -> Bool {
        if kind == .correct { correctCounts[factID, default: 0] += 1 }
        recent.append(kind)
        if recent.count > Mastery.window { recent.removeFirst(recent.count - Mastery.window) }
        guard !mastered, Mastery.isMet(self, level: level) else { return false }
        mastered = true
        return true
    }
}

/// On-device progress for one learner. No accounts, nothing leaves the device.
final class ProgressStore {
    private let defaults: UserDefaults
    private let key = "mathReef.progress.v1"
    private var levels: [String: LevelProgress]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: LevelProgress].self, from: data) {
            levels = saved
        } else {
            levels = [:]
        }
    }

    func progress(for level: Level) -> LevelProgress {
        levels[level.id] ?? LevelProgress()
    }

    /// Records an answer and saves immediately, so quitting mid-session keeps progress.
    @discardableResult
    func record(_ kind: AnswerKind, fact: Fact, level: Level) -> Bool {
        var progress = progress(for: level)
        let justMastered = progress.record(kind, factID: fact.id, level: level)
        levels[level.id] = progress
        save()
        return justMastered
    }

    /// The first level of a world is always open; each later level needs the previous one mastered.
    func isUnlocked(_ index: Int, in world: World) -> Bool {
        index == 0 || (world.levels.indices.contains(index - 1) && progress(for: world.levels[index - 1]).mastered)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(levels) { defaults.set(data, forKey: key) }
    }
}
