import Combine
import Foundation

/// A player's progress. It must always load: every field falls back to its default when a save doesn't have
/// it (a save from before the field existed), and fields a save has that this version doesn't know are
/// ignored (a save from a later version). Never rename these keys or the level IDs stored in them.
struct ArcadeSave: Codable {
    var clearedLevels: Set<String> = []
    var bestTimes: [String: Double] = [:]
    var hasSeenJellyLesson = false
    /// Worlds whose "conquered" unlock screen has been shown.
    var seenUnlocks: Set<String>? = nil
    /// The first-launch tutorial has been shown (finished, skipped, or left).
    var hasSeenTutorial: Bool? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clearedLevels = (try? values.decodeIfPresent(Set<String>.self, forKey: .clearedLevels)) ?? []
        bestTimes = (try? values.decodeIfPresent([String: Double].self, forKey: .bestTimes)) ?? [:]
        hasSeenJellyLesson = (try? values.decodeIfPresent(Bool.self, forKey: .hasSeenJellyLesson)) ?? false
        seenUnlocks = try? values.decodeIfPresent(Set<String>.self, forKey: .seenUnlocks)
        hasSeenTutorial = try? values.decodeIfPresent(Bool.self, forKey: .hasSeenTutorial)
    }
}

final class ArcadeProgress: ObservableObject {
    @Published private(set) var save: ArcadeSave
    private let defaults: UserDefaults
    static let key = "biggerFish.campaign.v1"

    /// Where a save that couldn't be read at all is kept, so the next save can't destroy it.
    static let unreadableKey = key + ".unreadable"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { save = ArcadeSave(); return }
        if let loaded = try? JSONDecoder().decode(ArcadeSave.self, from: data) {
            save = loaded
        } else {
            // Not even a JSON object (any object loads, field by field): keep the original, and start afresh.
            defaults.set(data, forKey: Self.unreadableKey)
            save = ArcadeSave()
        }
    }

    func isCleared(_ world: ArcadeWorld, _ index: Int) -> Bool {
        save.clearedLevels.contains(world.levelID(index))
    }

    func isOpen(_ world: ArcadeWorld, _ index: Int) -> Bool {
        guard (0..<world.levelCount).contains(index) else { return false }
        #if DEBUG
        // A world still being prototyped (on the map, not yet in the campaign) has every level open for playtesting.
        if !ArcadeWorld.campaign.contains(world) { return true }
        #endif
        return index == 0 || isCleared(world, index) || isCleared(world, index - 1)
    }

    /// How many of the world's main levels, and of its Deep End, are cleared.
    func clearedCounts(in world: ArcadeWorld) -> (main: Int, deepEnd: Int) {
        let cleared = (0..<world.levelCount).filter { isCleared(world, $0) }
        let deep = cleared.filter(ArcadeWorld.isDeepEnd).count
        return (cleared.count - deep, deep)
    }

    func nextLevel(in world: ArcadeWorld) -> Int {
        (0..<world.levelCount).first { !isCleared(world, $0) } ?? 0
    }

    /// Completed campaigns stay focused on the final stop when returning to their map.
    /// The level map's marker: the level you just left when coming back from one, otherwise the first
    /// level not yet cleared (or the last level once the world is complete).
    func mapFocus(in world: ArcadeWorld, returningFrom left: Int? = nil) -> Int {
        if let left, (0..<world.levelCount).contains(left) { return left }
        return (0..<world.levelCount).first { !isCleared(world, $0) } ?? max(0, world.levelCount - 1)
    }

    func clear(_ world: ArcadeWorld, _ index: Int, seconds: Double) {
        guard (0..<world.levelCount).contains(index), seconds.isFinite, seconds >= 0 else { return }
        let id = world.levelID(index)
        save.clearedLevels.insert(id)
        save.bestTimes[id] = min(save.bestTimes[id] ?? seconds, seconds)
        persist()
    }

    /// Debug A/B testing: a new player starts the world from level 1.
    func reset(_ world: ArcadeWorld) {
        let prefix = world.rawValue + "."
        save.clearedLevels = save.clearedLevels.filter { !$0.hasPrefix(prefix) }
        save.bestTimes = save.bestTimes.filter { !$0.key.hasPrefix(prefix) }
        persist()
    }

    /// A world whose tenth level is beaten but whose "conquered" screen (opening its Deep End) the player hasn't had,
    /// shown at launch: players who beat it before that screen existed. With several, the furthest along first.
    var unseenUnlock: ArcadeWorld? {
        ArcadeWorld.campaign.last { world in
            isCleared(world, ArcadeWorld.mainLevelCount - 1) && !(save.seenUnlocks ?? []).contains(world.rawValue)
        }
    }

    /// Marks this world's "conquered" screen as shown. Each world's opens its own Deep End, and worlds can be played
    /// in any order, so it says nothing about other worlds'.
    func sawUnlock(_ world: ArcadeWorld) {
        save.seenUnlocks = (save.seenUnlocks ?? []).union([world.rawValue])
        persist()
    }

    /// Only a new player sees the tutorial: someone updating with levels already cleared knows the game.
    var needsTutorial: Bool { save.hasSeenTutorial != true && save.clearedLevels.isEmpty }

    func sawTutorial() {
        save.hasSeenTutorial = true
        persist()
    }

    func sawJellyLesson() {
        save.hasSeenJellyLesson = true
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(save) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
