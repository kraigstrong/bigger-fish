import Foundation

/// Stable IDs belong to Bigger Fish; its save data is independent of Math Reef.
enum ArcadeWorld: String, CaseIterable, Identifiable, Codable {
    case shallowReef = "shallow-reef"
    case jellyBloom = "jelly-bloom"

    var id: String { rawValue }
    var title: String { self == .shallowReef ? "Shallow Reef" : "Jelly Bloom" }
    var subtitle: String {
        self == .shallowReef ? "Eat. Dodge. Grow." : "Bounce the tops. Dodge the tentacles."
    }
    var levels: [Level] { self == .shallowReef ? GameTuning.levels : GameTuning.bloomLevels }
    var levelTitles: [String] {
        self == .shallowReef
            ? ["Little Fish", "Finding Your Fins", "Bigger Company", "Feeding Frenzy", "King of the Reef"]
            : ["Bounce House", "Threading", "Bloom", "Night Bloom", "Gauntlet"]
    }
    func levelID(_ index: Int) -> String { "\(rawValue).\(index + 1)" }
}
