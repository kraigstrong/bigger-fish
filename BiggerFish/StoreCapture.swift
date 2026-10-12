#if DEBUG
import FishKit
import SpriteKit
import UIKit

/// App Store screenshots, from Xcode builds only; `scripts/bigger-fish-store-capture.sh` drives it. Launched with
/// `-storeCapture <moment>`, the app plays the moment's level with the diagnostics bot (`ArcadeSimulation`) until the
/// moment comes, or opens the moment's screen, and saves the frame it draws, with the interface hidden, to
/// Documents/StoreCapture/<moment>.png. (A simulator screenshot would have the Dynamic Island drawn over it.)
/// Levels play exactly as shipped: a run is deterministic, so the capture plays it through once with each of the
/// bot's policies to find the best frame, then again to stop there. Progress is staged in its own saved state, so
/// real progress, purchases, and analytics are untouched.
enum StoreCapture {
    /// The screenshots, in the order the listing tells the game (kraigstrong/bigger-fish#142).
    enum Moment: String, CaseIterable {
        /// Eating a smaller fish, mid-bite, with more around.
        case eat
        /// A bigger fish sliding past, just missing you.
        case dodge
        /// A fish that kept eating: ahead of you, as big as you or bigger, mid-bite. (A fish you miss comes back
        /// bigger, but in the levels the bot plays, the ones it misses rarely outgrow it.)
        case missed
        /// Bouncing off a jellyfish's top.
        case jellyTops = "jelly-tops"
        /// Fish hiding in the kelp, drawn as dark shapes.
        case kelpShadows = "kelp-shadows"
        /// A baited hook hanging ahead of you, its boat at the surface above it.
        case sunsetHooks = "sunset-hooks"
        /// Your headlamp in the dark, lures glowing all around.
        case midnightLight = "midnight-light"
        /// Shallow Reef's map once it's conquered: every level's pip filled in, and the crown.
        case conquered
        /// The screen for conquering Shallow Reef, which opens its Deep End.
        case deepEnd = "deep-end"

        /// The level it's played on (world, level index), for the moments in play: picked by eye from every level's
        /// best frame. (`-arcadePlaytest` picks another, to try one.)
        var level: (world: ArcadeWorld, index: Int)? {
            switch self {
            case .eat: (.shallowReef, 4)
            case .dodge: (.shallowReef, 8)
            case .missed: (.shallowReef, 9)
            case .jellyTops: (.jellyBloom, 1)
            case .kelpShadows: (.kelpForest, 7)
            case .sunsetHooks: (.sunsetCove, 6)
            case .midnightLight: (.midnightZone, 4)
            case .conquered, .deepEnd: nil
            }
        }

        /// The level map it shows, if any. (The Deep End's screen shows over the world map, as it does for a player
        /// who conquered a world before that screen existed.)
        var map: ArcadeWorld? { self == .conquered ? .shallowReef : nil }

        /// The bot's ways of playing to try; the frame comes from whichever plays the moment best.
        var policies: [ArcadeSimulation.Policy] { level == nil ? [] : ArcadeSimulation.Policy.allCases }
    }

    /// The moment this launch captures, if any.
    static let moment = moment(in: ProcessInfo.processInfo.arguments)

    /// `-storeCapture <moment>` in a launch's arguments.
    static func moment(in arguments: [String]) -> Moment? {
        guard let flag = arguments.firstIndex(of: "-storeCapture"), arguments.indices.contains(flag + 1) else { return nil }
        return Moment(rawValue: arguments[flag + 1])
    }

    // MARK: Staged progress

    /// The capture's own saved state, apart from real progress and never backed up to iCloud (`ArcadeProgress.backup`).
    static let suiteName = "biggerFish.storeCapture"

    /// The capture's own saved state, wiped and staged at launch (nil when not capturing).
    static let defaults: UserDefaults? = moment.map { moment in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if let data = try? JSONEncoder().encode(stagedSave(for: moment)) { defaults.set(data, forKey: ArcadeProgress.key) }
        return defaults
    }

