#if DEBUG
import SpriteKit
import UIKit

/// Gameplay footage for the trailer and App Store previews, from Xcode builds only; `scripts/bigger-fish-footage.sh`
/// drives it. Launched with `-arcadePlaytest <world>.<level> -storeFootage <bot policy>`, the app plays the level with
/// the diagnostics bot (`ArcadeSimulation`) and saves the frames it draws, with the interface hidden, to
/// Documents/StoreFootage/NNNNN.jpg, then `done.txt`. Frames are played and drawn one at a time rather than recorded
/// live, so the footage never stutters, and a run is deterministic, so the same launch gives the same footage.
/// Progress is staged in its own saved state, so real progress, purchases, and analytics are untouched.
///
/// Optional, in seconds of the run: `-storeFootageFrom` and `-storeFootageTo` (default the whole run, and
/// `tail` seconds after it ends). `-storeFootageEvery <n>` keeps every nth frame. `-storeFootageScale` below 1 shrinks
/// them, for a quick look at a whole run before recording the part that's wanted; above 1 (up to 3) draws them bigger
/// than the screen, sharp, as PNGs (NNNNN.png), for App Store art (the universal creative is 5244 x 2950: about 2.45
/// times).
enum StoreFootage {
    struct Request: Equatable {
        var policy: ArcadeSimulation.Policy
        var from: CGFloat = 0
        var to: CGFloat = StoreCapture.runLimit
        var every = 1
        var scale: CGFloat = 1
    }

    /// The footage this launch records, if any.
    static let request = request(in: ProcessInfo.processInfo.arguments)

    /// `-storeFootage <policy>` and its options in a launch's arguments. It needs a real level (`-arcadePlaytest`):
    /// without one no level opens, and nothing would ever be recorded.
    static func request(in arguments: [String]) -> Request? {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard ArcadePlaytest.level(in: arguments) != nil,
              let policy = value("-storeFootage").flatMap({ ArcadeSimulation.Policy(rawValue: $0) }) else { return nil }
        var request = Request(policy: policy)
        if let from = value("-storeFootageFrom").flatMap(Double.init), from >= 0 { request.from = CGFloat(from) }
        if let to = value("-storeFootageTo").flatMap(Double.init), CGFloat(to) > request.from { request.to = CGFloat(to) }
        if let every = value("-storeFootageEvery").flatMap(Int.init), every >= 1 { request.every = every }
        if let scale = value("-storeFootageScale").flatMap(Double.init), scale > 0, scale <= 3 { request.scale = CGFloat(scale) }
        return request
    }

    /// Seconds kept after the run ends, so a last bite, sting, or hook plays out.
    static let tail: CGFloat = 2

    // MARK: Staged progress

    /// The footage's own saved state, apart from real progress and never backed up to iCloud (`ArcadeProgress.backup`).
    static let suiteName = "biggerFish.storeFootage"

    /// Staged like a store capture's (`StoreCapture.stagedSave`): no tutorial or lesson over the level (nil when not
    /// recording).
    static let defaults: UserDefaults? = request.map { _ in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if let data = try? JSONEncoder().encode(StoreCapture.stagedSave(for: .eat)) { defaults.set(data, forKey: ArcadeProgress.key) }
        return defaults
    }

    // MARK: Recording

    /// Where frames are saved (cleared at each launch), for the script to collect from the simulator.
    static let framesDirectory: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoreFootage", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// At launch: tells the script when `-storeFootage` can't record, rather than leave it waiting for frames.
    static func begin() {
        guard request == nil, ProcessInfo.processInfo.arguments.contains("-storeFootage") else { return }
        fail("-storeFootage needs a level that exists (-arcadePlaytest <world>.<level>) and a bot: "
             + ArcadeSimulation.Policy.allCases.map(\.rawValue).joined(separator: ", "))
    }

    /// Records the level once its scene is on screen.
    @MainActor static func attach(_ scene: GameScene) {
        guard let request else { return }
        Task { @MainActor in
            while scene.view == nil { try? await Task.sleep(for: .milliseconds(50)) }
            // Past the loading screen's fade.
            try? await Task.sleep(for: .seconds(1))
            record(request, in: scene)
        }
    }

