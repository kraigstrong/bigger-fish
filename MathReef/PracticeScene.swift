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

    static let targetCorrect = 10
    static let requeueGap = 2
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
    let kind: AnswerKind
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
        self.kind = choice.kind
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

    private struct MenuItem {
        let title: String
        let subtitle: String
        let enabled: Bool
        let action: () -> Void
    }

    private let store = ProgressStore()
    private var phase: Phase = .home
    private var worldIndex = 0
    private var levelIndex = 0
    private var world: World { Curriculum.worlds[worldIndex] }
    private var level: Level { world.levels[levelIndex] }
    private var session = PracticeSession(facts: [], pool: [])
    private var currentFact: Fact?
    private var masteredThisSession = false
    private var rng = SeededGenerator(seed: 0)
    private var player: Fish!
    private var playerNode: FishNode!
    private var answers: [AnswerFish] = []
    private var swallow: LabSwallow?
    private var lastKind: AnswerKind = .correct
    private var chosenValue = 0
    private var feedbackRemaining: CGFloat = 0
    private var sessionStart: CGFloat = 0
    private var nextID = 1

    private let backgroundLayer = SKNode()
    private let fishLayer = SKNode()
    private let uiLayer = SKNode()
    private let playerPrompt = SKNode()
    private let topPrompt = SKNode()
    private let progressLabel = SKNode()
    private let panel = SKNode()
    private let closeButton = SKNode()
    private var buttons: [(frame: CGRect, action: () -> Void)] = []
    private var specks: [(node: SKSpriteNode, parallax: CGFloat)] = []

    private var holdTouches = Set<UITouch>()
    private var lastUpdate: TimeInterval?
    private var realClock: CGFloat = 0
    private var timeScale: CGFloat = 1
    private var isBuilt = false

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
        for node in [playerPrompt, topPrompt, progressLabel, panel, closeButton] {
            uiLayer.addChild(node)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        positiveHaptic.prepare()
        gentleHaptic.prepare()

        buildBackground()
        buildCloseButton()
        showHome()
    }

    /// The scene is created before the view knows its real size; rebuild the layout when it arrives.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isBuilt, size != oldSize, size.width > 1, size.height > 1 else { return }
        backgroundLayer.removeAllChildren()
        specks.removeAll()
        buildBackground()
        buildCloseButton()
        showHome()
    }

    @objc private func appWillResignActive() {
        holdTouches.removeAll()
    }

    // MARK: - Menus

    /// World picker.
    private func showHome() {
        enterMenu(.home)
        showMenu(
            title: "Math Reef",
            subtitle: "Pick a world.",
            items: Curriculum.worlds.indices.map { index in
                let world = Curriculum.worlds[index]
                let mastered = world.levels.filter { store.progress(for: $0).mastered }.count
                return MenuItem(
                    title: world.title,
                    subtitle: world.comingSoon ? "Coming soon" : "\(mastered)/\(world.levels.count) mastered",
                    enabled: !world.comingSoon
                ) { [weak self] in
                    self?.worldIndex = index
                    self?.showWorld()
                }
            },
            back: nil
        )
    }

    /// Level picker for the current world; later levels unlock by mastering the one before.
    private func showWorld() {
        enterMenu(.world)
        showMenu(
            title: world.title,
            subtitle: "Master each level to unlock the next.",
            items: world.levels.indices.map { index in
                let level = world.levels[index]
                let unlocked = store.isUnlocked(index, in: world)
                let progress = store.progress(for: level)
                let coverage = Mastery.coverage(progress, level: level)
                let status = progress.mastered ? "Mastered"
                    : !unlocked ? "Master level \(index) first"
                    : "Facts \(coverage.done)/\(coverage.total)"
                return MenuItem(title: "\(index + 1) · \(level.title)", subtitle: status, enabled: unlocked) { [weak self] in
                    self?.levelIndex = index
                    self?.showInstructions()
                }
            },
            back: { [weak self] in self?.showHome() }
        )
    }

    private func enterMenu(_ menu: Phase) {
        clearWave()
        phase = menu
        holdTouches.removeAll()
        setPrompt(nil)
        updateProgress()
        closeButton.isHidden = true
        render()
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
        // Facts not yet answered correctly enough come first.
        let progress = store.progress(for: level)
        let priority = Set(level.facts.map(\.id).filter { progress.correctCounts[$0, default: 0] < Mastery.correctPerFact })
        // Fresh each session so order, lanes, and colors can't be memorized across replays.
        rng = SeededGenerator(seed: UInt64.random(in: 0...UInt64.max))
        session = PracticeSession(level: level, targetCorrect: L.targetCorrect, requeueGap: L.requeueGap,
                                  priority: priority, using: &rng)
        masteredThisSession = false
        timeScale = 1

        player = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: size.height / 2), radius: L.playerRadius)
        playerNode = FishNode(style: .player, isPlayer: true, tailPhase: 0)
        playerNode.zPosition = 30
        fishLayer.addChild(playerNode)
    }

    private func showInstructions() {
        resetSession()
        phase = .instructions
        setPrompt(nil)
        updateProgress()
        closeButton.isHidden = false
        let lines: [PanelLine] = level.intro.map { line in
            line.hasPrefix("= ") ? (String(line.dropFirst(2)), 26, true) : (line, 19, false)
        } + [masteryLine]
        showPanel(
            title: "Level \(levelIndex + 1): \(level.title)",
            lines: lines,
            buttons: [("Start", { [weak self] in self?.startSession() })]
        )
        render()
    }

    /// "Mastered" or current progress toward mastery.
    private var masteryLine: PanelLine {
        let progress = store.progress(for: level)
        if progress.mastered { return ("Mastered", 17, true) }
        let coverage = Mastery.coverage(progress, level: level)
        let recent = Mastery.recentAccuracy(progress)
        return ("Mastery: facts \(coverage.done)/\(coverage.total) · last \(Mastery.window): \(recent.correct)/\(recent.of)", 16, false)
    }

    private func nextLevel() {
        levelIndex += 1
        showInstructions()
    }

    private func startSession() {
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
        let choices = fact.choices(keyMistake: level.keyMistake(for: fact), using: &rng)
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
        lastKind = answer.kind
        chosenValue = answer.value
        session.record(answer.kind)
        if store.record(answer.kind, fact: fact, level: level) { masteredThisSession = true }
        phase = .feedback
        updateProgress()

        for other in answers where other !== answer { fadeOut(other) }

        switch lastKind {
        case .correct:
            beginSwallow(answer, failing: false)
            positiveHaptic.notificationOccurred(.success)
            feedbackRemaining = L.correctFeedbackSeconds
            showPanel(title: "Yes!", lines: [(fact.solution, 28, true)], buttons: [], style: .correct)
        case .keyMistake, .otherMistake:
            // The wrong-answer panel appears when the fish is spat out (see `spit`).
            beginSwallow(answer, failing: true)
            gentleHaptic.impactOccurred(intensity: 0.4)
            feedbackRemaining = L.struggleSeconds + L.incorrectFeedbackSeconds
        }
    }

    /// Identical for every wrong answer; the summary still counts key mistakes separately.
    private func showWrongFeedback() {
        guard let fact = currentFact else { return }
        let lines = fact.wrongAnswerFeedback(chosen: chosenValue)
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
        phase = .summary
        holdTouches.removeAll()
        setPrompt(nil)
        updateProgress()
        closeButton.isHidden = true

        var result = session.result
        result.elapsedTime = TimeInterval(realClock - sessionStart)
        let seconds = Int(result.elapsedTime.rounded())
        var lines: [PanelLine] = [
            ("\(result.correctAnswers) correct · \(result.totalAttempts) attempts · \(Int((result.accuracy * 100).rounded()))%", 20, true),
            ("\(level.keyMistakeName): \(result.keyMistakes)", 18, false),
            ("Other mistakes: \(result.otherMistakes)", 18, false),
            ("Time: \(seconds / 60):\(String(format: "%02d", seconds % 60))", 18, false),
        ]
        if masteredThisSession {
            let unlocked = levelIndex + 1 < world.levels.count ? "Level \(levelIndex + 2) unlocked!" : "\(world.title) complete!"
            lines.append(("Level mastered! \(unlocked)", 22, true))
        } else {
            lines.append(masteryLine)
        }
        showPanel(
            title: masteredThisSession ? "Mastered!" : "Level \(levelIndex + 1) complete",
            lines: lines,
            buttons: summaryButtons,
            centerX: size.width / 2,
            style: masteredThisSession ? .correct : .neutral
        )
    }

    private var summaryButtons: [(title: String, action: () -> Void)] {
        var list: [(title: String, action: () -> Void)] = []
        if levelIndex + 1 < world.levels.count && store.isUnlocked(levelIndex + 1, in: world) {
            list.append(("Next: \(world.levels[levelIndex + 1].title)", { [weak self] in self?.nextLevel() }))
        }
        list.append(("Play Again", { [weak self] in self?.replay() }))
        list.append(("Levels", { [weak self] in self?.showWorld() }))
        return list
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            if !closeButton.isHidden && hypot(p.x - closeButton.position.x, p.y - closeButton.position.y) < 36 {
                showWorld()
                return
            }
            if let hit = buttons.first(where: { $0.frame.insetBy(dx: -10, dy: -10).contains(p) }) {
                hit.action()
                return
            }
            if phase == .answering || phase == .feedback {
                holdTouches.insert(touch)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTouches.subtract(touches)
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
        let slow = phase == .feedback && lastKind != .correct && swallow == nil
        let targetScale = slow ? L.incorrectTimeScale : 1
        timeScale += (targetScale - timeScale) * min(1, realDt * 8)

        if phase == .answering || phase == .feedback {
            simulate(realDt * timeScale)
        }
        if phase == .feedback {
            feedbackRemaining -= realDt
            if feedbackRemaining <= 0 { finishFeedback() }
        }
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

    private func setPrompt(_ text: String?) {
        for (node, fontSize) in [(playerPrompt, L.promptFontSize), (topPrompt, L.promptFontSize + 6)] {
            node.removeAllChildren()
            guard let text else { continue }
            let label = outlinedLabel(text, fontSize: fontSize)
            let pill = SKShapeNode(
                rectOf: CGSize(width: label.calculateAccumulatedFrame().width + 28, height: fontSize + 14),
                cornerRadius: (fontSize + 14) / 2
            )
            pill.fillColor = SKColor(white: 0, alpha: 0.35)
            pill.strokeColor = .clear
            pill.zPosition = 0
            label.zPosition = 1
            node.addChild(pill)
            node.addChild(label)
        }
        topPrompt.position = CGPoint(x: size.width / 2, y: size.height - 34)
    }

    private func updateProgress() {
        progressLabel.removeAllChildren()
        let result = session.result
        // Short enough to stay clear of the top-center prompt.
        var text = "\(world.title.uppercased()) \(levelIndex + 1)  ·  \(result.correctAnswers)/\(L.targetCorrect) correct"
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
        style: PanelStyle = .neutral
    ) {
        hidePanel()
        let titleLabel = label(title, fontSize: 32, heavy: true)
        let lineLabels = lines.map { label($0.text, fontSize: $0.fontSize, heavy: $0.heavy) }
        let buttonGap: CGFloat = 14
        let buttonLabels = newButtons.map {
            label($0.title, fontSize: 19, heavy: true, color: SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1))
        }
        let buttonWidths = buttonLabels.map { max(140, $0.frame.width + 40) }
        let buttonsWidth = buttonWidths.reduce(0, +) + CGFloat(max(0, newButtons.count - 1)) * buttonGap
        let lineHeights = lines.map { $0.fontSize + 12 }
        let height = 58 + lineHeights.reduce(0, +) + (newButtons.isEmpty ? 10 : 82)
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
        var x = -buttonsWidth / 2
        for ((_, action), (text, buttonWidth)) in zip(newButtons, zip(buttonLabels, buttonWidths)) {
            let button = SKShapeNode(rectOf: CGSize(width: buttonWidth, height: 48), cornerRadius: 24)
            button.fillColor = SKColor(white: 1, alpha: 0.92)
            button.strokeColor = .clear
            button.position = CGPoint(x: x + buttonWidth / 2, y: -height / 2 + 42)
            text.zPosition = 1
            button.addChild(text)
            panel.addChild(button)
            let center = CGPoint(x: panel.position.x + button.position.x, y: panel.position.y + button.position.y)
            buttons.append((CGRect(x: center.x - buttonWidth / 2, y: center.y - 24, width: buttonWidth, height: 48), action))
            x += buttonWidth + buttonGap
        }
        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.2))
    }

    /// Full-screen menu: title, subtitle, a grid of cards (up to 4 per row), and an optional Back.
    private func showMenu(title: String, subtitle: String, items: [MenuItem], back: (() -> Void)?) {
        hidePanel()
        let panelWidth = size.width - 80, panelHeight = size.height - 40
        let backing = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 24)
        backing.fillColor = SKColor(white: 0, alpha: 0.45)
        backing.strokeColor = .clear
        backing.zPosition = -1
        panel.addChild(backing)
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)

        let titleLabel = label(title, fontSize: 32, heavy: true)
        titleLabel.position = CGPoint(x: 0, y: panelHeight / 2 - 36)
        panel.addChild(titleLabel)
        let subtitleLabel = label(subtitle, fontSize: 17, heavy: false)
        subtitleLabel.position = CGPoint(x: 0, y: panelHeight / 2 - 68)
        panel.addChild(subtitleLabel)

        let columns = min(4, max(1, items.count))
        let rows = (items.count + columns - 1) / columns
        let gap: CGFloat = 12, cardHeight: CGFloat = 64
        let cardWidth = min(200, (panelWidth - 40 - CGFloat(columns - 1) * gap) / CGFloat(columns))
        let gridHeight = CGFloat(rows) * cardHeight + CGFloat(rows - 1) * gap
        let gridTop = (back == nil ? 0 : 22) + gridHeight / 2 - 8

        for (index, item) in items.enumerated() {
            let row = index / columns, column = index % columns
            let inRow = min(columns, items.count - row * columns)
            let rowWidth = CGFloat(inRow) * cardWidth + CGFloat(inRow - 1) * gap
            let center = CGPoint(
                x: -rowWidth / 2 + cardWidth / 2 + CGFloat(column) * (cardWidth + gap),
                y: gridTop - cardHeight / 2 - CGFloat(row) * (cardHeight + gap)
            )
            let card = SKShapeNode(rectOf: CGSize(width: cardWidth, height: cardHeight), cornerRadius: 18)
            card.position = center
            card.fillColor = SKColor(white: 1, alpha: item.enabled ? 0.92 : 0.18)
            card.strokeColor = .clear
            let textColor = item.enabled ? SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1) : SKColor(white: 1, alpha: 0.7)
            let name = label(item.title, fontSize: 18, heavy: true, color: textColor)
            name.setScale(min(1, (cardWidth - 16) / max(name.frame.width, 1)))
            name.position = CGPoint(x: 0, y: 10)
            name.zPosition = 1
            card.addChild(name)
            let status = label(item.subtitle, fontSize: 13, heavy: false, color: textColor.withAlphaComponent(0.8))
            status.setScale(min(1, (cardWidth - 16) / max(status.frame.width, 1)))
            status.position = CGPoint(x: 0, y: -14)
            status.zPosition = 1
            card.addChild(status)
            panel.addChild(card)
            if item.enabled {
                let sceneCenter = CGPoint(x: panel.position.x + center.x, y: panel.position.y + center.y)
                buttons.append((CGRect(x: sceneCenter.x - cardWidth / 2, y: sceneCenter.y - cardHeight / 2,
                                       width: cardWidth, height: cardHeight), item.action))
            }
        }

        if let back {
            let button = SKShapeNode(rectOf: CGSize(width: 120, height: 40), cornerRadius: 20)
            button.position = CGPoint(x: 0, y: -panelHeight / 2 + 34)
            button.fillColor = SKColor(white: 1, alpha: 0.92)
            button.strokeColor = .clear
            let text = label("Back", fontSize: 17, heavy: true, color: SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1))
            text.zPosition = 1
            button.addChild(text)
            panel.addChild(button)
            let sceneCenter = CGPoint(x: panel.position.x, y: panel.position.y + button.position.y)
            buttons.append((CGRect(x: sceneCenter.x - 60, y: sceneCenter.y - 20, width: 120, height: 40), back))
        }
        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.2))
    }

    private func hidePanel() {
        panel.removeAllActions()
        panel.removeAllChildren()
        buttons.removeAll()
    }

    private func buildCloseButton() {
        closeButton.removeAllChildren()
        let circle = SKShapeNode(circleOfRadius: 20)
        circle.fillColor = SKColor(white: 0, alpha: 0.25)
        circle.strokeColor = SKColor(white: 1, alpha: 0.5)
        circle.lineWidth = 1.5
        closeButton.addChild(circle)
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

    /// Superscript digits (², ³) are drawn as small raised digits: in the heavy display font the
    /// Unicode superscript glyphs are large enough that "3²" can read as "32".
    private func label(_ text: String, fontSize: CGFloat, heavy: Bool, color: SKColor = .white) -> SKLabelNode {
        let name = heavy ? "AvenirNext-Heavy" : "AvenirNext-DemiBold"
        let font = UIFont(name: name, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: heavy ? .heavy : .semibold)
        let small = font.withSize(fontSize * 0.58)
        let superscripts: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

        let styled = NSMutableAttributedString()
        for character in text {
            if let digit = superscripts.firstIndex(of: character) {
                styled.append(NSAttributedString(string: "\(digit)", attributes: [
                    .font: small, .foregroundColor: color, .baselineOffset: fontSize * 0.38,
                ]))
            } else {
                styled.append(NSAttributedString(string: String(character), attributes: [
                    .font: font, .foregroundColor: color,
                ]))
            }
        }

        let label = SKLabelNode()
        label.attributedText = styled
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
}
