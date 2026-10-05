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

    /// A planned test level: -arcadePlanner hard, or -arcadePlanner hard.3 for another variation.
    static var planner: (spec: MeetingSpec, variation: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadePlanner"), args.indices.contains(flag + 1) else { return nil }
        let parts = args[flag + 1].split(separator: ".")
        guard let name = parts.first,
              let spec = GameTuning.plannerPresets.first(where: { $0.name.lowercased() == name.lowercased() }) else { return nil }
        return (spec, parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
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
