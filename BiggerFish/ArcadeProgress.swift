import Combine
import Foundation

struct ArcadeSave: Codable {
    var clearedLevels: Set<String> = []
    var bestTimes: [String: Double] = [:]
    var hasSeenJellyLesson = false
}

final class ArcadeProgress: ObservableObject {
    @Published private(set) var save: ArcadeSave
    private let defaults: UserDefaults
    static let key = "biggerFish.campaign.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        save = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(ArcadeSave.self, from: $0) } ?? ArcadeSave()
    }

    func isCleared(_ world: ArcadeWorld, _ index: Int) -> Bool {
        save.clearedLevels.contains(world.levelID(index))
    }

    func isOpen(_ world: ArcadeWorld, _ index: Int) -> Bool {
        guard world.levels.indices.contains(index) else { return false }
        return index == 0 || isCleared(world, index) || isCleared(world, index - 1)
    }

    func nextLevel(in world: ArcadeWorld) -> Int {
        world.levels.indices.first { !isCleared(world, $0) } ?? 0
    }

    /// Completed campaigns stay focused on the final stop when returning to their map.
    func mapFocus(in world: ArcadeWorld) -> Int {
        world.levels.indices.first { !isCleared(world, $0) } ?? max(0, world.levels.count - 1)
    }

    func clear(_ world: ArcadeWorld, _ index: Int, seconds: Double) {
        guard world.levels.indices.contains(index), seconds.isFinite, seconds >= 0 else { return }
        let id = world.levelID(index)
        save.clearedLevels.insert(id)
        save.bestTimes[id] = min(save.bestTimes[id] ?? seconds, seconds)
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
