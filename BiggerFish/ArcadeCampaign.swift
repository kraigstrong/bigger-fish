import Foundation

/// Stable IDs belong to Bigger Fish; its save data is independent of Math Reef.
enum ArcadeWorld: String, CaseIterable, Identifiable, Codable {
    case shallowReef = "shallow-reef"
    case jellyBloom = "jelly-bloom"

    /// The playable worlds, in map order. The map shows three more as coming soon.
    static let campaign: [ArcadeWorld] = [.shallowReef, .jellyBloom]
    static var mapWorlds: [ArcadeWorld] { campaign }
    var hasJellies: Bool { self == .jellyBloom }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shallowReef: "Shallow Reef"
        case .jellyBloom: "Jelly Bloom"
        }
    }
    var subtitle: String {
        switch self {
        case .shallowReef: "Eat. Dodge. Grow."
        case .jellyBloom: "Bounce the tops. Dodge the tentacles."
        }
    }
    /// Both worlds play planned levels (see docs/meeting-planner.md), shipped as data.
    var levels: [Level] {
        switch self {
        case .shallowReef: GameTuning.reefLabLevels
        case .jellyBloom: GameTuning.jellyLabLevels
        }
    }
    func level(_ index: Int) -> Level { levels[index] }
    /// The original seeded campaigns the planned levels replaced, kept for the debug tuner and the
    /// generator's tests.
    var seededLevels: [Level] {
        switch self {
        case .shallowReef: GameTuning.levels
        case .jellyBloom: GameTuning.bloomLevels
        }
    }
    /// Counting a world's levels doesn't load them.
    var levelCount: Int {
        switch self {
        case .shallowReef: GameTuning.reefLabSpecs.count
        case .jellyBloom: GameTuning.jellyLabSpecs.count
        }
    }
    var levelTitles: [String] { (0..<levelCount).map { "Level \($0 + 1)" } }

    /// Every world's main run is ten levels. Beating the tenth opens the next world, and any levels after it
    /// are the world's Deep End: optional extra-hard levels for players who want more.
    static let mainLevelCount = 10
    var deepEndCount: Int { max(0, levelCount - Self.mainLevelCount) }
    static func isDeepEnd(_ index: Int) -> Bool { index >= mainLevelCount }
    var previousWorld: ArcadeWorld? { Self.campaign.firstIndex(of: self).flatMap { $0 > 0 ? Self.campaign[$0 - 1] : nil } }
    var nextWorld: ArcadeWorld? {
        Self.campaign.firstIndex(of: self).flatMap { Self.campaign.indices.contains($0 + 1) ? Self.campaign[$0 + 1] : nil }
    }
    /// What the unlock screen says about this world when it opens.
    var unlockLine: String {
        switch self {
        case .shallowReef: "Eat. Dodge. Grow."
        case .jellyBloom: "Bounce on the bells. Steer clear of the stingers."
        }
    }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
