import Foundation

/// Stable IDs belong to Bigger Fish; its save data is independent of Math Reef.
enum ArcadeWorld: String, CaseIterable, Identifiable, Codable {
    case shallowReef = "shallow-reef"
    case jellyBloom = "jelly-bloom"
    case kelpForest = "kelp-forest"
    case midnightZone = "midnight-zone"
    case sunsetCove = "sunset-cove"
    case riptideReef = "riptide-reef"

    /// The playable worlds, in map order: 1.0's five. Sunset Cove plays fourth, before Midnight Zone (Kraig,
    /// 2026-10-12: "I think it should actually be the 4th world, with 5th being midnight zone"); saves key progress by
    /// world ID, so the order can change. Once a world ships, its ID and level numbers are permanent.
    static let campaign: [ArcadeWorld] = [.shallowReef, .jellyBloom, .kelpForest, .sunsetCove, .midnightZone]
    /// Worlds still being prototyped: on the map in Xcode builds only, after the campaign and open from the start,
    /// so nothing unlocks them and the campaign's last world doesn't point to them. Midnight Zone and Sunset Cove
    /// started here; Riptide Reef is being developed for 2.0.
    static let prototypes: [ArcadeWorld] = [.riptideReef]
    static var mapWorlds: [ArcadeWorld] {
        #if DEBUG
        mapWorlds(includingPrototypes: true)
        #else
        mapWorlds(includingPrototypes: false)
        #endif
    }
    /// The world map's worlds: the campaign, then (in Xcode builds) the prototypes.
    static func mapWorlds(includingPrototypes: Bool) -> [ArcadeWorld] {
        includingPrototypes ? campaign + prototypes : campaign
    }
    var hasJellies: Bool { self == .jellyBloom }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shallowReef: "Shallow Reef"
        case .jellyBloom: "Jelly Bloom"
        case .kelpForest: "Kelp Forest"
        case .midnightZone: "Midnight Zone"
        case .sunsetCove: "Sunset Cove"
        case .riptideReef: "Riptide Reef"
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
        case .sunsetCove: "Watch the boats. Leave the bait."
        case .riptideReef: "Ride the currents."
        }
    }
    /// Both worlds play planned levels (see docs/meeting-planner.md), shipped as data.
    var levels: [Level] {
        switch self {
        case .shallowReef: GameTuning.shallowReefLevels
        case .jellyBloom: GameTuning.jellyLabLevels
        case .kelpForest: GameTuning.kelpLevels
        case .midnightZone: GameTuning.midnightLevels
        case .sunsetCove: GameTuning.sunsetLevels
        case .riptideReef: GameTuning.riptideLevels
        }
    }
    func level(_ index: Int) -> Level { levels[index] }
    /// Counting a world's levels doesn't load them.
    var levelCount: Int {
        switch self {
        case .shallowReef: GameTuning.reefLabSpecs.count
        case .jellyBloom: GameTuning.jellyLabSpecs.count
        case .kelpForest: GameTuning.kelpSpecs.count
        case .midnightZone: GameTuning.midnightSpecs.count
        case .sunsetCove: GameTuning.sunsetLevelCount
        case .riptideReef: GameTuning.riptideLevelCount
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
    /// level and its pips). Shallow Reef's is how a level is won, in the words of Adventure's tutorial and its card on the
    /// home screen: the tutorial teaches it in its last beat, so a player who skips it hears it nowhere else (one wasn't
    /// sure how to get to the next level).
    var rules: [String] {
        switch self {
        case .shallowReef: [ArcadeHome.winRule + "."]
        case .jellyBloom: ["Bounce the tops.", "Dodge the tentacles."]
        case .kelpForest: ["Kelp slows you down.", "Fish in the kelp show only bubbles."]
        case .midnightZone: ["Your light shows the way.", "Fish lurk in the dark."]
        case .sunsetCove: ["Boats lower baited hooks.", "Don't take the bait."]
        case .riptideReef: ["Currents speed you up.", "Small fish get swept along."]
        }
    
    }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
