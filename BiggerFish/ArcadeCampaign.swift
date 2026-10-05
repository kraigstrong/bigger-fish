import Foundation

/// Stable IDs belong to Bigger Fish; its save data is independent of Math Reef.
enum ArcadeWorld: String, CaseIterable, Identifiable, Codable {
    case shallowReef = "shallow-reef"
    case jellyBloom = "jelly-bloom"
    /// Planned-meeting levels for A/B testing against the campaign; see docs/meeting-planner.md.
    case reefLab = "reef-lab"

    /// The shipped campaign worlds, in map order.
    static let campaign: [ArcadeWorld] = [.shallowReef, .jellyBloom]
    /// Worlds on the map. Reef Lab is Debug-only for now.
    static var mapWorlds: [ArcadeWorld] {
        #if DEBUG
        return campaign + [.reefLab]
        #else
        return campaign
        #endif
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shallowReef: "Shallow Reef"
        case .jellyBloom: "Jelly Bloom"
        case .reefLab: "Reef Lab"
        }
    }
    var subtitle: String {
        switch self {
        case .shallowReef: "Eat. Dodge. Grow."
        case .jellyBloom: "Bounce the tops. Dodge the tentacles."
        case .reefLab: "Planned levels to compare with Shallow Reef."
        }
    }
    var levels: [Level] {
        switch self {
        case .shallowReef: GameTuning.levels
        case .jellyBloom: GameTuning.bloomLevels
        case .reefLab: GameTuning.reefLabLevels
        }
    }
    func level(_ index: Int) -> Level { levels[index] }
    /// Counting Reef Lab's levels doesn't load them.
    var levelCount: Int { self == .reefLab ? GameTuning.reefLabSpecs.count : levels.count }
    var levelTitles: [String] { (0..<levelCount).map { "Level \($0 + 1)" } }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
