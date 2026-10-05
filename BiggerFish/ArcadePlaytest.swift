#if DEBUG
import Foundation

/// Launch a specific level without changing real campaign progress:
/// -arcadePlaytest jelly-bloom.4 (world ID + one-based level number).
enum ArcadePlaytest {
    static var mapSelection: ArcadeWorld? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadeMap"), args.indices.contains(flag + 1) else { return nil }
        return ArcadeWorld(rawValue: args[flag + 1])
    }

    static var selection: (world: ArcadeWorld, index: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadePlaytest"), args.indices.contains(flag + 1) else { return nil }
        let parts = args[flag + 1].split(separator: ".")
        guard parts.count == 2, let world = ArcadeWorld(rawValue: String(parts[0])),
              let number = Int(parts[1]), (0..<world.levelCount).contains(number - 1) else { return nil }
        return (world, number - 1)
    }

    /// Another variation of a Reef Lab level as a practice run: -arcadePlanner 10.3 (level, variation).
    /// Use -arcadePlaytest reef-lab.10 for the level itself.
    static var planner: (spec: MeetingSpec, variation: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadePlanner"), args.indices.contains(flag + 1) else { return nil }
        let parts = args[flag + 1].split(separator: ".")
        guard let number = parts.first.flatMap({ Int($0) }), GameTuning.reefLabSpecs.indices.contains(number - 1) else { return nil }
        // The tuner's range; a negative or huge variation would overflow the planner's seed.
        let variation = parts.count > 1 ? Int(parts[1]) : 0
        guard let variation, (0...99).contains(variation) else { return nil }
        return (GameTuning.reefLabSpecs[number - 1], variation)
    }

    /// A visual-only result preview; no clear or purchase is recorded.
    static var resultPreview: Bool? {
        let args = ProcessInfo.processInfo.arguments
        guard selection != nil, let flag = args.firstIndex(of: "-arcadeResult"),
              args.indices.contains(flag + 1) else { return nil }
        switch args[flag + 1] {
        case "passed": return true
        case "failed": return false
        default: return nil
        }
    }

    static var defaults: UserDefaults {
        selection == nil ? .standard : UserDefaults(suiteName: "biggerFish.playtest")!
    }
}
#endif
