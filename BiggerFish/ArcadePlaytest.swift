#if DEBUG
import Foundation

/// Launch a specific level without changing real campaign progress:
/// -arcadePlaytest jelly-bloom.4 (world ID + one-based level number).
enum ArcadePlaytest {
    static var mapSelection: ArcadeWorld? {
        if let capture = StoreCapture.moment { return capture.map }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadeMap"), args.indices.contains(flag + 1) else { return nil }
        return ArcadeWorld(rawValue: args[flag + 1])
    }

    /// An App Store capture (`StoreCapture`) plays its moment's level, unless this picks another.
    static var selection: (world: ArcadeWorld, index: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadePlaytest"), args.indices.contains(flag + 1) else {
            return StoreCapture.moment?.level
        }
        let parts = args[flag + 1].split(separator: ".")
        guard parts.count == 2, let world = ArcadeWorld(rawValue: String(parts[0])),
              let number = Int(parts[1]), (0..<world.levelCount).contains(number - 1) else { return nil }
        return (world, number - 1)
    }

    /// Another variation of a Shallow Reef level as a practice run: -arcadePlanner 10.3 (Shallow Reef's level
    /// number, as played, and variation). Use -arcadePlaytest shallow-reef.10 for the level itself.
    static var planner: (spec: MeetingSpec, variation: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadePlanner"), args.indices.contains(flag + 1) else { return nil }
        let parts = args[flag + 1].split(separator: ".")
        guard let number = parts.first.flatMap({ Int($0) }), GameTuning.shallowReefOrder.indices.contains(number - 1) else { return nil }
        // The tuner's range; a negative or huge variation would overflow the planner's seed.
        let variation = parts.count > 1 ? Int(parts[1]) : 0
        guard let variation, (0...99).contains(variation) else { return nil }
        return (GameTuning.reefLabSpecs[GameTuning.shallowReefOrder[number - 1]], variation)
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

    /// Play with or without the unlock, ignoring StoreKit: -arcadeUnlocked YES (or NO).
    static var unlockOverride: Bool? {
        // App Store captures show every world open, with no price anywhere.
        if StoreCapture.moment != nil { return true }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadeUnlocked"), args.indices.contains(flag + 1) else { return nil }
        return args[flag + 1] == "YES"
    }

    /// A playtest's own saved state, apart from real progress and never backed up to iCloud (`ArcadeProgress.backup`).
    static let suiteName = "biggerFish.playtest"

    static var defaults: UserDefaults {
        StoreCapture.defaults ?? screenDefaults ?? (selection == nil ? .standard : UserDefaults(suiteName: suiteName)!)
    }

    /// A screen to open at launch, to check its layout at a device's size (an iPad, a small phone):
    /// -arcadeScreen worlds, settings, unlock, conquered, credits, tutorial, or pause (with -arcadePlaytest for the
    /// level to pause). Add -arcadeMap <world ID> for a level map, -arcadeUnlocked YES or NO for either side of the
    /// unlock ("conquered" shows the unlock's offer without it), or -arcadePlaytest with -arcadeResult for a result card.
    enum Screen: String { case worlds, settings, unlock, conquered, credits, tutorial, pause }

    static let screen: Screen? = {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-arcadeScreen"), args.indices.contains(flag + 1) else { return nil }
        return Screen(rawValue: args[flag + 1])
    }()

    /// A screen check's own saved state, wiped and staged at launch as the App Store captures stage theirs: Shallow
    /// Reef conquered with a best time on each level, the tutorial and every "conquered" screen seen. Never backed up
    /// to iCloud (`ArcadeProgress.backup`).
    static let screenSuiteName = "biggerFish.screen"

    private static let screenDefaults: UserDefaults? = screen.map { _ in
        let defaults = UserDefaults(suiteName: screenSuiteName)!
        defaults.removePersistentDomain(forName: screenSuiteName)
        if let data = try? JSONEncoder().encode(StoreCapture.stagedSave(for: .conquered)) {
            defaults.set(data, forKey: ArcadeProgress.key)
        }
        return defaults
    }
}
#endif
