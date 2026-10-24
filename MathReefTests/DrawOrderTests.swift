import CryptoKit
import FishKit
import Foundation
import ImageIO
import Metal
import SpriteKit
import Testing
@testable import MathReef

/// The scene draws in an order fixed by depth alone (`DrawOrderAudit`), at the moments that matter, on a phone, the
/// smallest phone, and an iPad: the reef and every world's level path, padlocks and all; Settings, the parental gate, and
/// the grown-ups' links; the unlock's screens; a level's card; rounds played right and wrong, with their questions,
/// panels, and swallows; the results, their stars, and a crown; and the tutorial, from Hold to the reef.
@MainActor
struct DrawOrderTests {
    /// A moment: its name, the stage showing it, and whether it's one of the frames `manualRenderDrawOrderMoments`
    /// saves.
    typealias Capture = (_ name: String, _ stage: Stage, _ keyframe: Bool) -> Void

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// The scene's size on an iPhone 17, an iPhone SE (the smallest screen), and a 13-inch iPad (`ReefScreen`).
    static let screens: [(name: String, size: CGSize)] = {
        let iPad = CGSize(width: 1376, height: 1032), scale = ReefScreen.scale(for: iPad)
        return [("phone", CGSize(width: 874, height: 402)), ("se", CGSize(width: 667, height: 375)),
                ("ipad", CGSize(width: iPad.width / scale, height: iPad.height / scale))]
    }()

    @Test func everyScreenDrawsInOrderByDepthAlone() throws {
        var found: [String: (example: String, moments: [String])] = [:]
        try Self.sweep { name, stage, _ in
            for clash in DrawOrderAudit.clashes(in: stage.scene) {
                found[clash.kind, default: (clash.description, [])].moments.append(name)
            }
        }
        let report = found.sorted { $0.key < $1.key }.map { kind, value in
            "• \(kind)\n    e.g. \(value.example)\n    in \(value.moments.count) moments, first \(value.moments.first ?? "")"
        }
        #expect(found.isEmpty, "Drawn in either order on a phone:\n\(report.joined(separator: "\n"))")
    }

    /// The audit finds what it should: a backdrop and its text at one depth (Bigger Fish's pause menu's old bug), but not
    /// a child on its parent, nodes apart on screen, or the same color twice.
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

    /// Renders every moment when xcodebuild runs with `TEST_RUNNER_DRAW_ORDER_RENDERS=<label>`: a hash of each one's
    /// pixels, a line each, in `build/math-reef-draw-order/<label>/hashes.txt`, and the key moments as `<moment>.png`
    /// beside it. So renders before and after a change of depths can be compared pixel for pixel, every frame the audit
    /// looks at: every run plays the same, frame by frame.
    @Test func manualRenderDrawOrderMoments() throws {
        guard let label = ProcessInfo.processInfo.environment["DRAW_ORDER_RENDERS"], !label.isEmpty else { return }
        let folder = Self.root.appendingPathComponent("build/math-reef-draw-order/\(label)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var hashes: [String] = [], failures: [String] = []
        try Self.sweep { name, stage, keyframe in
            guard let image = stage.image(), let pixels = image.dataProvider?.data as Data? else {
                failures.append(name)
                return
            }
            hashes.append("\(name)  \(SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined())")
            guard keyframe else { return }
            let file = name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
            guard let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("\(file).png") as CFURL,
                                                                    "public.png" as CFString, 1, nil) else {
                failures.append(name)
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
            if !CGImageDestinationFinalize(destination) { failures.append(name) }
        }
        try (hashes.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("hashes.txt"), atomically: true,
                                                          encoding: .utf8)
        #expect(failures.isEmpty, "Couldn't render \(failures)")
    }

    // MARK: The moments

    static func sweep(_ capture: @escaping Capture) throws {
        defer { PracticeScene.testDefaults = nil }
        for screen in screens {
            let named: Capture = { capture("\(screen.name) \($0)", $1, $2) }
            try maps(screen.size, named)
            try unlock(screen.size, named)
            try rounds(screen.size, named)
            try tutorial(screen.size, named)
        }
        try fish(capture)
    }

    private static func world(_ id: String) -> Int { Curriculum.worlds.firstIndex { $0.id == id }! }

    /// The app's scene at `size`, on its own saved state with `progress` staged.
    private static func reef(_ size: CGSize, unlocked: Bool,
                             progress: (ProgressStore) -> Void = { _ in }) throws -> (Stage, PracticeScene) {
        let suite = "mathReef.tests.drawOrder"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "mathReef.soundOn")
        defaults.set(unlocked, forKey: "mathReef.unlocked")
        progress(ProgressStore(defaults: defaults))
        PracticeScene.testDefaults = defaults
        let scene = PracticeScene(size: size)
        return (try Stage(scene), scene)
    }

