import FishKit
import SpriteKit
import UIKit

// Math Reef: math practice built on the FishKit engine. Pick a world and a level, then swim into
// the right answer. Answer correctness replaces Bigger Fish's relative-size rule.

enum ReefTuning {
    // MARK: Movement (same feel as Bigger Fish to start)

    static let motion = MotionTuning(
        riseAcceleration: 1100, fallAcceleration: 1200, verticalDamping: 1.2,
        maxRiseSpeed: 250, maxFallSpeed: 250, boundaryBounce: 0.15, maxTilt: 0.35
    )
    static let waterTopMargin: CGFloat = 12
    static let waterBottomMargin: CGFloat = 10
    /// Where the player sits horizontally on screen (fraction of width).
    static let playerScreenX: CGFloat = 0.30
    static let collisionScale: CGFloat = 1.05

    // MARK: Swallow animation

    static let swallowDurationCurve: [(ratio: CGFloat, seconds: CGFloat)] = [
        (0.50, 0.12), (0.75, 0.30), (0.95, 0.72), (1.00, 0.80),
    ]
    static let pulseDuration: CGFloat = 0.25
    static let pulseAmount: CGFloat = 0.15
    static let mouthOpenSeconds: CGFloat = 0.06
    static let mouthCloseSeconds: CGFloat = 0.14

    // MARK: Sessions and answers

    static let requeueGap = 2
    /// Questions from earlier levels in the world mixed into each round (about 70% new, 30% review).
    static let reviewPerRound = 3
    /// Slower forward speed than Bigger Fish so there is time to read.
    static let screenCrossSeconds: CGFloat = 4.0
    /// Answer fish are all the same size and clearly smaller than the player.
    static let playerRadius: CGFloat = 30
    static let answerRadius: CGFloat = 21
    /// Each answer fish gets its own random speed and bob, independent of correctness.
    static let answerSwimSpeedRange: ClosedRange<CGFloat> = 15...45
    static let answerBobRange: ClosedRange<CGFloat> = 4...14
    static let answerBobRateRange: ClosedRange<CGFloat> = 0.8...1.8
    /// Extra random distance ahead per fish (screen widths) so a wave arrives staggered.
    static let staggerScreens: ClosedRange<CGFloat> = 0...0.9
    /// Random vertical offset within a lane (fraction of reachable range); lanes stay distinct.
    static let laneJitter: CGFloat = 0.07
    /// Answer lanes as fractions of the player's reachable vertical range.
    static let laneFractions: [CGFloat] = [0.1, 0.5, 0.9]
    /// Waves spawn this many screen widths ahead of the player (just off the right edge).
    static let spawnAheadScreens: CGFloat = 0.85
    /// A wave the player has fully passed is reintroduced ahead.
    static let missedBehindScreens: CGFloat = 0.45
    static let correctFeedbackSeconds: CGFloat = 1.0
    /// A wrong answer is chewed on for this long (real time) before being spat out.
    static let struggleSeconds: CGFloat = 0.6
    /// Wrong-answer panel time after the spit.
    static let incorrectFeedbackSeconds: CGFloat = 1.8
    /// Gameplay speed while incorrect feedback is showing.
    static let incorrectTimeScale: CGFloat = 0.3
    static let answerFontSize: CGFloat = 24
    static let promptFontSize: CGFloat = 34
}

private final class AnswerFish {
    let fish: Fish
    let node: FishNode
    let numberLabel: SKNode
    let value: Int
    let isCorrect: Bool
    var baseY: CGFloat
    var swimSpeed: CGFloat = 0
    var bobAmplitude: CGFloat = 0
    var bobRate: CGFloat = 1
    var fading = false

    init(fish: Fish, node: FishNode, numberLabel: SKNode, choice: Choice) {
        self.fish = fish
        self.node = node
        self.numberLabel = numberLabel
        self.value = choice.value
        self.isCorrect = choice.isCorrect
        self.baseY = 0
    }
}

private struct LabSwallow {
    let prey: AnswerFish
    /// Wrong answer: the player struggles, then spits the fish out instead of finishing.
    let failing: Bool
    var elapsed: CGFloat = 0
    let duration: CGFloat
    let startOffset: CGVector
}

final class PracticeScene: SKScene {
    private enum Phase { case home, world, instructions, answering, feedback, summary }
    private enum PanelStyle { case neutral, correct, wrong }
    private typealias L = ReefTuning
    private typealias PanelLine = (text: String, fontSize: CGFloat, heavy: Bool)

    private let store = ProgressStore()
    private var worldMap: WorldMapNode?
    private var levelMap: LevelMapNode?
    private var phase: Phase = .home
    private var worldIndex = 0
    private var levelIndex = 0
    private var world: World { Curriculum.worlds[worldIndex] }
    private var level: Level { world.levels[levelIndex] }
    private var session = PracticeSession(facts: [], pool: [])
    private var currentFact: Fact?
    private var rng = SeededGenerator(seed: 0)
    private var player: Fish!
    private var playerNode: FishNode!
    private var answers: [AnswerFish] = []
    private var swallow: LabSwallow?
    private var lastCorrect = true
    private var feedbackRemaining: CGFloat = 0
    private var sessionStart: CGFloat = 0
    private var nextID = 1

    private let backgroundLayer = SKNode()
    private let fishLayer = SKNode()
    private let uiLayer = SKNode()
    private let playerPrompt = SKNode()
    private let progressLabel = SKNode()
    private let panel = SKNode()
    private let closeButton = SKNode()
    /// Top right of the maps; opens Settings (sound on/off, and links for grown-ups).
    private let settingsButton = SKNode()
    /// Settings or one of its grown-up screens is open over the map.
    private var isShowingSettings = false
    /// The question on screen while the parental gate is open.
    private var parentalGate: ParentalGate?
    private var buttons: [(frame: CGRect, action: () -> Void)] = []
    private var specks: [(node: SKSpriteNode, parallax: CGFloat)] = []

    private var holdTouches = Set<UITouch>()
    private var lastUpdate: TimeInterval?
    private var realClock: CGFloat = 0
    private var timeScale: CGFloat = 1
    private var isBuilt = false