    /// Sound and music off, kept in the capture's own saved state (nil when not capturing).
    static let silentSettings: ArcadeSettings? = defaults.map { defaults in
        let settings = ArcadeSettings(defaults: defaults)
        settings.soundEffectsOn = false
        settings.musicOn = false
        return settings
    }

    /// A player who has conquered Shallow Reef, with a best time on each level, and hasn't started its Deep End. The
    /// tutorial and lessons are seen, and so is every "conquered" screen, except Shallow Reef's for the Deep End's
    /// moment: the game shows it once at launch.
    static func stagedSave(for moment: Moment) -> ArcadeSave {
        var save = ArcadeSave()
        let bestTimes: [Double] = [24, 27, 31, 29, 34, 33, 38, 36, 41, 44]
        for (index, seconds) in bestTimes.enumerated() {
            let id = ArcadeWorld.shallowReef.levelID(index)
            save.clearedLevels.insert(id)
            save.bestTimes[id] = seconds
        }
        save.hasSeenTutorial = true
        save.hasSeenJellyLesson = true
        let seen = ArcadeWorld.campaign.filter { moment != .deepEnd || $0 != .shallowReef }
        save.seenUnlocks = Set(seen.map(\.rawValue))
        return save
    }

    // MARK: What a capture sees

    /// A fish as it's drawn, in screen points.
    struct Swimmer: Equatable {
        let id: Int
        let center: CGPoint
        let radius: CGFloat
        /// The fish it's swallowing, if any.
        var prey: Int? = nil
        /// Being swallowed.
        var isEaten = false
        /// How much of it is left while it's swallowed (1 whole, 0.1 nearly gone).
        var shrink: CGFloat = 1
        /// How far it has faded into a dark shape in the kelp (0 its own colors, 1 a silhouette).
        var shade: CGFloat = 0
    }

    /// A Sunset Cove hook, in screen points: where its bait hangs, and where its line meets the boat's rod at the surface.
    struct Hook: Equatable {
        let bait: CGPoint
        let rodX: CGFloat
    }

    /// The scene at one step of a run, in screen points.
    struct SceneView {
        var size = GameTuning.playfieldSize
        /// Run seconds.
        var time: CGFloat = 0
        var playing = true
        var won = false
        var player: Swimmer
        /// Your fish's climb (negative while falling), in screen points a second: it turns Midnight Zone's headlamp.
        var rising: CGFloat = 0
        /// Every other fish.
        var fish: [Swimmer] = []
        /// Jellyfish centers, and their radius.
        var jellies: [CGPoint] = []
        var jellyRadius: CGFloat = 0
        /// When your fish last bounced off a jellyfish's top, in run seconds.
        var lastBounce: CGFloat? = nil
        /// Sunset Cove's hooks you haven't passed yet.
        var hooks: [Hook] = []

        /// Wholly on screen, `margin` points clear of every edge, tail and all.
        func shows(_ fish: Swimmer, margin: CGFloat = 16) -> Bool {
            let halfWidth = fish.radius * 1.5 + margin, halfHeight = fish.radius + margin
            return fish.center.x - halfWidth >= 0 && fish.center.x + halfWidth <= size.width
                && fish.center.y - halfHeight >= 0 && fish.center.y + halfHeight <= size.height
        }

        /// Partly on screen, cut off by an edge.
        func cutsOff(_ fish: Swimmer) -> Bool {
            let halfWidth = fish.radius * 1.5, halfHeight = fish.radius
            let overlaps = fish.center.x + halfWidth > 0 && fish.center.x - halfWidth < size.width
                && fish.center.y + halfHeight > 0 && fish.center.y - halfHeight < size.height
            return overlaps && !shows(fish, margin: 0)
        }

        /// Fish other than yours wholly on screen, and not being eaten.
        var shown: [Swimmer] { fish.filter { !$0.isEaten && shows($0) } }
        /// How many fish other than yours an edge of the screen cuts off: each one is a distraction.
        var cutOff: Int { fish.filter { !$0.isEaten && cutsOff($0) }.count }