    /// Progress across the reef: Addition's gold crown, Subtraction's silver, Multiplication partway (its next level
    /// with a star, a skip test ahead, the rest locked), Division begun, Exponents untouched.
    private static func reefProgress(_ store: ProgressStore) {
        for world in Curriculum.worlds {
            let count = world.levels.count
            let stars: [Int] = switch world.id {
            case "addition": Array(repeating: 3, count: count)
            case "subtraction": (0..<count).map { $0 % 3 == 1 ? 2 : 3 }
            case "multiplication": [3, 2, 3, 3, 1]
            case "division": [2, 2]
            default: []
            }
            store.debugSetStars(stars, in: world)
        }
    }

    /// The reef, every world's level path at its start and its end, and Settings and the grown-ups' screens behind it.
    private static func maps(_ size: CGSize, _ capture: @escaping Capture) throws {
        let (stage, scene) = try reef(size, unlocked: true, progress: reefProgress)
        stage.play(1, "reef", capture)
        capture("reef", stage, true)
        for (index, world) in Curriculum.worlds.enumerated() {
            scene.debugShow(.world(index))
            stage.play(1, "\(world.id) path", capture)
            capture("\(world.id) path", stage, true)
            scene.debugDragLevelPath(by: -10_000)
            stage.play(0.25, "\(world.id) path's end", capture)
            capture("\(world.id) path's end", stage, true)
        }
        scene.debugShow(.home)
        scene.debugShow(.settings)
        stage.play(0.5, "settings", capture)
        capture("settings", stage, true)
        scene.debugShow(.parentalGate)
        stage.play(0.25, "parental gate", capture)
        capture("parental gate", stage, true)
        scene.debugTypeGateAnswer(digits: 1)
        stage.play(0.25, "parental gate, a digit typed", capture)
        capture("parental gate, a digit typed", stage, true)
        scene.debugTypeGateAnswer(digits: 3)
        stage.play(0.25, "for grown-ups", capture)
        capture("for grown-ups", stage, true)
    }

    /// Past the free sample without the unlock: padlocks on the level path, some over stars, and the unlock's screens.
    private static func unlock(_ size: CGSize, _ capture: @escaping Capture) throws {
        let (stage, scene) = try reef(size, unlocked: false, progress: reefProgress)
        scene.debugShow(.world(world("multiplication")))
        stage.play(0.5, "padlocked path", capture)
        capture("padlocked path", stage, true)
        scene.debugShow(.unlockPrompt)
        stage.play(0.5, "unlock prompt", capture)
        capture("unlock prompt", stage, true)
        let screens: [(PracticeScene.DebugScreen, String)] = [(.unlock, "unlock"), (.waiting, "unlock waiting"),
                                                              (.unlocked, "unlocked")]
        for (screen, name) in screens {
            scene.debugShow(screen)
            stage.play(0.25, name, capture)
            capture(name, stage, true)
        }
    }

    /// A level's card, then a round with one wrong answer (the struggle, the spit, the panel that explains it), played
    /// to its results and their stars; a squares round, with its raised digits, the same; and a gold crown's arrival.
    /// Every frame of an answer's moment is looked at, for the mouth that opens and closes in a frame or two.
    private static func rounds(_ size: CGSize, _ capture: @escaping Capture) throws {
        let (stage, scene) = try reef(size, unlocked: true, progress: reefProgress)
        let plays: [(world: Int, level: Int, misses: Set<Int>, name: String)] = [
            (world("multiplication"), 4, [1], "× round"), (world("exponents"), 0, [], "squares round"),
        ]
        for (index, level, misses, name) in plays {
            scene.debugOpenLevel(world: index, level: level, misses: misses)
            stage.play(0.5, "\(name) card", capture)
            capture("\(name) card", stage, true)
            scene.debugStartRound()
            stage.play(150, name, keyframesEvery: 5, closely: { scene.debugPhase == .feedback },
                       until: { scene.debugPhase == .summary }, capture)
            #expect(scene.debugPhase == .summary, "\(name) didn't finish")
            stage.play(3, "\(name) results", capture)
            capture("\(name) results", stage, true)
        }
        scene.debugPreviewCrown(.gold)
        stage.play(6, "crown", keyframesEvery: 0.5, capture)
    }

    /// The tutorial: Hold, left alone until its hint plays again; Let go; Eat the answer, the 2 missed once so a ring
    /// marks it the next time round; the catch, "Ready to play!", and the fade to the reef. Then once more, skipped.
    private static func tutorial(_ size: CGSize, _ capture: @escaping Capture) throws {
        let (stage, scene) = try reef(size, unlocked: false)
        scene.debugStartTutorial()
        stage.play(4, "tutorial hold", keyframesEvery: 1, capture)
        scene.debugAutopilot = true
        stage.play(10, "tutorial", keyframesEvery: 0.5, until: { scene.debugTutorialStep == .eat }, capture)
        // Left on the bottom, the fish misses the first 2, which swims by on top, and eats it the next time round.
        scene.debugAutopilot = false
        stage.play(30, "tutorial eat", keyframesEvery: 1, until: { scene.debugTutorialStep == .done }, capture)
        #expect(scene.debugTutorialStep == .done, "The tutorial's 2 wasn't eaten")
        stage.play(6, "tutorial ending", keyframesEvery: 0.25, until: { scene.debugPhase == .home }, capture)
        #expect(scene.debugPhase == .home, "The tutorial didn't end on the reef")
        stage.play(1, "tutorial ending reef", keyframesEvery: 0.25, capture)
        scene.debugStartTutorial()
        stage.play(1, "tutorial again", capture)
        scene.debugSkipTutorial()
        stage.play(1.5, "tutorial skipped", keyframesEvery: 0.5, capture)
    }

