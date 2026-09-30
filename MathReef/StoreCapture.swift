import CoreGraphics
import Foundation

#if DEBUG
/// App Store screenshots and the preview video, from debug builds only. Launching with
/// `-storeCapture <scene>` opens a staged scene with believable progress. The autopilot swims
/// during play, since simulator taps are unreliable in landscape. Screenshot scenes save the
/// frames the app draws, which, unlike simulator screenshots, have no Dynamic Island over them.
/// Progress, the unlock, and the sound setting live in their own UserDefaults suite (wiped at each
/// launch), so real progress, purchases, and analytics are untouched; analytics are off.
/// `scripts/store-capture.sh` drives it.
enum StoreCapture {
    enum Scene: String {
        /// The reef, with crowns and stars across the worlds.
        case home
        /// Multiplication's level path, partway through.
        case world
        /// A times-table round, answered right every time.
        case play
        /// A times-table round whose second question is answered wrong, for the explanation.
        case wrong
        /// An addition round, for the youngest players.
        case addition
        /// A squares round.
        case exponents
        /// The results panel with three stars and the gold crown.
        case crown
        /// The preview video: the reef, the level path, a round with one wrong answer, then the
        /// results and the silver crown for finishing the world.
        case video
    }

    static let scene: Scene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-storeCapture"), args.indices.contains(i + 1) else { return nil }
        return Scene(rawValue: args[i + 1])
    }()

    static let defaults: UserDefaults = {
        let name = "mathReef.storeCapture"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        // Screenshots show the whole reef, without padlocks.
        defaults.set(true, forKey: "mathReef.unlocked")
        return defaults
    }()

    /// Stars per level (0 = not played) for each world, by scene.
    static func stars(for world: World, in scene: Scene) -> [Int] {
        let count = world.levels.count
        let pattern = [3, 3, 2, 3, 3, 2, 3]
        func partway(_ passed: Int) -> [Int] {
            (0..<count).map { $0 < passed ? pattern[$0 % pattern.count] : 0 }
        }
        switch world.id {
        case "addition":
            return Array(repeating: 3, count: count)
        case "subtraction":
            return (0..<count).map { $0 % 4 == 2 ? 2 : 3 }
        case "multiplication":
            switch scene {
            case .video, .crown:
                // Every level but the one being played, so passing it finishes the world (and the
                // fish isn't already wearing the crown it's about to win).
                return (0..<count).map { $0 == videoLevel ? 0 : 3 }
            default:
                return partway(9)
            }
        case "division":
            return partway(3)
        default:
            return Array(repeating: 0, count: count)
        }
    }

    /// Where screenshot scenes save the frames they draw (cleared at each launch), for
    /// `scripts/store-capture.sh` to collect from the simulator.
    static let framesDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoreCapture", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        return dir
    }()

    /// The Dynamic Island's center, in points from the right edge of a landscape iPhone 17 Pro Max.
    static let islandInset: CGFloat = 32.5

    /// Multiplication's × 7, the level the video and the times-table scenes play.
    static let videoLevel = 11
}
#endif
