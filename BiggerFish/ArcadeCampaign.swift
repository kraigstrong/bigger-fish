import Foundation

/// Stable IDs belong to Bigger Fish; its save data is independent of Math Reef.
enum ArcadeWorld: String, CaseIterable, Identifiable, Codable {
    case shallowReef = "shallow-reef"
    case jellyBloom = "jelly-bloom"
    case kelpForest = "kelp-forest"

    /// The playable worlds, in map order. The map shows the rest as coming soon.
    static let campaign: [ArcadeWorld] = [.shallowReef, .jellyBloom, .kelpForest]
    static var mapWorlds: [ArcadeWorld] { campaign }
    var hasJellies: Bool { self == .jellyBloom }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shallowReef: "Shallow Reef"
        case .jellyBloom: "Jelly Bloom"
        case .kelpForest: "Kelp Forest"
        }
    }
    var subtitle: String {
        switch self {
        case .shallowReef: "Eat. Dodge. Grow."
        case .jellyBloom: "Bounce the tops. Dodge the tentacles."
        case .kelpForest: "Dive into the kelp. Mind what's hiding."
        }
    }
    /// Both worlds play planned levels (see docs/meeting-planner.md), shipped as data.
    var levels: [Level] {
        switch self {
        case .shallowReef: GameTuning.reefLabLevels
        case .jellyBloom: GameTuning.jellyLabLevels
        case .kelpForest: GameTuning.kelpLevels
        }
    }
    func level(_ index: Int) -> Level { levels[index] }
    /// The original seeded campaigns the planned levels replaced, kept for the debug tuner and the
    /// generator's tests.
    var seededLevels: [Level] {
        switch self {
        case .shallowReef: GameTuning.levels
        case .jellyBloom: GameTuning.bloomLevels
        case .kelpForest: GameTuning.kelpLevels
        }
    }
    /// Counting a world's levels doesn't load them.
    var levelCount: Int {
        switch self {
        case .shallowReef: GameTuning.reefLabSpecs.count
        case .jellyBloom: GameTuning.jellyLabSpecs.count
        case .kelpForest: GameTuning.kelpSpecs.count
        }
    }
    var levelTitles: [String] { (0..<levelCount).map { "Level \($0 + 1)" } }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