    /// Every fish as Math Reef dresses it, on its own: yours bare, in silver, and in gold, its mouth shut, opening (the
    /// line and the open mouth both show), and wide; and the answers in every look, swimming and half swallowed.
    private static func fish(_ capture: @escaping Capture) throws {
        let scene = SKScene(size: CGSize(width: 1100, height: 600))
        scene.anchorPoint = .zero
        var fish: [FishNode] = []
        for crown in [Crown.none, .silver, .gold] {
            for mouth in [0, 0.15, 0.6, 1] as [CGFloat] {
                let node = FishNode(style: .player, isPlayer: true, tailPhase: 0)
                node.setHeadwear(fishCrown(crown))
                node.apply(radius: ReefTuning.playerRadius, facing: 1, tilt: 0.1, stretchX: 1, stretchY: 1, mouthOpen: mouth,
                           time: 0.4, tailRate: 14)
                fish.append(node)
            }
        }
        for pattern in FishStyle.Pattern.allCases {
            for tail in FishStyle.Tail.allCases {
                for fin in [false, true] {
                    for shrink in [1, 0.55] as [CGFloat] {
                        let style = FishStyle(body: SKColor(red: 0.98, green: 0.6, blue: 0.3, alpha: 1),
                                              accent: SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1),
                                              pattern: pattern, tail: tail, eyeScale: 1.1, hasDorsalFin: fin)
                        let node = FishNode(style: style, isPlayer: false, tailPhase: 0)
                        node.apply(radius: ReefTuning.answerRadius, facing: -1, tilt: 0, stretchX: shrink, stretchY: shrink,
                                   mouthOpen: 0, time: 0.4, tailRate: 9)
                        fish.append(node)
                    }
                }
            }
        }
        for (index, node) in fish.enumerated() {
            node.position = CGPoint(x: 60 + CGFloat(index % 10) * 108, y: 540 - CGFloat(index / 10) * 110)
            scene.addChild(node)
        }
        capture("fish", try Stage(scene), true)
    }

    // MARK: The stage

    /// A scene played a frame at a time by a renderer, as a store capture plays (`StoreCapture.Stepper`): its update and
    /// its actions alike, so fades, the stars and the crown, and the tutorial's ending all play, the same every run.
    @MainActor final class Stage {
        let scene: SKScene
        private let view: SKView
        private let device: MTLDevice
        private let renderer: SKRenderer
        private var time: TimeInterval = 100

        init(_ scene: SKScene) throws {
            self.scene = scene
            scene.scaleMode = .fill
            view = SKView(frame: CGRect(origin: .zero, size: scene.size))
            view.ignoresSiblingOrder = true
            // Built as it's presented, then played from here: a view can't draw a scene a renderer has.
            view.presentScene(scene)
            view.isPaused = true
            scene.isPaused = false
            device = try #require(MTLCreateSystemDefaultDevice())
            renderer = SKRenderer(device: device)
            renderer.ignoresSiblingOrder = true
            renderer.scene = scene
            step()
        }

        /// Plays on a 60th of a second.
        func step() {
            time += 1.0 / 60
            renderer.update(atTime: time)
        }

        /// Plays on `seconds`, capturing the moment as `name` and the time played every quarter second, and every frame
        /// while `closely`, with a keyframe every `keyframesEvery` seconds if that's set, until `done`.
        func play(_ seconds: TimeInterval, _ name: String, keyframesEvery: TimeInterval = 0, closely: () -> Bool = { false },
                  until done: () -> Bool = { false }, _ capture: Capture) {
            let keyEvery = Int((keyframesEvery * 60).rounded())
            for frame in 1...Int((seconds * 60).rounded()) {
                step()
                if frame % 15 == 0 || closely() {
                    capture("\(name) \(String(format: "%07.3f", Double(frame) / 60))s", self, keyEvery > 0 && frame % keyEvery == 0)
                }
                if done() { return }
            }
        }

        /// The scene as it's drawn now, at twice its size in points.
        func image() -> CGImage? {
            let width = Int(scene.size.width * 2), height = Int(scene.size.height * 2)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                                      mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor), let queue = device.makeCommandQueue(),
                  let commands = queue.makeCommandBuffer() else { return nil }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            scene.backgroundColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: 1)
            pass.colorAttachments[0].storeAction = .store
            renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commands,
                            renderPassDescriptor: pass)
            commands.commit()
            commands.waitUntilCompleted()
            let bytesPerRow = width * 4
            var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
            texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                    | CGImageAlphaInfo.noneSkipFirst.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}
