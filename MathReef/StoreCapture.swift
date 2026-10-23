import CoreGraphics
import Foundation
import SpriteKit
import UIKit

#if DEBUG
/// App Store screenshots and the preview video, from debug builds only. Launching with
/// `-storeCapture <scene>` opens a staged scene with believable progress. The autopilot swims
/// during play, since simulator taps are unreliable in landscape. Screenshots and the video are
/// the frames the app draws (`image(of:)`), which, unlike the simulator's screenshots and
/// recordings, have no Dynamic Island over them, at the screen's full resolution, an iPad's too.
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

    /// Multiplication's × 7, the level the video and the times-table scenes play.
    static let videoLevel = 11

    /// A number after `flag` in the launch arguments, if it's above zero.
    private static func number(after flag: String) -> Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1),
              let value = Double(args[i + 1]), value > 0 else { return nil }
        return value
    }

    /// How long the video scene records, in seconds of play: `-storeCaptureSeconds`, or long enough for the reef, the
    /// path, the card, a full round, and the results and crown.
    static let videoSeconds: TimeInterval = number(after: "-storeCaptureSeconds") ?? 86

    /// Frame by frame, each frame plays exactly `frameStep` of the game, its actions too, however long the simulator
    /// took over the last one (`PracticeScene.update`). Saving a full-size frame takes it far longer than a frame, and
    /// in real time the game would jump ahead in big steps after each (the autopilot's taps then show as a jerky bob)
    /// or fall behind a burst of screenshots. Always for the video; for screenshots, `-storeCaptureFrameByFrame`.
    static let isFrameByFrame = scene == .video || ProcessInfo.processInfo.arguments.contains("-storeCaptureFrameByFrame")
    static let frameStep: TimeInterval = 1.0 / 60
    private static let launched = Date().timeIntervalSince1970
    /// Seconds of play, which the scene keeps up to date each frame: the clock that moves the fish.
    static var playClock: TimeInterval = 0
    /// A frame was saved since the scene last looked: the next frame comes late.
    static var savedFrame = false

    /// Seconds since 1970 on the game's clock: when the app launched, plus the seconds of play since.
    static func now() -> TimeInterval {
        launched + playClock
    }

    // MARK: Frames

    /// The scene as the screen shows it, at the screen's full resolution. A scene's texture comes out at the scene's
    /// own size, which on an iPad is smaller than the screen's (`ReefScreen.scale`), so there every node is drawn that
    /// much bigger inside a holder, just for this frame, and put back after (as Bigger Fish's `StoreFootage.image`).
    @MainActor static func image(of scene: SKScene) -> CGImage? {
        guard let view = scene.view else { return nil }
        savedFrame = true
        let scale = ReefScreen.scale(for: view.window?.bounds.size ?? view.bounds.size)
        let crop = CGRect(x: -scene.anchorPoint.x * scene.size.width, y: -scene.anchorPoint.y * scene.size.height,
                          width: scene.size.width, height: scene.size.height)
        guard scale > 1 else { return view.texture(from: scene, crop: crop)?.cgImage() }
        let children = scene.children
        let holder = SKNode()
        for node in children { node.removeFromParent(); holder.addChild(node) }
        holder.setScale(scale)
        scene.addChild(holder)
        let big = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
        let image = view.texture(from: holder, crop: big)?.cgImage()
        holder.removeFromParent()
        for node in children { node.removeFromParent(); scene.addChild(node) }
        return image
    }

    /// The preview video's frames: the app saves what it draws while the video scene plays, 30 a second of play, as
    /// StoreCapture/video/NNNNN.jpg, with the moment each was drawn in times.txt (on the game's clock, `now`, one a
    /// line, as the audio cues are logged), then done.txt. The script times the video and lines up the soundtrack by
    /// them.
    @MainActor final class VideoRecorder {
        static let framesPerSecond: TimeInterval = 30
        private let until: TimeInterval
        private var next: TimeInterval = 0
        private var count = 0
        private var times: [String] = []
        private let directory = framesDirectory.appendingPathComponent("video", isDirectory: true)
        /// JPEGs are encoded off the main thread, a few at once, so the game keeps its pace.
        private let encoder: OperationQueue = {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 4
            queue.qualityOfService = .userInitiated
            return queue
        }()

        init(seconds: TimeInterval) {
            until = now() + seconds
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        /// Whether a frame is due at `now`, on the game's clock.
        func isDue(at now: TimeInterval) -> Bool {
            now < until && now >= next - 0.001
        }

        /// Saves the scene if a frame is due. False once the video is long enough (and finished).
        func capture(_ scene: SKScene) -> Bool {
            let now = StoreCapture.now()
            guard now < until else {
                finish()
                return false
            }
            guard isDue(at: now), let image = image(of: scene) else { return true }
            // On a 30-a-second grid, started again from now when a slow frame falls behind it.
            next = (now - next < 0.5 / Self.framesPerSecond ? next : now) + 1 / Self.framesPerSecond
            let url = directory.appendingPathComponent(String(format: "%05d.jpg", count))
            count += 1
            times.append(String(format: "%.4f", now))
            encoder.addOperation {
                try? UIImage(cgImage: image).jpegData(compressionQuality: 0.9)?.write(to: url)
            }
            return true
        }

        private func finish() {
            encoder.waitUntilAllOperationsAreFinished()
            try? (times.joined(separator: "\n") + "\n").write(
                to: directory.appendingPathComponent("times.txt"), atomically: true, encoding: .utf8)
            try? "\(count) frames".write(to: directory.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
            print("[StoreCapture] video: \(count) frames")
        }
    }
}
#endif
