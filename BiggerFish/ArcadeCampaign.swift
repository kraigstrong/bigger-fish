import Foundation

/// Stable IDs belong to Bigger Fish; its save data is independent of Math Reef.
enum ArcadeWorld: String, CaseIterable, Identifiable, Codable {
    case shallowReef = "shallow-reef"
    case jellyBloom = "jelly-bloom"
    /// Planned-meeting levels, shown as Shallow Reef 2, to A/B test against Shallow Reef; see
    /// docs/meeting-planner.md. Its ID stays "reef-lab" for saved progress and analytics.
    case reefLab = "reef-lab"
    /// Planned levels with drifting jellyfish, shown as Jelly Bloom 2. Debug-only for now.
    case jellyLab = "jelly-lab"

    /// The seeded campaign worlds, which the debug tuner edits.
    static let campaign: [ArcadeWorld] = [.shallowReef, .jellyBloom]
    /// Worlds on the map: TestFlight compares Shallow Reef with Shallow Reef 2. Jelly Bloom 2 is Debug-only for now.
    static var mapWorlds: [ArcadeWorld] {
        #if DEBUG
        return campaign + [.reefLab, .jellyLab]
        #else
        return campaign + [.reefLab]
        #endif
    }
    /// Jellyfish worlds share Jelly Bloom's look, lesson, and seeds.
    var hasJellies: Bool { self == .jellyBloom || self == .jellyLab }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shallowReef: "Shallow Reef"
        case .jellyBloom: "Jelly Bloom"
        case .reefLab: "Shallow Reef 2"
        case .jellyLab: "Jelly Bloom 2"
        }
    }
    var subtitle: String {
        switch self {
        case .shallowReef: "Eat. Dodge. Grow."
        case .jellyBloom: "Bounce the tops. Dodge the tentacles."
        case .reefLab: "Eat. Dodge. Grow."
        case .jellyLab: "Bounce the tops. Dodge the tentacles."
        }
    }
    var levels: [Level] {
        switch self {
        case .shallowReef: GameTuning.levels
        case .jellyBloom: GameTuning.bloomLevels
        case .reefLab: GameTuning.reefLabLevels
        case .jellyLab: GameTuning.jellyLabLevels
        }
    }
    func level(_ index: Int) -> Level { levels[index] }
    /// Counting a planned world's levels doesn't load them.
    var levelCount: Int {
        switch self {
        case .reefLab: GameTuning.reefLabSpecs.count
        case .jellyLab: GameTuning.jellyLabSpecs.count
        default: levels.count
        }
    }
    var levelTitles: [String] { (0..<levelCount).map { "Level \($0 + 1)" } }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
