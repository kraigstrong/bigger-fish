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
        case .reefLab: "Planned meetings to compare."
        }
    }
    var levels: [Level] {
        switch self {
        case .shallowReef: GameTuning.levels
        case .jellyBloom: GameTuning.bloomLevels
        case .reefLab: GameTuning.reefLabLevels
        }
    }
    /// Counting levels never plans Reef Lab's, which takes a moment in Debug builds.
    var levelCount: Int { self == .reefLab ? GameTuning.plannerPresets.count : levels.count }
    var levelTitles: [String] {
        self == .reefLab ? GameTuning.plannerPresets.map(\.name) : (0..<levelCount).map { "Level \($0 + 1)" }
    }
    /// Every Reef Lab level is open, so each can be compared without clearing the one before.
    var opensEveryLevel: Bool { self == .reefLab }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
