import FishKit
import Foundation
import ImageIO
import SpriteKit
import Testing
@testable import BiggerFish

/// Every scene draws in an order fixed by depth alone (`DrawOrderAudit`), at the moments that matter: each world's cards
/// before and after a level, playing, paused, a sting's zap, the win's glow; the tutorial's beats, captions and hints;
/// the credits' cards, names and thanks; the maps' decoration; and the parts every scene is made of.
@MainActor
struct DrawOrderTests {
    /// A moment: its name, its scene drawn as it stands, the view showing it, and whether it's one of the frames
    /// `manualRenderDrawOrderMoments` saves.
    typealias Capture = (_ name: String, _ scene: SKScene, _ view: SKView, _ keyframe: Bool) -> Void

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    @Test func everySceneDrawsInOrderByDepthAlone() {
        var found: [String: (example: String, moments: [String])] = [:]
        Self.sweep { name, scene, _, _ in
            for clash in DrawOrderAudit.clashes(in: scene) {
                found[clash.kind, default: (clash.description, [])].moments.append(name)
            }
        }
        let report = found.sorted { $0.key < $1.key }.map { kind, value in
            "• \(kind)\n    e.g. \(value.example)\n    in \(value.moments.count) moments, first \(value.moments.first ?? "")"
        }
        #expect(found.isEmpty, "Drawn in either order on a phone:\n\(report.joined(separator: "\n"))")
    }