        /// How far your fish is from the middle of the water, 0 (in the middle) to 1 (at the top or bottom).
        var playerOffCenter: CGFloat { min(1, abs(player.center.y - size.height / 2) / (size.height / 2)) }
        /// How much your fish has grown on screen (0 at its starting size), up to 1.5.
        var playerGrowth: CGFloat { min(1.5, max(0, player.radius / GameTuning.baseRadius - 1)) }
    }

    /// Scores a run's frames for the moment: how good each is, or nil when it doesn't show the moment.
    static func score(_ moment: Moment, _ view: SceneView) -> Double? {
        let player = view.player
        guard view.playing, !player.isEaten, view.shows(player, margin: 8) else { return nil }
        let shown = view.shown
        let edges = Double(view.cutOff) * 10
        switch moment {
        case .eat:
            // Mid-bite on a good mouthful, a little way into the level, with fish to eat and to dodge around.
            guard let preyID = player.prey, let prey = view.fish.first(where: { $0.id == preyID }) else { return nil }
            // How big the meal still looks, against your fish.
            let mouthful = prey.radius * prey.shrink / player.radius
            guard prey.shrink <= 0.75, mouthful >= 0.35, view.playerOffCenter <= 0.5 else { return nil }
            let bigger = shown.filter { $0.radius > player.radius * 1.1 }
            let smaller = shown.filter { $0.radius < player.radius * 0.9 }
            guard shown.count >= 3, !bigger.isEmpty else { return nil }
            return Double(min(shown.count, 8)) * 6 + (smaller.isEmpty ? 0 : 10) + Double(mouthful) * 60
                + Double(view.playerGrowth) * 25 - Double(view.playerOffCenter) * 40 - edges
        case .dodge:
            // A fish much bigger than you going by just over or under you, alongside or about to be, with only a
            // sliver of water between.
            guard player.prey == nil, view.playerOffCenter <= 0.75 else { return nil }
            return shown.compactMap { threat -> Double? in
                let ratio = threat.radius / player.radius
                guard ratio >= 1.4, threat.prey == nil else { return nil }
                let reach = threat.radius + player.radius
                let dx = threat.center.x - player.center.x
                let clearance = abs(threat.center.y - player.center.y) - reach * 0.95
                guard dx > -reach, dx < reach * 2.5, (0...40).contains(clearance) else { return nil }
                return 60 - Double(clearance) + Double(min(ratio, 3)) * 20 + Double(min(shown.count, 5)) * 4
                    - Double(view.playerOffCenter) * 30 - edges
            }.max()
        case .missed:
            // A fish ahead of you that kept eating, mid-bite and as big as you or bigger.
            guard player.prey == nil else { return nil }
            return shown.compactMap { fish -> Double? in
                guard let preyID = fish.prey, let prey = view.fish.first(where: { $0.id == preyID }),
                      (0.5...0.9).contains(prey.shrink), fish.radius >= player.radius,
                      fish.center.x > player.center.x + player.radius * 2 else { return nil }
                let centered = abs(fish.center.x - view.size.width * 0.55) / view.size.width
                return 50 + Double(min(fish.radius / player.radius, 2.5)) * 10 - Double(centered) * 40
                    - Double(view.playerOffCenter) * 20 - edges
            }.max()
        case .jellyTops:
            // On a top, just bouncing off: the jellyfish under you, big beside you while you're small.
            guard let bounce = view.lastBounce, (0...0.12).contains(view.time - bounce), view.playerOffCenter <= 0.6 else { return nil }
            let onScreen = view.jellies.filter { $0.x > view.jellyRadius * 1.2 && $0.x < view.size.width - view.jellyRadius * 1.2 }
            guard let under = onScreen.min(by: { hypot($0.x - player.center.x, $0.y - player.center.y)
                    < hypot($1.x - player.center.x, $1.y - player.center.y) }),
                  under.y < player.center.y else { return nil }
            return 50 + Double(onScreen.count) * 6 + Double(min(shown.count, 5)) * 4
                + Double(min(view.jellyRadius / player.radius, 3)) * 10 - Double(view.playerOffCenter) * 20 - edges
        case .kelpShadows:
            // Dark shapes in the kelp ahead, and a fish or two still in their colors.
            let dark = shown.filter { $0.shade >= 0.85 && $0.center.x > player.center.x }
            guard !dark.isEmpty else { return nil }
            let bright = shown.filter { $0.shade == 0 }
            let middle = dark.map(\.center.x).reduce(0, +) / CGFloat(dark.count)
            return Double(min(dark.count, 4)) * 25 + Double(min(bright.count, 3)) * 8
                - Double(abs(middle - view.size.width * 0.6) / view.size.width) * 40 - Double(view.playerOffCenter) * 20 - edges
        case .midnightLight:
            // Your beam level, lighting up a fish ahead, with lures glowing round about.
            let tilt = headlampTilt(rising: view.rising)
            let lit = shown.filter { isLit($0, by: player, tilt: tilt, width: view.size.width) }
            guard !lit.isEmpty, shown.count >= 3 else { return nil }
            return Double(min(lit.count, 3)) * 25 + Double(min(shown.count, 7)) * 6
                - Double(abs(tilt)) * 40 - Double(view.playerOffCenter) * 20 - edges
        case .sunsetHooks:
            // A hook hanging well below its boat a little way ahead of you, the boat on screen, and fish about.
            guard player.prey == nil, shown.count >= 2, view.playerOffCenter <= 0.6 else { return nil }
            return view.hooks.compactMap { hook -> Double? in
                let width = view.size.width, height = view.size.height
                guard hook.bait.x > player.center.x + player.radius * 3, hook.bait.x < width * 0.85,
                      hook.rodX > width * 0.3, hook.rodX < width * 0.95,
                      hook.bait.y > height * 0.2, hook.bait.y < height * 0.65 else { return nil }
                let centered = abs(hook.bait.x - width * 0.6) / width
                return 50 + Double(min(shown.count, 6)) * 6 - Double(centered) * 40
                    - Double(view.playerOffCenter) * 20 - edges
            }.max()
        case .conquered, .deepEnd:
            return nil
        }
    }

