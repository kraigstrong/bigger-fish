import Foundation

/// Stable IDs belong to Bigger Fish; its save data is independent of Math Reef.
enum ArcadeWorld: String, CaseIterable, Identifiable, Codable {
    case shallowReef = "shallow-reef"
    case jellyBloom = "jelly-bloom"
    case kelpForest = "kelp-forest"
    case midnightZone = "midnight-zone"

    /// The playable worlds, in map order. The map shows the rest as coming soon. Once a world ships, its ID and
    /// level numbers are permanent (they key saved progress).
    static let campaign: [ArcadeWorld] = [.shallowReef, .jellyBloom, .kelpForest, .midnightZone]
    /// Worlds still being prototyped: on the map in Xcode builds only, after the campaign and open from the start,
    /// so nothing unlocks them and the campaign's last world doesn't point to them. Midnight Zone started here.
    static let prototypes: [ArcadeWorld] = []
    /// Worlds that joined the campaign after players could already beat the world before them (whose "conquered"
    /// screen then said more worlds were coming). Those players are shown that screen once more, announcing it.
    /// Add a world here when it ships after the world before it.
    static let lateArrivals: Set<ArcadeWorld> = [.midnightZone]
    static var mapWorlds: [ArcadeWorld] {
        #if DEBUG
        campaign + prototypes
        #else
        campaign
        #endif
    }
    var hasJellies: Bool { self == .jellyBloom }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shallowReef: "Shallow Reef"
        case .jellyBloom: "Jelly Bloom"
        case .kelpForest: "Kelp Forest"
        case .midnightZone: "Midnight Zone"
        }
    }
    /// The world's one line, on the world map and its unlock screen. Each world names things one way
    /// everywhere: Jelly Bloom's jellyfish have tops and tentacles.
    var subtitle: String {
        switch self {
        case .shallowReef: "Eat. Dodge. Grow."
        case .jellyBloom: "Bounce the tops. Dodge the tentacles."
        case .kelpForest: "Dive into the kelp. Mind what's hiding."
        case .midnightZone: "Light the way. Mind the dark."
        }
    }
    /// Both worlds play planned levels (see docs/meeting-planner.md), shipped as data.
    var levels: [Level] {
        switch self {
        case .shallowReef: GameTuning.shallowReefLevels
        case .jellyBloom: GameTuning.jellyLabLevels
        case .kelpForest: GameTuning.kelpLevels
        case .midnightZone: GameTuning.midnightLevels
        }
    }
    func level(_ index: Int) -> Level { levels[index] }
    /// Shallow Reef and Jelly Bloom replaced original seeded campaigns, kept for the debug tuner; later worlds
    /// were planned from the start.
    var hasSeededOriginal: Bool { self == .shallowReef || self == .jellyBloom }
    /// The original seeded campaigns the planned levels replaced, kept for the debug tuner and the
    /// generator's tests.
    var seededLevels: [Level] {
        switch self {
        case .shallowReef: GameTuning.levels
        case .jellyBloom: GameTuning.bloomLevels
        case .kelpForest: GameTuning.kelpLevels
        case .midnightZone: GameTuning.midnightLevels
        }
    }
    /// Counting a world's levels doesn't load them.
    var levelCount: Int {
        switch self {
        case .shallowReef: GameTuning.reefLabSpecs.count
        case .jellyBloom: GameTuning.jellyLabSpecs.count
        case .kelpForest: GameTuning.kelpSpecs.count
        case .midnightZone: GameTuning.midnightSpecs.count
        }
    }
    var levelTitles: [String] { (0..<levelCount).map { "Level \($0 + 1)" } }

    /// Every world's main run is ten levels. Beating the tenth opens the levels after it, the world's Deep End:
    /// optional extra-hard levels for players who want more. Worlds themselves are all open from the start (with the
    /// unlock; see `ArcadeUnlock`).
    static let mainLevelCount = 10
    var deepEndCount: Int { max(0, levelCount - Self.mainLevelCount) }
    static func isDeepEnd(_ index: Int) -> Bool { index >= mainLevelCount }
    var nextWorld: ArcadeWorld? {
        Self.campaign.firstIndex(of: self).flatMap { Self.campaign.indices.contains($0 + 1) ? Self.campaign[$0 + 1] : nil }
    }
    /// What's new in the world, on the card before its first level until that's beaten (every other card is just the
    /// level and its pips). Shallow Reef has nothing new: the tutorial teaches the controls, eating and avoiding, and
    /// being the last fish swimming.
    var rules: [String] {
        switch self {
        case .shallowReef: []
        case .jellyBloom: ["Bounce the tops.", "Dodge the tentacles."]
        case .kelpForest: ["Kelp slows you down.", "Fish in the kelp hide their colors."]
        case .midnightZone: ["Your light shows the way.", "Fish lurk in the dark."]
        }
    }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