    /// The audit finds what it should: a backdrop and its text at one depth (the pause menu's old bug), but not a
    /// child on its parent, nodes apart on screen, or the same color twice.
    @Test func theAuditFindsSiblingsThatCanSwap() {
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let card = SKNode()
        card.position = CGPoint(x: 100, y: 100)
        scene.addChild(card)
        let panel = SKShapeNode(rectOf: CGSize(width: 120, height: 60), cornerRadius: 10)
        panel.fillColor = SKColor(white: 0, alpha: 0.3)
        card.addChild(panel)
        let words = SKLabelNode(text: "Paused")
        words.fontColor = .white
        card.addChild(words)
        let far = SKLabelNode(text: "Far")
        far.position = CGPoint(x: -90, y: -90)
        card.addChild(far)
        let button = SKShapeNode(rectOf: CGSize(width: 40, height: 20))
        button.fillColor = .white
        button.position = CGPoint(x: 0, y: -60)
        button.addChild(SKLabelNode(text: "Go"))
        card.addChild(button)
        let faint = SKShapeNode(circleOfRadius: 8)
        faint.fillColor = SKColor(white: 1, alpha: 0.2)
        faint.strokeColor = .clear
        faint.position = CGPoint(x: 0, y: -60)
        card.addChild(faint)
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        view.presentScene(scene)
        defer { withExtendedLifetime(view) {} }

        let clashes = DrawOrderAudit.clashes(in: scene)
        #expect(clashes.count == 1 && clashes.first.map { [$0.first.node, $0.second.node] }?.contains(words) == true,
                "\(clashes)")
        // Its own depth puts the panel under its words.
        panel.zPosition = -1
        #expect(DrawOrderAudit.clashes(in: scene).isEmpty)
        // A hidden node draws nothing.
        panel.zPosition = 0
        panel.isHidden = true
        #expect(DrawOrderAudit.clashes(in: scene).isEmpty)
    }

    // MARK: Pixel-identical renders

    /// Saves every key moment as `build/draw-order/<label>/<moment>.png`, when xcodebuild runs with
    /// `TEST_RUNNER_DRAW_ORDER_RENDERS=<label>`, so renders before and after a change of depths can be compared pixel
    /// for pixel. Fades that haven't run (tests don't run actions) are shown at full strength, the same each time.
    @Test func manualRenderDrawOrderMoments() throws {
        guard let label = ProcessInfo.processInfo.environment["DRAW_ORDER_RENDERS"], !label.isEmpty else { return }
        let folder = Self.root.appendingPathComponent("build/draw-order/\(label)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var failures: [String] = []
        Self.sweep { name, scene, view, keyframe in
            guard keyframe else { return }
            Self.reveal(scene)
            let file = name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
            guard let texture = view.texture(from: scene),
                  let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("\(file).png") as CFURL,
                                                                    "public.png" as CFString, 1, nil) else {
                failures.append(name)
                return
            }
            CGImageDestinationAddImage(destination, texture.cgImage(), nil)
            if !CGImageDestinationFinalize(destination) { failures.append(name) }
        }
        #expect(failures.isEmpty, "Couldn't render \(failures)")
    }

    /// Fades in waiting to run, shown as they end.
    private static func reveal(_ node: SKNode) {
        if node.alpha == 0 && node.hasActions() { node.alpha = 1 }
        for child in node.children { reveal(child) }
    }

    // MARK: The moments

    static func sweep(_ capture: @escaping Capture) {
        for world in ArcadeWorld.campaign + ArcadeWorld.prototypes { level(world, capture) }
        tutorial(capture)
        credits(capture)
        maps(capture)
        parts(capture)
    }

    private static func present(_ scene: SKScene) -> SKView {
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }

    /// Captures a level as it's drawn now. The card faded out as play began is hidden for the moment, as it is on
    /// screen (tests don't run its fade).
    private static func shoot(_ scene: GameScene, _ view: SKView, _ name: String, keyframe: Bool, _ capture: @escaping Capture) {
        scene.debugRender()
        let message = scene.debugMessage
        let shows: Bool
        switch scene.debugPhase {
        case .ready: shows = !scene.isTutorial
        case .playing, .paused: shows = false
        case .won: shows = true
        case .lost: shows = !scene.debugResultTitles.isEmpty
        }
        message.isHidden = !shows
        capture(name, scene, view, keyframe)
        message.isHidden = false
    }

    /// Plays on with the diagnostics bot, capturing every quarter second (and keyframes every `keyframes` seconds)
    /// until `seconds` pass or the run ends.
    private static func play(_ scene: GameScene, _ view: SKView, _ name: String, seconds: CGFloat, keyframes: CGFloat = 5,
                             _ capture: @escaping Capture) {
        let step = GameTuning.simulationStep
        let steps = Int((seconds / step).rounded()), every = Int((0.25 / step).rounded())
        let keyEvery = Int((keyframes / step).rounded())
        for frame in 1...steps {
            scene.debugHold(scene.debugBotHolds(.collector))
            scene.debugAdvance(seconds: step)
            guard scene.debugPhase == .playing else { return }
            if frame % every == 0 {
                shoot(scene, view, "\(name) \(String(format: "%05.2f", Double(CGFloat(frame) * step)))s",
                      keyframe: frame % keyEvery == 0, capture)
            }
        }
    }

    private static func level(_ world: ArcadeWorld, _ capture: @escaping Capture) {
        let scene = GameScene(world: world, levelIndex: 0, showsJellyLesson: false)
        // Two later levels cleared, so the pips show both ways; the first isn't, so its card says what's new.
        scene.hasCleared = { (1...2).contains($0) }
        let view = present(scene)
        defer { withExtendedLifetime(view) {} }
        let name = world.rawValue
        shoot(scene, view, "\(name) ready card", keyframe: true, capture)

        /// The card's way back in (Play again or Retry), to the prompt, and on with a new run.
        func again(_ moment: String, playing seconds: CGFloat) {
            scene.debugTapResult(scene.debugPhase == .won ? .playAgain : .tryAgain)
            shoot(scene, view, "\(name) \(moment)", keyframe: true, capture)
            scene.debugStart()
            play(scene, view, "\(name) \(moment) then playing", seconds: seconds, capture)
        }

        scene.debugStart()
        play(scene, view, "\(name) playing", seconds: 25, capture)
        if scene.debugPhase != .playing {
            // The bot's run ended (won or eaten): its card, then again.
            shoot(scene, view, "\(name) bot's card", keyframe: true, capture)
            again("tap to start after the bot", playing: 3)
        }
        if scene.debugPhase == .playing {
            scene.debugPauseForTuning()
            shoot(scene, view, "\(name) paused", keyframe: true, capture)
            scene.debugResume()
        }
        if scene.debugPhase == .playing {
            if world.hasJellies && scene.debugTouchTentacles(playerVictim: true) {
                // The zap, as it jolts and as the fish rolls over, then the card.
                shoot(scene, view, "\(name) stung", keyframe: true, capture)
                for tenth in 1...25 {
                    scene.debugAdvance(seconds: 0.1)
                    shoot(scene, view, "\(name) stung \(tenth)", keyframe: tenth == 3, capture)
                }
            } else if !scene.debugHooks.isEmpty && scene.debugTouchHook(0, at: .bait) {
                // Reeled up the line and out of the water, then the card.
                for tenth in 1...13 {
                    scene.debugAdvance(seconds: 0.1)
                    shoot(scene, view, "\(name) hooked \(tenth)", keyframe: tenth == 3, capture)
                }
            } else {
                scene.debugCommitFatalSwallowForMetrics()
                for tenth in 1...15 {
                    scene.debugAdvance(seconds: 0.1)
                    shoot(scene, view, "\(name) eaten \(tenth)", keyframe: tenth == 2, capture)
                }
            }
        }
        shoot(scene, view, "\(name) lost card", keyframe: true, capture)

        again("tap to start", playing: 0.5)
        if scene.debugPhase != .playing { again("tap to start once more", playing: 0.1) }
        scene.debugClearLevel()
        // The first clear's pip fills in with its ring (after a moment, on screen).
        if let strip = descendants(of: scene).compactMap({ $0 as? WorldProgressStrip }).first { strip.debugFillEarned(0) }
        shoot(scene, view, "\(name) won card", keyframe: true, capture)
        scene.debugAdvance(seconds: 1)
        shoot(scene, view, "\(name) won card later", keyframe: false, capture)

        scene.debugTapResult(.nextLevel)
        shoot(scene, view, "\(name) next ready card", keyframe: true, capture)
        scene.debugStart()
        play(scene, view, "\(name) level 2", seconds: 15, capture)
        scene.debugPauseForTuning()
        shoot(scene, view, "\(name) level 2 paused", keyframe: false, capture)
    }

    private static func tutorial(_ capture: @escaping Capture) {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = present(scene)
        defer { withExtendedLifetime(view) {} }
        shoot(scene, view, "tutorial ready", keyframe: true, capture)
        var frame = 0
        let run = scene.debugPlayTutorial {
            frame += 1
            guard frame % 15 == 0 else { return }
            shoot(scene, view, "tutorial \(scene.debugTutorialBeat) \(String(format: "%04d", frame))",
                  keyframe: frame % 180 == 0, capture)
        }
        #expect(run.finished)
        shoot(scene, view, "tutorial finale", keyframe: true, capture)
        scene.debugAdvance(seconds: 1)
        shoot(scene, view, "tutorial finale later", keyframe: false, capture)

        let wall = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let wallView = present(wall)
        defer { withExtendedLifetime(wallView) {} }
        _ = wall.debugPlayTutorial(missesAWallMeal: true, from: .eatEnough)
        shoot(wall, wallView, "tutorial retry card", keyframe: true, capture)
    }

    private static func credits(_ capture: @escaping Capture) {
        let settings = ArcadeSettings(defaults: UserDefaults(suiteName: "biggerFish.tests.drawOrder")!)
        settings.soundEffectsOn = false
        settings.vibrationOn = false
        let scene = CreditsScene(reduceMotion: false, settings: settings)
        let view = present(scene)
        defer { withExtendedLifetime(view) {} }
        func shoot(_ name: String, keyframe: Bool) {
            scene.debugRender()
            // The start card fades out at the first tap (tests don't run its fade).
            let startCard = descendants(of: scene).first { ($0 as? SKLabelNode)?.text == CreditsScene.startTitle }?.parent
            startCard?.isHidden = !scene.debugWaitingToStart
            capture(name, scene, view, keyframe)
            startCard?.isHidden = false
        }
        shoot("credits start card", keyframe: true)
        var frame = 0, eatenAt: [Int: Int] = [:]
        scene.debugPlay {
            frame += 1
            let eaten = scene.eaten.count
            if eatenAt[eaten] == nil { eatenAt[eaten] = frame }
            guard frame % 15 == 0 || frame == eatenAt[eaten]! + 8 else { return }
            let thanks = frame == eatenAt[eaten]! + 8 && eaten > 0
            shoot(thanks ? "credits thanks \(eaten)" : "credits swim \(String(format: "%05d", frame))",
                  keyframe: thanks ? eaten % 3 == 1 : frame % 600 == 0)
        }
        scene.debugAdvance(seconds: 0.8)
        #expect(scene.debugCardShowing)
        shoot("credits end card", keyframe: true)
    }

    private static func maps(_ capture: @escaping Capture) {
        let size = CGSize(width: 874, height: 402)
        let stops = [CGPoint(x: 90, y: 300), CGPoint(x: 250, y: 150), CGPoint(x: 420, y: 290), CGPoint(x: 600, y: 140),
                     CGPoint(x: 780, y: 280)]
        let maps: [(name: String, home: CGPoint, from: CGPoint?, pulsing: [CGPoint])] = [
            ("map swim", stops[2], stops[1], [stops[3]]), ("map home on a pulsing stop", stops[3], nil, [stops[3]]),
            ("map first stop", stops[0], nil, []),
        ]
        for (name, home, from, pulsing) in maps {
            let scene = MapDecorationScene(size: size, points: stops, fishHome: home, fishFrom: from, pulsingStops: pulsing)
            let view = present(scene)
            for (index, time) in [100.0, 100.8, 101.1, 104].enumerated() {
                scene.update(time)
                capture("\(name) \(index)", scene, view, index == 1)
            }
            withExtendedLifetime(view) {}
        }
    }

    /// The pieces every scene is built of, on their own: every kind of fish with its mouth shut, opening, and wide; the
    /// jellyfish by day and night; kelp in front and behind; a sting's zap; and a world's pips with one filling in.
    private static func parts(_ capture: @escaping Capture) {
        let size = GameTuning.playfieldSize
        let fishScene = SKScene(size: size)
        fishScene.anchorPoint = .zero
        var index = 0
        for pattern in FishStyle.Pattern.allCases {
            for tail in FishStyle.Tail.allCases {
                for fin in [false, true] {
                    for mouth in [0, 0.15, 1] as [CGFloat] {
                        let style = FishStyle(body: SKColor(red: 0.3, green: 0.79, blue: 0.94, alpha: 1),
                                              accent: SKColor(red: 0.75, green: 0.93, blue: 1, alpha: 1),
                                              pattern: pattern, tail: tail, eyeScale: 1.25, hasDorsalFin: fin)
                        let fish = FishNode(style: index == 0 ? .player : style, isPlayer: index == 0, tailPhase: 0)
                        fish.position = CGPoint(x: 50 + CGFloat(index % 9) * 95, y: 40 + CGFloat(index / 9) * 64)
                        fish.apply(radius: 18, facing: index % 2 == 0 ? 1 : -1, tilt: 0.1, stretchX: 1, stretchY: 1,
                                   mouthOpen: mouth, time: 0.4, tailRate: 9)
                        fishScene.addChild(fish)
                        index += 1
                    }
                }
            }
        }
        let fishView = present(fishScene)
        capture("parts fish", fishScene, fishView, true)

        let hazards = SKScene(size: size)
        hazards.anchorPoint = .zero
        for (x, night) in [(140, false), (380, true)] as [(CGFloat, Bool)] {
            let jelly = JellyfishNode(radius: 46, tentacleLength: 120, phase: 0.6, night: night)
            jelly.position = CGPoint(x: x, y: 260)
            jelly.animate(time: 1.3, drift: CGVector(dx: 30, dy: 0))
            hazards.addChild(jelly)
        }
        let zap = ZapNode(seed: 7)
        zap.position = CGPoint(x: 300, y: 70)
        zap.update(time: 0.2, radius: 30)
        hazards.addChild(zap)
        for (x, front) in [(560, false), (760, true)] as [(CGFloat, Bool)] {
            let kelp = KelpNode(width: 180, height: 300, seed: 3, front: front)
            kelp.position = CGPoint(x: x, y: -20)
            kelp.sway(time: 2)
            hazards.addChild(kelp)
        }
        let hazardView = present(hazards)
        capture("parts hazards", hazards, hazardView, true)

        let pips = SKScene(size: size)
        pips.anchorPoint = .zero
        for (row, level) in [3, ArcadeWorld.mainLevelCount + 2].enumerated() {
            let progress = WorldProgress(world: .kelpForest, level: level) { $0 < level }
            let strip = WorldProgressStrip(progress: progress, next: level, earned: level - 1)
            strip.position = CGPoint(x: size.width / 2, y: 280 - CGFloat(row) * 140)
            strip.debugFillEarned(level - 1 - progress.run.lowerBound)
            pips.addChild(strip)
        }
        let pipView = present(pips)
        capture("parts pips", pips, pipView, true)
        withExtendedLifetime([fishView, hazardView, pipView]) {}
    }

    static func descendants(of node: SKNode) -> [SKNode] { node.children.flatMap { [$0] + descendants(of: $0) } }
}