    /// Plays the level from the start with the bot, one display frame at a time, saving the frames the request wants.
    @MainActor private static func record(_ request: Request, in scene: GameScene) {
        // The bot plays between frames; nothing moves on its own meanwhile.
        scene.isPaused = true
        scene.debugCaptureRestart()
        let step = GameTuning.simulationStep
        let interval = StoreCapture.decisionInterval(request.policy)
        var nextDecision: CGFloat = 0
        var frame = 0, saved = 0
        var endedAt: Int?
        let started = Date()
        // Every bite, for picking moments: when, how big the meal was against your fish, and the biggest it had been.
        var biggest: [Int: CGFloat] = [:]
        var lastPrey: Int?
        var bites: [String] = []
        // And the other fish's bites on screen, for showing that they grow too: when, which fish, its size against
        // yours, and where it is (fractions of the frame from the top left).
        var theirLastPrey: [Int: Int] = [:]
        var theirBites: [String] = []
        while CGFloat(frame) * step < request.to {
            let view = scene.debugCaptureView
            if view.playing, view.time >= nextDecision {
                scene.debugHold(scene.debugBotHolds(request.policy))
                nextDecision = view.time + interval
            }
            scene.debugFrame(seconds: step)
            frame += 1
            let after = scene.debugCaptureView
            if endedAt == nil, !after.playing { endedAt = frame }
            for fish in after.fish where !fish.isEaten {
                biggest[fish.id] = max(biggest[fish.id] ?? 0, fish.radius / after.player.radius)
            }
            if let prey = after.player.prey, prey != lastPrey, let meal = after.fish.first(where: { $0.id == prey }) {
                bites.append(String(format: "%.2fs %.2f (at most %.2f)", CGFloat(frame) * step,
                                    meal.radius / after.player.radius, biggest[prey] ?? 0))
            }
            lastPrey = after.player.prey
            for fish in after.fish where !fish.isEaten {
                guard let prey = fish.prey, theirLastPrey[fish.id] != prey else { continue }
                theirLastPrey[fish.id] = prey
                guard after.shows(fish, margin: 0) else { continue }
                theirBites.append(String(format: "%.2fs #%d %.2f at %.2f, %.2f", CGFloat(frame) * step, fish.id,
                                         fish.radius / after.player.radius, fish.center.x / after.size.width,
                                         1 - fish.center.y / after.size.height))
            }
            if CGFloat(frame) * step >= request.from, frame % request.every == 0 {
                scene.debugHideInterface()
                guard let data = image(scene, scale: request.scale) else { return fail("couldn't draw frame \(frame)") }
                do {
                    let name = String(format: "%05d.%@", saved, request.scale > 1 ? "png" : "jpg")
                    try data.write(to: framesDirectory.appendingPathComponent(name))
                } catch {
                    return fail("couldn't save frame \(frame): \(error.localizedDescription)")
                }
                saved += 1
            }
            if let endedAt, CGFloat(frame - endedAt) * step >= tail { break }
        }
        let outcome = endedAt.map { "\(scene.debugCaptureView.won ? "won" : "lost") at \(String(format: "%.2f", CGFloat($0) * step))s" }
            ?? "still playing"
        let summary = "\(saved) frames, \(request.policy.rawValue) bot, \(outcome), in \(Int(Date().timeIntervalSince(started)))s"
        let report = ([summary, "bites (time, meal against you, the most it had been):"] + bites
                      + ["their bites on screen (time, fish, its size against you, where it is):"] + theirBites)
            .joined(separator: "\n")
        try? report.write(to: framesDirectory.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
        print("[StoreFootage] \(summary)")
    }

    /// The scene as drawn, interface hidden, at the screen's full resolution times `scale`: a JPEG, or a PNG above 1.
    @MainActor static func image(_ scene: SKScene, scale: CGFloat) -> Data? {
        guard let view = scene.view else { return nil }
        let crop = CGRect(x: -scene.anchorPoint.x * scene.size.width, y: -scene.anchorPoint.y * scene.size.height,
                          width: scene.size.width, height: scene.size.height)
        if scale > 1 {
            // A scene's texture is clipped to the scene, so every node is drawn `scale` times as big inside a holder,
            // just for this frame, and put back after.
            let children = scene.children
            let holder = SKNode()
            for node in children { node.removeFromParent(); holder.addChild(node) }
            holder.setScale(scale)
            scene.addChild(holder)
            let big = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
            let image = view.texture(from: holder, crop: big)?.cgImage()
            holder.removeFromParent()
            for node in children { node.removeFromParent(); scene.addChild(node) }
            return image.flatMap { UIImage(cgImage: $0).pngData() }
        }
        guard let image = view.texture(from: scene, crop: crop)?.cgImage() else { return nil }
        guard scale < 1 else { return UIImage(cgImage: image).jpegData(compressionQuality: 0.92) }
        let size = CGSize(width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Tells the script the footage couldn't be recorded, and why.
    private static func fail(_ reason: String) {
        print("[StoreFootage] failed: \(reason)")
        try? reason.write(to: framesDirectory.appendingPathComponent("failed.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
