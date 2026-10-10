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
    /// Worlds an unlock screen has announced as open (the next world on a world's "conquered" screen).
    var announcedWorlds: Set<String>? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clearedLevels = (try? values.decodeIfPresent(Set<String>.self, forKey: .clearedLevels)) ?? []
        bestTimes = (try? values.decodeIfPresent([String: Double].self, forKey: .bestTimes)) ?? [:]
        hasSeenJellyLesson = (try? values.decodeIfPresent(Bool.self, forKey: .hasSeenJellyLesson)) ?? false
        seenUnlocks = try? values.decodeIfPresent(Set<String>.self, forKey: .seenUnlocks)
        announcedWorlds = try? values.decodeIfPresent(Set<String>.self, forKey: .announcedWorlds)
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
            // Not even a JSON object: keep the original, then start from whatever can be salvaged.
            defaults.set(data, forKey: Self.unreadableKey)
            save = Self.salvage(data)
        }
    }

    /// Cleared levels and best times from a save the decoder rejected, read as loosely as possible.
    private static func salvage(_ data: Data) -> ArcadeSave {
        var save = ArcadeSave()
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return save }
        save.clearedLevels = Set((object["clearedLevels"] as? [Any] ?? []).compactMap { $0 as? String })
        save.bestTimes = (object["bestTimes"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        save.hasSeenJellyLesson = object["hasSeenJellyLesson"] as? Bool ?? false
        return save
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

    /// The first world is always open; each one after opens when the one before has its tenth level beaten.
    /// A world you've already cleared a level in stays open, so players from before this rule keep theirs.
    func isWorldOpen(_ world: ArcadeWorld) -> Bool {
        guard let previous = world.previousWorld else { return true }
        return isCleared(previous, ArcadeWorld.mainLevelCount - 1) || (0..<world.levelCount).contains { isCleared(world, $0) }
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

    /// A world whose tenth level is beaten but whose unlock screen the player hasn't had, shown once at launch:
    /// players who beat it before that screen existed, and players who beat it before the world after it joined
    /// the campaign (`ArcadeWorld.lateArrivals`) and haven't been told or tried that world since. With several, the
    /// furthest along, since it announces the newest things.
    var unseenUnlock: ArcadeWorld? {
        ArcadeWorld.campaign.last { world in
            guard isCleared(world, ArcadeWorld.mainLevelCount - 1) else { return false }
            if !(save.seenUnlocks ?? []).contains(world.rawValue) { return true }
            guard let next = world.nextWorld, ArcadeWorld.lateArrivals.contains(next),
                  !(save.announcedWorlds ?? []).contains(next.rawValue) else { return false }
            let tried = clearedCounts(in: next)
            return tried.main + tried.deepEnd == 0
        }
    }

    /// Marks this world's unlock screen, and every earlier world's, as shown, and the worlds they announce.
    func sawUnlock(_ world: ArcadeWorld) {
        guard let index = ArcadeWorld.campaign.firstIndex(of: world) else { return }
        let shown = ArcadeWorld.campaign.prefix(index + 1)
        save.seenUnlocks = (save.seenUnlocks ?? []).union(shown.map(\.rawValue))
        save.announcedWorlds = (save.announcedWorlds ?? []).union(shown.compactMap { $0.nextWorld?.rawValue })
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