    /// The headlamp's turn as your fish climbs or falls (as `GameScene.render` turns it).
    static func headlampTilt(rising: CGFloat) -> CGFloat {
        (rising / GameTuning.motion.maxRiseSpeed).clamped(-1, 1) * GameTuning.headlampMaxTilt
    }

    /// Well inside the headlamp's beam: ahead of your fish, within its reach and near the middle of the cone.
    static func isLit(_ fish: Swimmer, by player: Swimmer, tilt: CGFloat, width: CGFloat) -> Bool {
        let dx = fish.center.x - (player.center.x + player.radius * 0.75), dy = fish.center.y - player.center.y
        let distance = hypot(dx, dy)
        return dx > 0 && distance > player.radius * 2 && distance < width * GameTuning.headlampReach * 0.85
            && abs(atan2(dy, dx) - tilt) < GameTuning.headlampHalfAngle * 0.8
    }

    // MARK: Playing to the moment

    /// One run's best frame: which way the bot played, and how many steps in.
    struct Take: Equatable {
        let policy: ArcadeSimulation.Policy
        let step: Int
        let score: Double
    }

    /// How often the bot decides, in run seconds: as often as it does in the balance studies (`GameScene.debugSimulate`).
    static func decisionInterval(_ policy: ArcadeSimulation.Policy) -> CGFloat {
        policy == .collector ? 0.16 : policy == .cautious ? 0.10 : 0.08
    }

    /// The longest a run plays looking for its moment, in run seconds.
    static let runLimit: CGFloat = 90
    /// Frames this many steps or fewer before your fish is eaten don't count: the moment should show play going on.
    static let lastStepsBeforeEaten = 120

    /// The best of a run's frames: the highest scoring, leaving out the last ones before your fish was eaten
    /// (`eatenAt`, the step it was, if it was).
    static func best(_ takes: [Take], eatenAt: Int?) -> Take? {
        takes.filter { eatenAt == nil || $0.step < eatenAt! - lastStepsBeforeEaten }.max { $0.score < $1.score }
    }

    /// For a level in play: plays it to its moment once the scene is on screen, then saves the frame.
    @MainActor static func attach(_ scene: GameScene) {
        guard let moment, moment.level != nil else { return }
        Task { @MainActor in
            while scene.view == nil { try? await Task.sleep(for: .milliseconds(50)) }
            // Past the loading screen's fade.
            try? await Task.sleep(for: .seconds(1))
            await capture(moment, in: scene)
        }
    }