    private let audio = ReefAudio()
    private var hasPlayedJingle = false
    private let positiveHaptic = UINotificationFeedbackGenerator()
    private let gentleHaptic = UIImpactFeedbackGenerator(style: .soft)

    private var waterBottom: CGFloat { L.waterBottomMargin }
    private var waterTop: CGFloat { size.height - L.waterTopMargin }
    private var playerMinY: CGFloat { waterBottom + L.playerRadius * 0.95 }
    private var playerMaxY: CGFloat { waterTop - L.playerRadius * 0.95 }
    private var playerSpeed: CGFloat { size.width / L.screenCrossSeconds }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.04, green: 0.15, blue: 0.32, alpha: 1)
        guard !isBuilt, size.width > 1, size.height > 1 else { return }
        isBuilt = true

        fishLayer.zPosition = 10
        uiLayer.zPosition = 100
        addChild(backgroundLayer)
        addChild(fishLayer)
        addChild(uiLayer)
        for node in [playerPrompt, progressLabel, panel, closeButton, settingsButton] {
            uiLayer.addChild(node)
        }
        // Above the maps, which share the UI layer (the scene ignores sibling order).
        settingsButton.zPosition = 10
        panel.zPosition = 20
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        positiveHaptic.prepare()
        gentleHaptic.prepare()

        buildBackground()
        buildCloseButton()
        buildSettingsButton()
        showHome()
        #if DEBUG
        // `-previewCrown gold` (or `silver`) in the scheme's launch arguments opens on the crown.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-previewCrown"), args.indices.contains(i + 1) {
            previewCrown(args[i + 1] == "gold" ? .gold : .silver)
        }
        #endif
    }

    /// The scene is created before the view knows its real size; rebuild the layout when it arrives.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isBuilt, size != oldSize, size.width > 1, size.height > 1 else { return }
        backgroundLayer.removeAllChildren()
        specks.removeAll()
        buildBackground()
        buildCloseButton()
        buildSettingsButton()
        showHome()
    }

    @objc private func appWillResignActive() {
        holdTouches.removeAll()
    }

    // MARK: - Menus

    /// The reef: pick a world.
    private func showHome() {
        enterMenu(.home)
        let stops = Curriculum.worlds.map { world in
            let stars = store.stars(in: world)
            return WorldStop(
                title: world.title, symbol: ReefStyle.symbol(for: world.id), color: ReefStyle.color(for: world.id),
                stars: stars.earned, maxStars: stars.total, crown: store.crown(for: world), comingSoon: world.comingSoon
            )
        }
        let map = WorldMapNode(size: size, worlds: stops, focus: worldIndex, fishCrown: store.crown(for: world))
        map.onSelect = { [weak self] index in
            self?.worldIndex = index
            self?.showWorld()
        }
        uiLayer.addChild(map)
        worldMap = map
    }

    /// The current world's level path; later levels unlock by passing the one before.
    private func showWorld() {
        enterMenu(.world)
        let stops = world.levels.indices.map { index in
            let level = world.levels[index], record = store.record(for: level)
            let state: LevelStopState = record.passed ? .passed
                : store.isSkipTest(index, in: world) ? .skipTest
                : store.isUnlocked(index, in: world) ? .open
                : .locked
            return LevelStop(number: index + 1, title: level.title, stars: record.stars, state: state,
                             isCheckpoint: level.isCheckpoint)
        }
        // The fish waits at the first level still to pass (or the last one, once all are passed).
        let focus = stops.firstIndex { $0.state == .open } ?? max(0, stops.count - 1)
        let map = LevelMapNode(
            size: size, title: world.title, color: ReefStyle.color(for: world.id), levels: stops,
            stars: store.stars(in: world), crown: store.crown(for: world), focus: focus
        )
        map.onSelect = { [weak self] index in
            self?.levelIndex = index
            self?.showInstructions()
        }
        map.onBack = { [weak self] in self?.showHome() }
        uiLayer.addChild(map)
        levelMap = map
    }

    private func enterMenu(_ menu: Phase) {
        // The jingle greets you at launch and on the way back from a level, not when moving
        // between the reef and a world's level path.
        if !hasPlayedJingle || ![.home, .world].contains(phase) {
            audio.play(.mapJingle)
            hasPlayedJingle = true
            audio.playMusic(nil)
            // The music fades in as the jingle rings out.
            audio.playMusic(.menu, after: 3.0, fade: 1.5)
        }
        clearWave()
        removeMaps()
        hidePanel()
        phase = menu
        holdTouches.removeAll()
        setPrompt(nil)
        updateProgress()
        closeButton.isHidden = true
        settingsButton.isHidden = false
        isShowingSettings = false
        render()
    }

    // MARK: - Settings

    private func showSettings(animated: Bool = true) {
        parentalGate = nil
        var lines: [PanelLine] = []
        var buttons: [(title: String, action: () -> Void)] = [
            (audio.isSoundOn ? "Sound: On" : "Sound: Off", { [weak self] in self?.toggleSound() }),
            ("For grown-ups", { [weak self] in self?.showParentalGate() }),
            ("Done", { [weak self] in self?.hideSettings() }),
        ]
        #if DEBUG
        // For seeing rare moments on a device. Debug builds only, so never in the App Store.
        lines.append(("Xcode builds only: crown previews, and Multiplication's saved progress", 15, false))
        buttons += [
            ("Preview silver", { [weak self] in self?.previewCrown(.silver) }),
            ("Preview gold", { [weak self] in self?.previewCrown(.gold) }),
            ("× silver", { [weak self] in self?.debugSetUpMultiplication(.silver) }),
            ("× gold", { [weak self] in self?.debugSetUpMultiplication(.gold) }),
            ("× 1 from silver", { [weak self] in self?.debugSetUpMultiplication(.oneLevelFromSilver) }),
            ("Reset ×", { [weak self] in self?.debugSetUpMultiplication(.reset) }),
        ]
        #endif
        showSettingsPanel(title: "Settings", lines: lines, buttons: buttons, animated: animated)
    }

    /// Settings and its grown-up screens: centered over the dimmed map. `animated: false` redraws in
    /// place without the panel's fade-in, for a change on the same screen (a sound toggle, a digit).
    private func showSettingsPanel(
        title: String, lines: [PanelLine], buttons: [(title: String, action: () -> Void)],
        buttonMinWidth: CGFloat = 140, animated: Bool
    ) {
        isShowingSettings = true
        holdTouches.removeAll()
        showPanel(title: title, lines: lines, buttons: buttons, centerX: size.width / 2, buttonMinWidth: buttonMinWidth)
        let scrim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.35), size: CGSize(width: size.width * 2, height: size.height * 2))
        scrim.zPosition = -2
        panel.addChild(scrim)
        if !animated {
            panel.removeAllActions()
            panel.alpha = 1
        }
    }

    private func toggleSound() {
        audio.isSoundOn.toggle()
        showSettings(animated: false)
    }

    private func hideSettings() {
        isShowingSettings = false
        parentalGate = nil
        hidePanel()
    }

    // MARK: - For grown-ups

    /// The privacy policy and support pages leave the app, so they sit behind a parental gate
    /// (see ParentalGate.swift). A wrong answer goes back to Settings with no second try.
    private func showParentalGate() {
        parentalGate = ParentalGate()
        drawParentalGate()
    }

    /// Redrawn in place for every digit, like the other screens reached from Settings.
    private func drawParentalGate() {
        guard let gate = parentalGate else { return }
        let blanks = Array(repeating: "_", count: String(gate.answer).count - gate.entry.count)
        let entry = (gate.entry.map(String.init) + blanks).joined(separator: " ")
        var buttons: [(title: String, action: () -> Void)] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0].map { digit in
            ("\(digit)", { [weak self] in self?.typeGateDigit(digit) })
        }
        buttons += [
            ("Delete", { [weak self] in
                self?.parentalGate?.deleteDigit()
                self?.drawParentalGate()
            }),
            ("Cancel", { [weak self] in self?.showSettings(animated: false) }),
        ]
        showSettingsPanel(
            title: "For grown-ups", lines: [(gate.question, 20, false), (entry, 30, true)],
            buttons: buttons, buttonMinWidth: 56, animated: false
        )
    }

    private func typeGateDigit(_ digit: Int) {
        guard var gate = parentalGate else { return }
        let result = gate.type(digit)
        parentalGate = gate
        switch result {
        case .typing: drawParentalGate()
        case .passed: showParentLinks()
        case .failed: showSettings(animated: false)
        }
    }

    private func showParentLinks() {
        parentalGate = nil
        showSettingsPanel(
            title: "For grown-ups", lines: [("These open in Safari.", 18, false)],
            buttons: [
                ("Privacy policy", { UIApplication.shared.open(ParentLinks.privacy) }),
                ("Support", { UIApplication.shared.open(ParentLinks.support) }),
                ("Done", { [weak self] in self?.hideSettings() }),
            ],
            animated: false
        )
    }

    #if DEBUG
    /// Rewrites Multiplication's saved progress, then shows the reef so the result is visible.
    private func debugSetUpMultiplication(_ setup: DebugWorldSetup) {
        guard let index = Curriculum.worlds.firstIndex(where: { $0.id == "multiplication" }) else { return }
        store.debugSetUp(setup, in: Curriculum.worlds[index])
        worldIndex = index
        showHome()
    }

    /// A perfect round that earns `crown` in the last world opened, without touching saved progress.
    private func previewCrown(_ crown: Crown) {
        isShowingSettings = false
        removeMaps()
        resetSession()  // brings the player fish on screen to receive the crown
        audio.playMusic(nil, fade: 0.6)
        phase = .summary
        render()
        showResults(
            title: "Level passed!",
            lines: [("100%", 56, true), ("12 of 12 right", 20, false), ("\(world.title) complete!", 20, true)],
            buttons: [("Done", { [weak self] in self?.showHome() })],
            passed: true, stars: 3, newStars: 3, newCrown: crown
        )
    }
    #endif

    private func removeMaps() {
        settingsButton.isHidden = true
        worldMap?.removeFromParent()
        levelMap?.removeFromParent()
        worldMap = nil
        levelMap = nil
    }

    // MARK: - Session flow

    private func clearWave() {
        answers.forEach { $0.node.removeFromParent() }
        answers.removeAll()
        swallow = nil
    }

    private func resetSession() {
        clearWave()
        playerNode?.removeFromParent()
        // Fresh each round so order, lanes, and colors can't be memorized across replays.
        rng = SeededGenerator(seed: UInt64.random(in: 0...UInt64.max))
        session = PracticeSession(
            level: level,
            review: world.reviewPool(before: levelIndex),
            reviewCount: level.isCheckpoint ? 0 : L.reviewPerRound,
            requeueGap: L.requeueGap,
            using: &rng
        )
        timeScale = 1

        player = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: size.height / 2), radius: L.playerRadius)
        playerNode = FishNode(style: .player, isPlayer: true, tailPhase: 0)
        // The fish wears a world's crown only inside that world.
        playerNode.setHeadwear(fishCrown(store.crown(for: world)))
        playerNode.zPosition = 30
        fishLayer.addChild(playerNode)
    }

    private func showInstructions() {
        removeMaps()
        resetSession()
        phase = .instructions
        setPrompt(nil)
        updateProgress()
        closeButton.isHidden = false
        let lines: [PanelLine] = level.intro.map { line in
            line.hasPrefix("= ") ? (String(line.dropFirst(2)), 26, true) : (line, 19, false)
        } + [("Get 80% to unlock the next level.", 18, false)]
            + (store.isSkipTest(levelIndex, in: world) ? [("Passing this skips the levels before it.", 18, false)] : [])
        showPanel(
            title: "Level \(levelIndex + 1): \(level.title)",
            lines: lines,
            buttons: [("Start", { [weak self] in self?.startSession() })]
        )
        render()
    }

    private func nextLevel() {
        levelIndex += 1
        showInstructions()
    }

    private func startSession() {
        audio.playMusic(.game)
        hidePanel()
        closeButton.isHidden = false
        sessionStart = realClock
        spawnWave()
    }

    /// Play Again skips the instructions.
    private func replay() {
        resetSession()
        startSession()
    }

    private func spawnWave() {
        guard let fact = session.current else { return finishSession() }
        currentFact = fact
        phase = .answering
        setPrompt(fact.prompt)
        updateProgress()

        // Lanes, distance ahead, speed, and bob are all random per fish, so none of them predicts
        // correctness.
        let choices = fact.choices(using: &rng)
        let lanes = Array(L.laneFractions.indices).shuffled(using: &rng)
        for (choice, lane) in zip(choices, lanes) {
            let f = Fish(id: nextID, isPlayer: false, position: .zero, radius: L.answerRadius)
            nextID += 1
            f.facing = -1
            f.phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)

            let node = FishNode(style: FishStyle.random(using: &rng), isPlayer: false, tailPhase: f.phase)
            node.zPosition = 20
            let number = numberLabel(choice.value)
            number.zPosition = 10
            node.addChild(number)
            fishLayer.addChild(node)

            let answer = AnswerFish(fish: f, node: node, numberLabel: number, choice: choice)
            place(answer, lane: lane)
            answers.append(answer)
        }
    }

    private func place(_ answer: AnswerFish, lane: Int) {
        let jitter = CGFloat.random(in: -L.laneJitter...L.laneJitter, using: &rng)
        answer.baseY = playerMinY + (playerMaxY - playerMinY) * (L.laneFractions[lane] + jitter).clamped(0, 1)
        answer.swimSpeed = CGFloat.random(in: L.answerSwimSpeedRange, using: &rng)
        answer.bobAmplitude = CGFloat.random(in: L.answerBobRange, using: &rng)
        answer.bobRate = CGFloat.random(in: L.answerBobRateRange, using: &rng)
        let ahead = L.spawnAheadScreens + CGFloat.random(in: L.staggerScreens, using: &rng)
        answer.fish.position = CGPoint(x: player.position.x + size.width * ahead, y: answer.baseY)
        answer.fish.velocity = CGVector(dx: -answer.swimSpeed, dy: 0)
    }

    /// If every answer slipped past, bring the same wave back ahead with fresh lanes.
    private func reintroduceWave() {
        let lanes = Array(L.laneFractions.indices).shuffled(using: &rng)
        for (answer, lane) in zip(answers, lanes) {
            place(answer, lane: lane)
        }
    }

    private func resolve(_ answer: AnswerFish) {
        guard let fact = currentFact else { return }
        lastCorrect = answer.isCorrect
        session.record(correct: answer.isCorrect)
        phase = .feedback
        updateProgress()

        for other in answers where other !== answer { fadeOut(other) }

        if lastCorrect {
            beginSwallow(answer, failing: false)
            positiveHaptic.notificationOccurred(.success)
            feedbackRemaining = L.correctFeedbackSeconds
            showPanel(title: "Yes!", lines: [(fact.solution, 28, true)], buttons: [], style: .correct)
        } else {
            // The wrong-answer panel appears when the fish is spat out (see `spit`).
            beginSwallow(answer, failing: true)
            gentleHaptic.impactOccurred(intensity: 0.4)
            feedbackRemaining = L.struggleSeconds + L.incorrectFeedbackSeconds
        }
    }

    /// Identical for every wrong answer.
    private func showWrongFeedback() {
        guard let fact = currentFact else { return }
        let lines = fact.wrongAnswerFeedback()
        let rest: [PanelLine] = lines.dropFirst().enumerated().map { index, line in
            index == lines.count - 2 ? (line, 30, true) : (line, 22, false)
        }
        showPanel(title: lines[0], lines: rest, buttons: [], style: .wrong)
    }

    private func finishFeedback() {
        clearWave()
        hidePanel()
        if session.isComplete {
            finishSession()
        } else {
            spawnWave()
        }
    }

    private func finishSession() {
        // Quiet for the stars and crown.
        audio.playMusic(nil, fade: 0.6)
        phase = .summary
        holdTouches.removeAll()
        setPrompt(nil)
        updateProgress()
        closeButton.isHidden = true

        let result = session.result
        let summary = store.recordRound(levelIndex, in: world, correct: result.correctAnswers, attempts: result.totalAttempts)
        showResults(
            title: summary.title,
            lines: [
                ("\(summary.percent)%", 56, true),
                ("\(summary.correct) of \(summary.attempts) right", 20, false),
                (summary.outcome, 20, true),
            ],
            buttons: summaryButtons(passed: summary.passed),
            passed: summary.passed,
            stars: summary.stars,
            newStars: summary.newStars,
            newCrown: summary.newCrown
        )
    }

    /// The results panel, its stars, and (for a new or better crown) the crown presentation.
    private func showResults(
        title: String, lines: [PanelLine], buttons: [(title: String, action: () -> Void)],
        passed: Bool, stars: Int, newStars: Int, newCrown: Crown?
    ) {
        // Right of center, like the in-game panels, so the player fish (and its crown) stays in view.
        showPanel(title: title, lines: lines, buttons: buttons, style: passed ? .correct : .neutral)
        if stars > 0 { showStars(earned: stars, new: newStars) }
        if let newCrown {
            panel.run(.sequence([
                .wait(forDuration: Self.starRingTime(stars) + 0.2),
                .run { [weak self] in self?.presentCrown(newCrown) },
            ]))
        }
    }

    /// The biggest moment in the game, timed to the 2.8s sparkle: the panel dims, the crown drops in
    /// over turning rays and lands with a sparkle burst, its name pops in, then it flies onto the
    /// player fish's head, where it stays whenever the fish is in this world.
    /// Everything is a child of the panel, so leaving the results screen cancels it.
    private func presentCrown(_ crown: Crown) {
        audio.play(.crown)
        let tint = crown == .gold ? ReefStyle.gold : ReefStyle.silver
        // Centered on screen, not on the panel.
        let stage = SKNode()
        stage.position = CGPoint(x: size.width / 2 - panel.position.x, y: size.height / 2 - panel.position.y)
        stage.zPosition = 10
        panel.addChild(stage)

        let scrim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55), size: CGSize(width: size.width * 2, height: size.height * 2))
        scrim.alpha = 0
        stage.addChild(scrim)
        scrim.run(.fadeIn(withDuration: 0.25))

        let center = CGPoint(x: 0, y: 22)
        let rays = crownRays(radius: max(size.width, size.height) * 0.6, color: tint)
        rays.position = center
        rays.alpha = 0
        rays.zPosition = 1
        stage.addChild(rays)
        rays.run(.group([.fadeAlpha(to: 0.35, duration: 0.4), .repeatForever(.rotate(byAngle: .pi / 3, duration: 4))]))

        let crownNode = crownShape(width: 130, crown: crown)
        crownNode.position = CGPoint(x: center.x, y: size.height / 2 + 120)
        crownNode.zPosition = 3
        stage.addChild(crownNode)
        let drop = SKAction.move(to: center, duration: 0.45)
        drop.timingMode = .easeIn
        crownNode.run(.sequence([
            drop,
            .run { [weak self] in
                self?.positiveHaptic.notificationOccurred(.success)
                self?.sparkleBurst(at: center, in: stage)
            },
            .scaleX(to: 1.15, y: 0.85, duration: 0.08),
            .scale(to: 1.05, duration: 0.12),
            .scale(to: 1, duration: 0.1),
        ]))

        let name = label(crown == .gold ? "Gold crown!" : "Silver crown!", fontSize: 34, heavy: true, color: tint)
        let detail = label(
            crown == .gold ? "3 stars on every \(world.title) level" : "Every \(world.title) level passed",
            fontSize: 18, heavy: false
        )
        for (node, y) in [(name, center.y - 88), (detail, center.y - 116)] {
            node.position = CGPoint(x: center.x, y: y)
            node.zPosition = 3
            node.setScale(0)
            stage.addChild(node)
            node.run(.sequence([
                .wait(forDuration: 0.55),
                .scale(to: 1.15, duration: 0.15),
                .scale(to: 1, duration: 0.1),
            ]))
        }

        // Hold, then clear the stage and fly the crown onto the fish, which stays still while the
        // results show.
        stage.run(.sequence([
            .wait(forDuration: 2.6),
            .run { [weak self] in
                for node in [scrim, rays, name, detail] { node.run(.fadeOut(withDuration: 0.3)) }
                self?.crownFliesToFish(crownNode, crown: crown)
            },
        ]))
    }

    private func crownFliesToFish(_ crownNode: SKNode, crown: Crown) {
        guard let fish = playerNode, !fish.isHidden else {
            crownNode.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            return
        }
        let head = crownNode.parent.map { $0.convert(FishNode.headwearAnchor, from: fish) } ?? .zero
        let fly = SKAction.group([
            .move(to: head, duration: 0.5),
            .scale(to: 24 / 130, duration: 0.5),
            .rotate(toAngle: -0.25, duration: 0.5),
        ])
        fly.timingMode = .easeInEaseOut
        crownNode.run(.sequence([
            fly,
            .run { [weak self] in
                guard let self, let worn = fishCrown(crown) else { return }
                fish.setHeadwear(worn)
                worn.setScale(1.5)
                worn.run(.scale(to: 1, duration: 0.2))
                self.positiveHaptic.notificationOccurred(.success)
            },
            .removeFromParent(),
        ]))
    }

    /// Soft light rays behind the crown, in its color.
    private func crownRays(radius: CGFloat, color: SKColor) -> SKNode {
        let path = CGMutablePath()
        let count = 12
        for i in 0..<count {
            let a = CGFloat(i) * 2 * .pi / CGFloat(count), half = CGFloat.pi / CGFloat(count) * 0.45
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: cos(a - half) * radius, y: sin(a - half) * radius))
            path.addLine(to: CGPoint(x: cos(a + half) * radius, y: sin(a + half) * radius))
            path.closeSubpath()
        }
        let rays = SKShapeNode(path: path)
        rays.fillColor = color
        rays.strokeColor = .clear
        return rays
    }

    /// Little stars flying out from where the crown lands.
    private func sparkleBurst(at point: CGPoint, in parent: SKNode) {
        for i in 0..<14 {
            let angle = CGFloat(i) / 14 * 2 * .pi + CGFloat.random(in: -0.15...0.15)
            let distance = CGFloat.random(in: 110...170)
            let sparkle = starShape(radius: CGFloat.random(in: 5...9), filled: true)
            sparkle.position = point
            sparkle.zPosition = 2
            parent.addChild(sparkle)
            let fly = SKAction.move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance), duration: 0.7)
            fly.timingMode = .easeOut
            sparkle.run(.sequence([
                .group([fly, .rotate(byAngle: .pi, duration: 0.7), .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.35)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// When the bell for the star at `index` rings (the first star is index 0).
    private static func starRingTime(_ index: Int) -> TimeInterval { 0.35 + Double(index) * 0.4 }

    /// This round's stars sit on the top edge of the results panel. The bell rings once per earned
    /// star; ones that beat the best pop in on their ring, and the rest pulse.
    private func showStars(earned: Int, new: Int) {
        let top = panel.calculateAccumulatedFrame().maxY - panel.position.y
        for i in 0..<3 {
            let star = starShape(radius: 22, filled: i < earned)
            star.position = CGPoint(x: CGFloat(i - 1) * 54, y: top + (i == 1 ? 8 : 0))
            star.zPosition = 5
            panel.addChild(star)
            guard i < earned else { continue }
            let isNew = i >= earned - new
            if isNew { star.setScale(0) }
            star.run(.sequence([
                .wait(forDuration: Self.starRingTime(i)),
                .run { [weak self] in self?.audio.play(.star) },
                .scale(to: isNew ? 1.35 : 1.15, duration: 0.18),
                .scale(to: 1, duration: 0.12),
            ]))
        }
    }

    private func summaryButtons(passed: Bool) -> [(title: String, action: () -> Void)] {
        let hasNext = levelIndex + 1 < world.levels.count
        if passed && hasNext {
            return [
                ("Next level", { [weak self] in self?.nextLevel() }),
                ("Play again", { [weak self] in self?.replay() }),
                ("Levels", { [weak self] in self?.showWorld() }),
            ]
        }
        return [
            (passed ? "Play again" : "Try again", { [weak self] in self?.replay() }),
            ("Levels", { [weak self] in self?.showWorld() }),
        ]
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            if !closeButton.isHidden && hypot(p.x - closeButton.position.x, p.y - closeButton.position.y) < 36 {
                showWorld()
                return
            }
            if !settingsButton.isHidden && !isShowingSettings
                && hypot(p.x - settingsButton.position.x, p.y - settingsButton.position.y) < 36 {
                showSettings()
                return
            }
            if let hit = buttons.first(where: { $0.frame.insetBy(dx: -10, dy: -10).contains(p) }) {
                hit.action()
                return
            }
            // A tap outside the Settings panel closes it without reaching the map underneath.
            if isShowingSettings {
                hideSettings()
                return
            }
            if phase == .answering || phase == .feedback {
                holdTouches.insert(touch)
            }
            if phase == .home { worldMap?.handleTap(at: p) }
            if phase == .world { levelMap?.touchBegan(at: p) }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .world, !isShowingSettings, let touch = touches.first else { return }
        levelMap?.touchMoved(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTouches.subtract(touches)
        if phase == .world, let touch = touches.first { levelMap?.touchEnded(at: touch.location(in: self)) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTouches.subtract(touches)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt else { return }
        let realDt = min(lastUpdate.map { CGFloat(currentTime - $0) } ?? 0, 1.0 / 30)
        lastUpdate = currentTime
        realClock += realDt

        // Wrong answers: the struggle plays at full speed, then gameplay slows while the panel shows.
        let slow = phase == .feedback && !lastCorrect && swallow == nil
        let targetScale = slow ? L.incorrectTimeScale : 1
        timeScale += (targetScale - timeScale) * min(1, realDt * 8)

        if phase == .answering || phase == .feedback {
            simulate(realDt * timeScale)
        }
        if phase == .feedback {
            feedbackRemaining -= realDt
            if feedbackRemaining <= 0 { finishFeedback() }
        }
        worldMap?.update(time: realClock)
        levelMap?.update(time: realClock)
        render()
    }

    private func simulate(_ dt: CGFloat) {
        let (y, vy) = PlayerMotion.step(
            y: player.position.y, vy: player.velocity.dy, holding: !holdTouches.isEmpty, dt: dt,
            minY: playerMinY, maxY: playerMaxY, tuning: L.motion
        )
        player.velocity = CGVector(dx: playerSpeed, dy: vy)
        player.position = CGPoint(x: player.position.x + playerSpeed * dt, y: y)
        for speck in specks {
            speck.node.position.x -= playerSpeed * dt * speck.parallax
            if speck.node.position.x < -8 { speck.node.position.x += size.width + 16 }
        }

        for answer in answers where swallow?.prey !== answer {
            let f = answer.fish
            // Ease back toward a slow leftward swim after any bounce.
            f.velocity.dx += (-answer.swimSpeed - f.velocity.dx) * min(1, dt * 1.5)
            f.velocity.dy *= exp(-3 * dt)
            answer.baseY += f.velocity.dy * dt
            f.position.x += f.velocity.dx * dt
            f.position.y = answer.baseY + sin(realClock * answer.bobRate + f.phase) * answer.bobAmplitude
        }

        advanceSwallow(dt)
        advanceAnimations(dt)

        if phase == .answering {
            let reach = (L.playerRadius + L.answerRadius) * L.collisionScale
            if let hit = answers.first(where: {
                hypot($0.fish.position.x - player.position.x, $0.fish.position.y - player.position.y) < reach
            }) {
                resolve(hit)
            } else if answers.allSatisfy({ $0.fish.position.x < player.position.x - size.width * L.missedBehindScreens }) {
                reintroduceWave()
            }
        }
    }

    // MARK: - Swallow and bounce

    private func beginSwallow(_ answer: AnswerFish, failing: Bool) {
        player.state = .swallowing(preyID: answer.fish.id)
        answer.fish.state = .beingSwallowed(predatorID: player.id)
        answer.node.zPosition = playerNode.zPosition - 0.5
        swallow = LabSwallow(
            prey: answer,
            failing: failing,
            duration: failing ? L.struggleSeconds : SwallowTiming.duration(sizeRatio: L.answerRadius / L.playerRadius, curve: L.swallowDurationCurve),
            startOffset: CGVector(
                dx: answer.fish.position.x - player.position.x,
                dy: answer.fish.position.y - player.position.y
            )
        )
    }

    /// Same motion as the campaign swallow: the whole prey is drawn into the mouth while shrinking.
    private func advanceSwallow(_ dt: CGFloat) {
        guard var s = swallow, s.prey.fish.state != .removed else { return }
        s.elapsed += dt
        swallow = s
        let t = min(1, s.elapsed / s.duration)
        let mouth = CGVector(dx: player.radius * 1.05, dy: -player.radius * 0.1)
        let prey = s.prey.fish
        if s.failing {
            advanceStruggle(s, t: t, mouth: mouth)
            return
        }
        let eased = t * t * (3 - 2 * t)
        prey.position = CGPoint(
            x: player.position.x + s.startOffset.dx + (mouth.dx - s.startOffset.dx) * eased,
            y: player.position.y + s.startOffset.dy + (mouth.dy - s.startOffset.dy) * eased
        )
        prey.shrink = 1 - 0.9 * eased
        if t >= 1 {
            prey.state = .removed
            s.prey.node.isHidden = true
            player.state = .swimming
            player.pulse = L.pulseDuration
            audio.play(.gulp)
        }
    }

    /// Like a near-equal fight in the campaign: the prey is dragged halfway in while it wriggles and
    /// the player chews, but it never goes down.
    private func advanceStruggle(_ s: LabSwallow, t: CGFloat, mouth: CGVector) {
        let prey = s.prey.fish
        let pull = 0.5 * (1 - pow(1 - t, 2))
        let wobble = sin(s.elapsed * 38) * 4
        prey.position = CGPoint(
            x: player.position.x + s.startOffset.dx + (mouth.dx - s.startOffset.dx) * pull,
            y: player.position.y + s.startOffset.dy + (mouth.dy - s.startOffset.dy) * pull + wobble
        )
        prey.shrink = 1 - 0.15 * pull
        prey.struggle = 1
        player.squash = 0.09 * sin(s.elapsed * 30)
        player.chew = 1
        if t >= 1 { spit(s.prey) }
    }

    private func spit(_ answer: AnswerFish) {
        swallow = nil
        player.state = .swimming
        player.squash = 0
        player.chew = 0
        answer.fish.state = .swimming
        answer.fish.shrink = 1
        answer.fish.struggle = 0
        bounce(answer)
        gentleHaptic.impactOccurred(intensity: 0.7)
        audio.play(.wrong)
        showWrongFeedback()
    }

    /// Wrong answers are nonfatal: the fish is knocked away and fades out.
    private func bounce(_ answer: AnswerFish) {
        let dy = answer.fish.position.y - player.position.y
        let dir: CGFloat = dy >= 0 ? 1 : -1
        answer.fish.velocity = CGVector(dx: playerSpeed + 140, dy: dir * 160)
        player.velocity.dy -= dir * 80
        fadeOut(answer, delay: 0.5)
    }

    private func fadeOut(_ answer: AnswerFish, delay: TimeInterval = 0) {
        guard !answer.fading else { return }
        answer.fading = true
        answer.node.run(.sequence([.wait(forDuration: delay), .fadeOut(withDuration: 0.35)]))
    }

    private func advanceAnimations(_ dt: CGFloat) {
        if player.pulse > 0 { player.pulse = max(0, player.pulse - dt) }
        if case .swallowing = player.state {
            player.mouth = min(1, player.mouth + dt / L.mouthOpenSeconds)
        } else {
            player.mouth = max(0, player.mouth - dt / L.mouthCloseSeconds)
        }
    }

    // MARK: - Rendering

    private func render() {
        guard let player else { return }
        let anchorX = size.width * L.playerScreenX

        var stretch: CGFloat = 1
        if player.pulse > 0 {
            stretch += sin((1 - player.pulse / L.pulseDuration) * .pi) * L.pulseAmount
        }
        playerNode.isHidden = phase == .home || phase == .world
        playerNode.position = CGPoint(x: anchorX, y: player.position.y)
        // Chewing during a struggle, as in the campaign's close calls.
        let mouth = player.mouth * (1 - 0.35 * player.chew * (0.5 + 0.5 * sin(realClock * 38)))
        playerNode.apply(
            radius: player.radius, facing: 1,
            tilt: (player.velocity.dy / L.motion.maxRiseSpeed * L.motion.maxTilt).clamped(-L.motion.maxTilt, L.motion.maxTilt),
            stretchX: stretch * (1 + player.squash), stretchY: stretch * (1 - player.squash), mouthOpen: mouth,
            time: realClock, tailRate: 14
        )
        playerPrompt.position = CGPoint(x: anchorX, y: player.position.y + L.playerRadius + 30)

        for answer in answers {
            let f = answer.fish
            answer.node.position = CGPoint(x: anchorX + f.position.x - player.position.x, y: f.position.y)
            answer.node.apply(
                radius: f.radius, facing: f.facing, tilt: f.struggle * sin(realClock * 45) * 0.35,
                stretchX: f.shrink, stretchY: f.shrink, mouthOpen: 0,
                time: realClock, tailRate: 9
            )
            answer.numberLabel.setScale(f.shrink)
        }
    }

    // MARK: - UI

    /// The question rides above the player fish.
    private func setPrompt(_ text: String?) {
        playerPrompt.removeAllChildren()
        guard let text else { return }
        let fontSize = L.promptFontSize
        let label = outlinedLabel(text, fontSize: fontSize)
        let pill = SKShapeNode(
            rectOf: CGSize(width: label.calculateAccumulatedFrame().width + 28, height: fontSize + 14),
            cornerRadius: (fontSize + 14) / 2
        )
        pill.fillColor = SKColor(white: 0, alpha: 0.35)
        pill.strokeColor = .clear
        pill.zPosition = 0
        label.zPosition = 1
        playerPrompt.addChild(pill)
        playerPrompt.addChild(label)
    }

    private func updateProgress() {
        progressLabel.removeAllChildren()
        let result = session.result
        // Short enough to stay clear of the top-center prompt.
        var text = "\(world.title.uppercased()) \(levelIndex + 1)  ·  \(result.correctAnswers)/\(session.targetCorrect)"
        if session.streak >= 2 { text += "   ·   streak \(session.streak)" }
        let label = label(text, fontSize: 14, heavy: true)
        label.horizontalAlignmentMode = .left
        label.alpha = 0.8
        progressLabel.addChild(label)
        progressLabel.position = CGPoint(x: 64, y: size.height - 34)
        progressLabel.isHidden = phase != .answering && phase != .feedback
    }

    /// Big number drawn on the fish; a dark offset copy keeps it legible on any body color.
    /// Long numbers (1000) shrink to fit the body; every fish stays the same size.
    private func numberLabel(_ value: Int) -> SKNode {
        let text = outlinedLabel("\(value)", fontSize: L.answerFontSize)
        let maxWidth = L.answerRadius * 2.2
        let width = text.calculateAccumulatedFrame().width
        if width > maxWidth { text.setScale(maxWidth / width) }
        // Answer fish face left; shift toward the tail and down so the number clears the eye.
        text.position = CGPoint(x: L.answerRadius * 0.22, y: -L.answerRadius * 0.12)
        let container = SKNode()
        container.addChild(text)
        return container
    }

    private func outlinedLabel(_ text: String, fontSize: CGFloat) -> SKNode {
        let node = SKNode()
        let shadow = label(text, fontSize: fontSize, heavy: true, color: SKColor(white: 0, alpha: 0.75))
        shadow.position = CGPoint(x: 1.5, y: -1.5)
        // Explicit z: the scene ignores sibling order, so equal-z siblings draw in arbitrary order
        // and the shadow could land on top of the white text.
        shadow.zPosition = 0
        let front = label(text, fontSize: fontSize, heavy: true)
        front.zPosition = 0.5
        node.addChild(shadow)
        node.addChild(front)
        return node
    }

    private func showPanel(
        title: String,
        lines: [(text: String, fontSize: CGFloat, heavy: Bool)],
        buttons newButtons: [(title: String, action: () -> Void)],
        centerX: CGFloat? = nil,
        style: PanelStyle = .neutral,
        buttonMinWidth: CGFloat = 140
    ) {
        hidePanel()
        let titleLabel = label(title, fontSize: 32, heavy: true)
        let lineLabels = lines.map { label($0.text, fontSize: $0.fontSize, heavy: $0.heavy) }
        let buttonGap: CGFloat = 14
        let buttonLabels = newButtons.map {
            label($0.title, fontSize: 19, heavy: true, color: SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1))
        }
        let buttonWidths = buttonLabels.map { max(buttonMinWidth, $0.frame.width + 40) }
        // Buttons wrap onto more rows when one row would be wider than the screen allows.
        let rowGap: CGFloat = 12
        var rows: [[Int]] = []
        for index in buttonWidths.indices {
            let row = rows.last ?? []
            let rowWidth = row.map { buttonWidths[$0] + buttonGap }.reduce(0, +) + buttonWidths[index]
            if row.isEmpty || rowWidth > size.width - 100 { rows.append([index]) } else { rows[rows.count - 1].append(index) }
        }
        let rowWidth = { (row: [Int]) in row.map { buttonWidths[$0] }.reduce(0, +) + CGFloat(max(0, row.count - 1)) * buttonGap }
        let buttonsWidth = rows.map(rowWidth).max() ?? 0
        let lineHeights = lines.map { $0.fontSize + 12 }
        let buttonsHeight = newButtons.isEmpty ? 10 : 82 + CGFloat(rows.count - 1) * (48 + rowGap)
        let height = 58 + lineHeights.reduce(0, +) + buttonsHeight
        let width = max(titleLabel.frame.width, lineLabels.map(\.frame.width).max() ?? 0, buttonsWidth) + 60

        let backing = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        switch style {
        case .neutral:
            backing.fillColor = SKColor(white: 0, alpha: 0.45)
            backing.strokeColor = .clear
        case .correct:
            backing.fillColor = SKColor(red: 0.10, green: 0.52, blue: 0.30, alpha: 0.92)
            backing.strokeColor = SKColor(white: 1, alpha: 0.6)
            backing.lineWidth = 2
        case .wrong:
            backing.fillColor = SKColor(red: 0.72, green: 0.20, blue: 0.22, alpha: 0.92)
            backing.strokeColor = SKColor(white: 1, alpha: 0.6)
            backing.lineWidth = 2
        }
        backing.zPosition = -1
        panel.addChild(backing)

        var y = height / 2 - 34
        titleLabel.position = CGPoint(x: 0, y: y)
        panel.addChild(titleLabel)
        y -= 24
        for (line, lineHeight) in zip(lineLabels, lineHeights) {
            y -= lineHeight / 2
            line.position = CGPoint(x: 0, y: y)
            panel.addChild(line)
            y -= lineHeight / 2
        }

        panel.position = CGPoint(x: centerX ?? size.width * 0.6, y: size.height / 2)
        for (rowIndex, row) in rows.enumerated() {
            var x = -rowWidth(row) / 2
            let rowY = -height / 2 + 42 + CGFloat(rows.count - 1 - rowIndex) * (48 + rowGap)
            for index in row {
                let (text, buttonWidth, action) = (buttonLabels[index], buttonWidths[index], newButtons[index].action)
                let button = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: 48), cornerRadius: 24)
                button.fillColor = SKColor(white: 1, alpha: 0.92)
                button.strokeColor = .clear
                button.position = CGPoint(x: x + buttonWidth / 2, y: rowY)
                text.zPosition = 1
                button.addChild(text)
                panel.addChild(button)
                let center = CGPoint(x: panel.position.x + button.position.x, y: panel.position.y + button.position.y)
                buttons.append((CGRect(x: center.x - buttonWidth / 2, y: center.y - 24, width: buttonWidth, height: 48), action))
                x += buttonWidth + buttonGap
            }
        }
        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.2))
    }

    private func hidePanel() {
        panel.removeAllActions()
        panel.removeAllChildren()
        buttons.removeAll()
    }

    /// The small translucent circle behind the close and settings icons.
    private func roundButtonBacking() -> SKShapeNode {
        let circle = SKShapeNode(circleOfRadius: 20)
        circle.fillColor = SKColor(white: 0, alpha: 0.25)
        circle.strokeColor = SKColor(white: 1, alpha: 0.5)
        circle.lineWidth = 1.5
        return circle
    }

    /// Same spot and style as the in-level close button, which it never appears alongside.
    private func buildSettingsButton() {
        settingsButton.removeAllChildren()
        settingsButton.addChild(roundButtonBacking())
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        if let symbol = UIImage(systemName: "gearshape.fill", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            let image = UIGraphicsImageRenderer(size: symbol.size).image { _ in symbol.draw(at: .zero) }
            let gear = SKSpriteNode(texture: SKTexture(image: image))
            gear.zPosition = 1
            settingsButton.addChild(gear)
        }
        settingsButton.position = CGPoint(x: size.width - 64, y: size.height - 36)
    }

    private func buildCloseButton() {
        closeButton.removeAllChildren()
        closeButton.addChild(roundButtonBacking())
        let cross = label("✕", fontSize: 18, heavy: true)
        cross.zPosition = 1
        closeButton.addChild(cross)
        closeButton.position = CGPoint(x: size.width - 64, y: size.height - 36)
    }

    private func buildBackground() {
        let gradient = SKSpriteNode(texture: WaterTextures.gradient())
        gradient.anchorPoint = .zero
        gradient.size = size
        gradient.zPosition = -1  // behind the specks; the scene ignores sibling order
        backgroundLayer.addChild(gradient)

        var speckRNG = SeededGenerator(seed: 7)
        let dot = WaterTextures.dot()
        for _ in 0..<40 {
            let node = SKSpriteNode(texture: dot)
            let parallax = CGFloat.random(in: 0.15...0.7, using: &speckRNG)
            let d = 1.5 + parallax * 4
            node.size = CGSize(width: d, height: d)
            node.alpha = 0.12 + parallax * 0.3
            specks.append((node, parallax))
            node.position = CGPoint(
                x: CGFloat.random(in: 0...size.width, using: &speckRNG),
                y: CGFloat.random(in: 0...size.height, using: &speckRNG)
            )
            backgroundLayer.addChild(node)
        }
    }

    private func label(_ text: String, fontSize: CGFloat, heavy: Bool, color: SKColor = .white) -> SKLabelNode {
        reefLabel(text, fontSize: fontSize, heavy: heavy, color: color)
    }
}
