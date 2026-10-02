#if DEBUG
import Foundation

/// Launch a specific level without changing real campaign progress:
/// -arcadePlaytest jelly-bloom.4 (world ID + one-based level number).
enum ArcadePlaytest {
    static var selection: (world: ArcadeWorld, index: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadePlaytest"), args.indices.contains(flag + 1) else { return nil }
        let parts = args[flag + 1].split(separator: ".")
        guard parts.count == 2, let world = ArcadeWorld(rawValue: String(parts[0])),
              let number = Int(parts[1]), world.levels.indices.contains(number - 1) else { return nil }
        return (world, number - 1)
    }

    static var defaults: UserDefaults {
        selection == nil ? .standard : UserDefaults(suiteName: "biggerFish.playtest")!
    }
}
#endif