    /// For a screen out of play: saves the frame once it has settled.
    @MainActor static func begin() {
        guard let moment, moment.level == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(GameTuning.launchMinimumSeconds + 2.5))
            save(moment, note: moment.map.map { "\($0.title) map" } ?? "conquered screen")
        }
    }

    @MainActor private static func capture(_ moment: Moment, in scene: GameScene) async {
        // The bot plays between frames; nothing moves on its own meanwhile.
        scene.isPaused = true
        guard let take = bestTake(moment, in: scene, policies: moment.policies) else {
            fail(moment, "no frame showed the moment in \(moment.policies.count) runs of \(Int(runLimit)) seconds")
            return
        }
        play(scene, policy: take.policy) { step, _ in step < take.step }
        scene.debugRender()
        scene.debugHideInterface()
        // Drawn on screen before the frame is saved.
        try? await Task.sleep(for: .seconds(0.5))
        save(moment, note: "\(take.policy.rawValue) bot, step \(take.step), score \(String(format: "%.1f", take.score))")
    }

    /// The best frame of the moment in a run with each of `policies`.
    @MainActor static func bestTake(_ moment: Moment, in scene: GameScene, policies: [ArcadeSimulation.Policy]) -> Take? {
        var best: Take?
        for policy in policies {
            var takes: [Take] = []
            var steps = 0
            play(scene, policy: policy) { step, view in
                if let score = score(moment, view) { takes.append(Take(policy: policy, step: step, score: score)) }
                steps = step
                return true
            }
            let end = scene.debugCaptureView
            if let top = Self.best(takes, eatenAt: !end.playing && !end.won ? steps : nil),
               top.score > best?.score ?? -.infinity {
                best = top
            }
        }
        return best
    }

    /// Plays the level from the start with the bot, one simulation step at a time, while `going` says to (given the
    /// step just played and the scene after it), the run lasts, and it's within `runLimit`.
    @MainActor static func play(_ scene: GameScene, policy: ArcadeSimulation.Policy,
                                while going: (Int, SceneView) -> Bool) {
        scene.debugCaptureRestart()
        let interval = decisionInterval(policy)
        var nextDecision: CGFloat = 0
        var step = 0
        while CGFloat(step) * GameTuning.simulationStep < runLimit {
            let view = scene.debugCaptureView
            guard view.playing else { return }
            if view.time >= nextDecision {
                scene.debugHold(scene.debugBotHolds(policy))
                nextDecision = view.time + interval
            }
            scene.debugAdvance(seconds: GameTuning.simulationStep)
            step += 1
            guard going(step, scene.debugCaptureView) else { return }
        }
    }

    // MARK: Saving the frame

    /// Where frames are saved (cleared at each launch), for the script to collect from the simulator.
    static let framesDirectory: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoreCapture", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Saves the whole window as drawn, at the screen's full resolution and with no alpha (App Store Connect rejects
    /// PNGs with an alpha channel).
    @MainActor private static func save(_ moment: Moment, note: String) {
        guard let data = windowPNG() else { fail(moment, "no window, or couldn't encode the frame"); return }
        do {
            try data.write(to: framesDirectory.appendingPathComponent("\(moment.rawValue).png"), options: .atomic)
            print("[StoreCapture] \(moment.rawValue): \(note)")
        } catch {
            fail(moment, "couldn't save the frame: \(error.localizedDescription)")
        }
    }

    /// The whole window as drawn, at the screen's full resolution and with no alpha, as a PNG.
    @MainActor static func windowPNG() -> Data? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.pngData()
    }

    /// Tells the script the moment couldn't be captured, and why.
    private static func fail(_ moment: Moment, _ reason: String) {
        print("[StoreCapture] \(moment.rawValue) failed: \(reason)")
        try? reason.write(to: framesDirectory.appendingPathComponent("\(moment.rawValue).failed"), atomically: true, encoding: .utf8)
    }
}
#endif
