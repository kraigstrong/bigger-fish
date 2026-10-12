import FishKit
import SpriteKit
import UIKit

private struct Swallow {
    let predatorID: Int
    let preyID: Int
    var elapsed: CGFloat = 0
    let duration: CGFloat
    /// prey radius / predator radius at the moment of contact.
    let ratio: CGFloat
    /// Prey position relative to the predator at contact (wrapped).
    let startOffset: CGVector
}

private struct BloomJelly {
    let node: JellyfishNode
    let origin: CGPoint
    var position: CGPoint
    let phase: CGFloat
}

/// A fish stung by tentacles: it jolts, rolls belly-up, and sinks out of sight.
private struct StungFish {
    let id: Int
    let node: FishNode
    let zap: ZapNode
    let start: CGFloat
    let position: CGPoint
    let radius: CGFloat
    let facing: CGFloat
}

private struct Speck {
    let node: SKSpriteNode
    let parallax: CGFloat
    let rise: CGFloat
}

/// A Sunset Cove hook on screen: its boat at the surface, its line, the hook, and the bait on it.
private struct HookRig {
    let hook: PlannedHook
    let boat: HookBoatNode
    let line: SKShapeNode
    let metal: SKShapeNode
    let bait: FishNode
    /// The gate's first line hangs from the second one's boat.
    let sharesBoat: Bool
}

/// One of Sunset Cove's shafts of sunlight: where it enters the water, drifting a little as you swim.
private struct SunRay {
    let node: SKSpriteNode
    var x: CGFloat
    let strength: CGFloat
    let phase: CGFloat
}

final class GameScene: SKScene {
    enum Phase {
        case ready, playing, paused, won, lost

        #if DEBUG
        /// As the hitch log and run recordings name it.
        var name: String {
            switch self {
            case .ready: "ready"
            case .playing: "playing"
            case .paused: "paused"
            case .won: "won"
            case .lost: "lost"
            }
        }
        #endif
    }
    private typealias T = GameTuning

    private var phase: Phase = .ready
    private var world = WrappedWorld(width: 1)
    private var fish: [Fish] = []
    private var fishByID: [Int: Fish] = [:]
    private var nodes: [Int: FishNode] = [:]
    private var swallows: [Swallow] = []
    private var player: Fish!
    private var nextFishID = 1
    private var mealsEaten = 0
    private var hasWon: Bool {
        !isTutorial && GameRules.isWin(fish) && waitingFish.isEmpty
    }
    /// The first-launch tutorial (`ArcadeTutorial`) instead of a level: its beats bring their own fish, nothing is
    /// recorded as cleared, and it ends by leaving for the map.
    let isTutorial: Bool
    let arcadeWorld: ArcadeWorld
    private var levelIndex: Int {
        didSet { worldLevel = arcadeWorld.level(levelIndex) }
    }
    /// The level being played (it advances with Next level), for the map to return to.
    var currentLevelIndex: Int { levelIndex }
    /// This slot's level, looked up once: `level` is read for every fish on every step.
    private var worldLevel: Level
    private var level: Level {
        if isTutorial { return T.tutorialLevel }
        #if DEBUG
        if let plannerLevel { return plannerLevel }
        #endif
        return worldLevel
    }
    /// Beating a world's tenth level finishes its main run: the result leads back to the map, where the next
    /// world and the Deep End open, rather than straight on to the Deep End.
    private var isWorldFinale: Bool {
        #if DEBUG
        if plannerLevel != nil { return false }
        #endif
        return levelIndex == ArcadeWorld.mainLevelCount - 1
    }
    private var isFinalLevel: Bool {
        #if DEBUG
        if plannerLevel != nil { return true }
        #endif
        return levelIndex == arcadeWorld.levelCount - 1
    }
    var analytics: ArcadeAnalytics?
    /// Whether a level of this world is cleared, for metrics and the world's progress pips.
    var hasCleared: ((Int) -> Bool)?
    /// Whether this run's level was already cleared when it started: a first clear fills its pip in with a pop.
    private var clearedBeforeRun = false
    private var metricAccumulator: ArcadeMetricAccumulator?
    private var fatalMetrics: ArcadeRunMetrics?
    private var metricDeathCause = "none"

    private var metricContext: ArcadeMetricContext {
        ArcadeMetricContext(world: arcadeWorld.rawValue, level: levelIndex + 1,
            setup: (level.ecosystemSeedIndex ?? levelIndex) + 1, seed: String(ecosystemSeed), revision: ArcadeAnalytics.revision)
    }
    private func metricSnapshot() -> ArcadeGrowthSnapshot {
        ArcadeGrowthSnapshot.measure(player: max(player.radius, player.targetRadius),
            opponents: fish.filter { !$0.isPlayer && $0.state != .removed }.map { max($0.radius, $0.targetRadius) },
            efficiency: level.effectiveAbsorptionEfficiency, inFlight: !swallows.isEmpty)
    }
    private func observeMetrics() {
        guard metricAccumulator != nil, fatalMetrics == nil else { return }
        metricAccumulator?.advance(seconds: Double(simClock), circuits: Double(forwardDistance / world.width))
        metricAccumulator?.observe(metricSnapshot())
    }
    private func enqueueMetricOperation(_ operation: @escaping (ArcadeAnalytics) -> Void) {
        guard let analytics, analytics.enabled else { return }
        // Every scene lifecycle operation uses this FIFO, preserving order without disk work on contacts.
        DispatchQueue.main.async { operation(analytics) }
    }
    private func finishMetrics(_ outcome: String) {
        guard let accumulator = metricAccumulator else { return }
        let summary = fatalMetrics ?? accumulator.summary
        let cause = outcome == "death" ? metricDeathCause : "none"
        metricAccumulator = nil; fatalMetrics = nil
        enqueueMetricOperation { $0.finish(outcome, cause: cause, summary: summary) }
    }
    func exitMetrics() {
        observeMetrics(); finishMetrics("quit")
        enqueueMetricOperation { $0.leave(); $0.flush() }
    }

    var onClear: ((Int, Double) -> Void)?
    var onExit: (() -> Void)?
    /// Pausing and resuming, so the screen around the playfield (on an iPad) can darken with the pause menu.
    var onPause: ((Bool) -> Void)?
    /// The first-launch tutorial was played to the end (called at once, before the win plays out and it leaves).
    var onTutorialFinished: (() -> Void)?
    /// Set from `onClear` when this win conquers the world for the first time: instead of its result card, the
    /// level leaves for the world's conquered screen once the win has played.
    var leavesForConqueredScreen = false
    /// Playing the same level again (Retry, Play again, or Restart): no card before it, just the prompt.
    private var replaying = false
    /// Whether a level is past the free ones without the unlock. Next level onto one leaves the level instead, with
    /// `leftForUnlock` set, so the unlock's screen can show.
    var levelNeedsUnlock: ((Int) -> Bool)?
    private(set) var leftForUnlock = false
    var onJellyLesson: (() -> Void)?
    private var showsJellyLesson: Bool
    private var lossReason = "There was a bigger fish."
    private var jellies: [BloomJelly] = []
    private var encounterLeases: [Int: EncounterLease] = [:]
    private var forwardDistance: CGFloat = 0
    private struct EncounterNeighbor {
        let id: Int
        let position: CGPoint
        let velocity: CGVector
        let radius: CGFloat
    }
    private var encounterNeighbors: [EncounterNeighbor] = []
    private var bounceRemaining: CGFloat = 0
    private var bounceCooldown: CGFloat = 0
    private var mapButton = MenuButtonRow(title: "Level map", symbol: "map.fill", style: .secondary)
    private var resultPanel: ArcadeResultPanel?
    #if DEBUG
    /// A test's or a bot's touch: holding or not, in place of real touches.
    private var simulationHolding: Bool?
    /// Played without a screen (tests, the planner's studies): no sound or analytics.
    private var simulationHeadless = false
    /// Your fish swims on untouchable: nothing eats it, it eats nothing, and jellies pass through it, so a run
    /// measures the fish alone (`debugEncounterCrossings`).
    private var simulationEcologyProbe = false
    /// A planned test level, played outside the campaign.
    private var plannerLevel: Level?
    /// A bot's fish that no other fish can eat: it passes through a bigger one (`debugPlayReferenceRoute`).
    private var simulationSafeFromFish = false
    /// On-screen contacts between two planned fish you haven't met, which bend their planned paths.
    private(set) var debugVisibleUnmetContacts = 0
    var debugPracticeRun = false
    func debugPauseForTuning() { if phase == .playing { pauseRun() } }
    func debugResume() { if phase == .paused { setPhase(.playing) } }
    private let previewResult = ArcadePlaytest.resultPreview
    private var didPreviewResult = false
    private var runRecorder: ArcadeRunRecorder?
    private var recordingStartedAt: CGFloat = 0
    private var recordedEncounterReleases: Set<Int> = []
    /// Where slow frames go (`HitchLog`); a test's own, or none.
    var hitchLog = HitchLog.shared
    #endif
    private var audio: ArcadeAudio { .shared }
    private var settings: ArcadeSettings { .shared }

    init(world: ArcadeWorld = .shallowReef, levelIndex: Int = 0,
         showsJellyLesson: Bool = true, tutorial: Bool = false) {
        arcadeWorld = world
        isTutorial = tutorial
        self.levelIndex = min(max(0, levelIndex), world.levelCount - 1)
        worldLevel = world.level(self.levelIndex)
        self.showsJellyLesson = showsJellyLesson
        super.init(size: T.playfieldSize)
        scaleMode = .aspectFit
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var aiMovementRNGs: [Int: SeededGenerator] = [:]
    /// Each fish's movement stream comes from this and its stable ID: a planned level's seed, or for the tutorial
    /// (which has no plan), the game's.
    private var ecosystemSeed: UInt64 { level.meetingPlan?.seed ?? T.spawnSeed }

    private func movementGenerator(for id: Int) -> SeededGenerator {
        FreeSwim.movementGenerator(ecosystemSeed: ecosystemSeed, id: id, variant: movementVariants[id] ?? 0)
    }
    /// Planned fish pick one of many movement streams; every other fish keeps variant 0.
    private var movementVariants: [Int: UInt64] = [:]

    private let backgroundLayer = SKNode()
    private let fishLayer = SKNode()
    private let hazardLayer = SKNode()
    private let uiLayer = SKNode()
    private let dimNode = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
    private var specks: [Speck] = []
    private var winGlow: SKShapeNode?

    private let messageNode = SKNode()
    private let pauseButton = SKNode()
    private let pauseMenu = SKNode()
    private let levelIndicator = SKNode()
    private var resumeButton = MenuButtonRow(title: "Resume", symbol: "play.fill", style: .primary)
    private var restartButton = MenuButtonRow(title: "Restart level", symbol: "arrow.counterclockwise", style: .secondary)
    private var effectsButton = MenuSwitchRow(title: "Sound effects", symbol: "speaker.wave.2.fill", isOn: true)
    private var musicButton = MenuSwitchRow(title: "Music", symbol: "music.note", isOn: true)
    private var vibrationButton = MenuSwitchRow(title: "Vibration", symbol: "iphone.radiowaves.left.and.right", isOn: true)

    private var holdTouches = Set<UITouch>()
    private var lastUpdate: TimeInterval?
    private var frameAccumulator: CGFloat = 0
    private var simulationAccumulator: CGFloat = 0
    private var previousPresentation: [Int: FishPresentation] = [:]
    private var previousJellyPositions: [CGPoint] = []
    private var previousZoom: CGFloat = 1
    private var realClock: CGFloat = 0
    /// Simulated seconds since the current run started playing.
    private var simClock: CGFloat = 0
    private var timeScale: CGFloat = 1
    private var slowMoRemaining: CGFloat = 0
    private var slowMoFactor: CGFloat = 1
    private var endedAt: CGFloat = 0
    private var stungFish: [StungFish] = []
    /// Kelp Forest fish that appear just off screen once you reach `appearsAt`, soonest first.
    private var waitingFish: [PlannedFish] = []
    /// A Kelp Forest fish swims straight at its meeting height until you're this far along, then roams.
    private var approachEnds: [Int: (until: CGFloat, y: CGFloat, start: CGFloat, path: Approach?, heading: CGFloat)] = [:]
    private var kelpBeds: [(bed: PlannedKelp, back: KelpNode, front: KelpNode)] = []
    /// Sunset Cove's hooks, each with its boat, line, and bait.
    private var hookRigs: [HookRig] = []
    /// You, caught on a hook and reeled up its line out of the water: which hook, when (real time), where it caught
    /// you, and whether you've broken the surface yet.
    private var reel: (rig: Int, start: CGFloat, from: CGPoint, splashed: Bool)?
    private var sunRays: [SunRay] = []
    /// Whether a delayed loss (a sting) sounds when its result shows; a hook's sounds as it catches you.
    private var lossSoundsAtResult = true
    #if DEBUG
    fileprivate var mealLog: [(id: Int, time: CGFloat)] = []
    #endif
    /// Midnight Zone's dark with your headlamp's beam in it: one sprite that multiplies the scene, centered on your
    /// head and turned with you.
    private var headlamp: SKSpriteNode?
    /// Fish drawn as silhouettes while in kelp, and the colors each of their shapes had before.
    /// How far each fish has faded into its silhouette (0: its own colors, 1: one dark shape).
    private var silhouetteShade: [Int: CGFloat] = [:]
    /// After a sting, the result waits until the death animation has played.
    private var pendingLossResultAt: CGFloat?
    /// When a world-conquering win leaves for the conquered screen (see `leavesForConqueredScreen`).
    private var pendingConqueredExitAt: CGFloat?
    private var lastCameraX: CGFloat = 0
    private var hasLayers = false
    private var isBuilt = false

    private let closeCallHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let eatenHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let eatenNotification = UINotificationFeedbackGenerator()
    private let mealHaptic = UIImpactFeedbackGenerator(style: .light)
    private let winNotification = UINotificationFeedbackGenerator()
    /// The Vibration setting (Settings, and the pause menu): off, the game plays no haptics.
    private var vibrates: Bool { ArcadeSettings.shared.vibrationOn }

    /// Wakes the haptics before they're needed. A session's first haptic otherwise stalls a frame while iOS sets them up:
    /// the first death (its two buzzes) stuttered. Called as the scene appears, while its card is up and nothing moves,
    /// and again as each run starts, since a prepared generator only stays ready a few seconds.
    private func prepareHaptics() {
        guard vibrates, view != nil else { return }
        #if DEBUG
        noteHitch(.hapticPrepare, "all five generators")
        #endif
        let generators: [UIFeedbackGenerator] = [mealHaptic, closeCallHaptic, eatenHaptic, eatenNotification, winNotification]
        for generator in generators { generator.prepare() }
    }

    /// Every haptic the game plays.
    enum Haptic: String {
        case meal, closeCall, bounce, sting, eaten, win, conquer

        #if DEBUG
        /// The haptic and the generators it fires, for the hitch log.
        var hitchDetail: String {
            switch self {
            case .meal: "meal: light impact"
            case .closeCall: "closeCall: rigid impact"
            case .bounce: "bounce: rigid impact"
            case .sting: "sting: error notification"
            case .eaten: "eaten: heavy impact + error notification"
            case .win: "win: success notification"
            case .conquer: "conquer: success notification"
            }
        }
        #endif
    }

    /// Plays a haptic, if Vibration is on: a light tap for a meal (a sharper one for a close call), a bump off a
    /// jellyfish, an error buzz for a sting or being eaten, a success for a win, and a success then a thump for
    /// conquering a world.
    private func buzz(_ haptic: Haptic) {
        guard vibrates else { return }
        #if DEBUG
        debugHaptics.append(haptic)
        noteHitch(.haptic, haptic.hitchDetail)
        #endif
        switch haptic {
        case .meal: mealHaptic.impactOccurred(intensity: T.mealHapticIntensity)
        case .closeCall: closeCallHaptic.impactOccurred()
        case .bounce: closeCallHaptic.impactOccurred(intensity: T.bounceHapticIntensity)
        case .sting: eatenNotification.notificationOccurred(.error)
        case .eaten:
            eatenHaptic.impactOccurred(intensity: 1)
            eatenNotification.notificationOccurred(.error)
        case .win: winNotification.notificationOccurred(.success)
        case .conquer:
            winNotification.notificationOccurred(.success)
            run(.sequence([.wait(forDuration: TimeInterval(T.conquerThumpDelay)), .run { [weak self] in
                #if DEBUG
                self?.noteHitch(.haptic, "conquer: heavy impact")
                #endif
                self?.eatenHaptic.impactOccurred(intensity: T.conquerThumpIntensity)
            }]))
        }
    }

    /// Camera scale: 1 at the start of a run, easing toward `minZoom` as the player grows.
    /// World y equals screen y at zoom 1; zooming out makes the water taller in world units.
    private var zoom: CGFloat = 1
    private var screenWaterBottom: CGFloat { T.waterBottomMargin }
    private var screenWaterTop: CGFloat { size.height - T.waterTopMargin }
    private var waterCenter: CGFloat { (screenWaterBottom + screenWaterTop) / 2 }
    private var waterBottom: CGFloat { waterCenter - (waterCenter - screenWaterBottom) / zoom }
    private var waterTop: CGFloat { waterCenter + (screenWaterTop - waterCenter) / zoom }
    /// Player movement is defined in screen points, so it feels the same at any zoom.
    private var playerSpeed: CGFloat { size.width / level.screenCrossSeconds / zoom }
    private var isHolding: Bool {
        #if DEBUG
        return simulationHolding ?? !holdTouches.isEmpty
        #else
        return !holdTouches.isEmpty
        #endif
    }
    private func playSound(_ effect: ArcadeAudio.Effect) {
        #if DEBUG
        if simulationHeadless { return }
        #endif
        audio.play(effect)
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.04, green: 0.15, blue: 0.32, alpha: 1)

        if !hasLayers {
            hasLayers = true
            backgroundLayer.zPosition = 0
            dimNode.zPosition = 5
            dimNode.alpha = 0
            fishLayer.zPosition = 10
            uiLayer.zPosition = 100
            addChild(backgroundLayer)
            addChild(dimNode)
            hazardLayer.zPosition = 8
            addChild(hazardLayer)
            addChild(fishLayer)
            addChild(uiLayer)
            uiLayer.addChild(messageNode)
            uiLayer.addChild(pauseButton)
            uiLayer.addChild(pauseMenu)
            uiLayer.addChild(levelIndicator)
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillResignActive),
                name: UIApplication.willResignActiveNotification, object: nil
            )
        }
        #if DEBUG
        hitchLog?.enterScene(self, hitchContext, view: view)
        #endif
        _ = audio // Warm normal gameplay audio; headless studies never create the player pool.
        prepareHaptics()
        if !isBuilt { build() }
    }

    static func keepsScreenAwake(_ phase: Phase) -> Bool { phase == .playing }

    override func willMove(from view: SKView) {
        // Leaving a level (even mid-play, as Skip leaves the tutorial): back to the maps, which sleep.
        UIApplication.shared.isIdleTimerDisabled = false
        #if DEBUG
        finishRunRecording("scene_closed")
        hitchLog?.leaveScene(self)
        #endif
        super.willMove(from: view)
    }

    private func build() {
        guard size.width > 1, size.height > 1 else { return }
        isBuilt = true
        layoutStatic()
        resetGame(startPlaying: false)
    }

    @objc private func appWillResignActive() {
        if phase == .playing { pauseRun() }
        holdTouches.removeAll()
        if let summary = metricAccumulator?.summary { enqueueMetricOperation { $0.checkpoint(summary) } }
        enqueueMetricOperation { $0.flush() }
    }

    // MARK: - Run setup

    private func resetGame(startPlaying: Bool) {
        observeMetrics(); finishMetrics("quit")
        #if DEBUG
        finishRunRecording("restart")
        #endif
        for node in nodes.values { node.removeFromParent() }
        nodes.removeAll()
        for stung in stungFish { stung.node.removeFromParent(); stung.zap.removeFromParent() }
        stungFish.removeAll()
        pendingLossResultAt = nil
        pendingConqueredExitAt = nil
        fish.removeAll()
        fishByID.removeAll()
        swallows.removeAll()
        hazardLayer.removeAllChildren()
        jellies.removeAll()
        encounterLeases.removeAll()
        forwardDistance = 0
        encounterNeighbors.removeAll()
        #if DEBUG
        recordedEncounterReleases.removeAll()
        mealLog.removeAll()
        debugBounces.removeAll()
        #endif
        nextFishID = 1
        aiMovementRNGs.removeAll()
        movementVariants.removeAll()
        mealsEaten = 0
        bounceRemaining = 0
        bounceCooldown = 0
        lossReason = "There was a bigger fish."
        winGlow?.removeFromParent()
        winGlow = nil
        dimNode.removeAllActions()
        dimNode.alpha = 0
        holdTouches.removeAll()
        timeScale = 1
        slowMoRemaining = 0
        simClock = 0
        frameAccumulator = 0
        simulationAccumulator = 0
        lastUpdate = nil
        zoom = 1

        world = WrappedWorld(width: size.width * level.worldScreens)
        spawnJellies()
        spawnKelp()
        spawnHooks()
        spawnEcosystem()
        lastCameraX = player.position.x
        capturePresentation()
        // A tutorial retry past its opening goes straight back in; its opening waits for your first touch.
        setPhase(startPlaying || (isTutorial && tutorialCheckpoint != .holdToRise) ? .playing : .ready)
        buildLevelIndicator()
        _ = render()
        // Now that your fish is drawn, the opening's arrows can sit by it.
        if isTutorial { followTutorialHint() }
    }

    private func spawnEcosystem() {
        let base = T.baseRadius
        let p = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: (waterBottom + waterTop) / 2), radius: base)
        p.velocity = CGVector(dx: playerSpeed, dy: 0)
        player = p
        add(p, style: .player)

        if isTutorial {
            startTutorial()
        } else if let plan = level.meetingPlan {
            spawnPlanned(plan)
        }
    }

    /// Each fish starts where its own free swim brings it across your path at its planned meeting.
    private func spawnPlanned(_ plan: MeetingPlan) {
        approachEnds.removeAll()
        waitingFish = plan.fish.filter { ($0.appearsAt ?? 0) > 0 }.sorted { $0.appearsAt! < $1.appearsAt! }
        for planned in plan.fish where (planned.appearsAt ?? 0) <= 0 { spawnPlannedFish(planned) }
    }

    /// Kelp Forest fish waiting off screen appear once you've come far enough.
    private func releaseWaitingFish() {
        while let next = waitingFish.first, let at = next.appearsAt, forwardDistance >= at {
            waitingFish.removeFirst()
            spawnPlannedFish(next)
        }
    }

    private func spawnPlannedFish(_ planned: PlannedFish) {
        let f = Fish(id: planned.id, isPlayer: false, position: planned.spawn, radius: planned.radius)
        nextFishID = max(nextFishID, planned.id + 1)
        f.heading = planned.startHeading
        f.cruiseSpeed = planned.cruiseSpeed
        f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
        f.facing = f.heading
        f.targetY = planned.spawn.y
        f.retargetTimer = planned.retargetTimer
        f.turnTimer = planned.turnTimer
        f.phase = planned.phase
        movementVariants[f.id] = planned.variant
        var styleGenerator = SeededGenerator(seed: planned.styleSeed)
        add(f, style: FishStyle.random(using: &styleGenerator))
        // Protected until you've passed its meeting, so the food race starts where you missed it.
        encounterLeases[f.id] = EncounterLease(home: planned.spawn,
            releaseDistance: planned.meetingDistance + size.width * T.freeEncounterReleaseScreens, index: planned.segment)
        if planned.appearsAt != nil {
            approachEnds[f.id] = (planned.meetingDistance + size.width * T.kelpApproachReleaseScreens, planned.spawn.y,
                                  simClock, planned.approach, planned.headOn ? -1 : 1)
        }
    }

    private func encounterProtected(_ id: Int) -> Bool {
        encounterLeases[id]?.isProtected(distance: forwardDistance) ?? false
    }

    private func add(_ f: Fish, style: FishStyle) {
        if !f.isPlayer { aiMovementRNGs[f.id] = movementGenerator(for: f.id) }
        fish.append(f)
        fishByID[f.id] = f
        let node = FishNode(style: style, isPlayer: f.isPlayer, tailPhase: CGFloat(f.id) * 1.7)
        node.zPosition = f.isPlayer ? 30 : 1 + CGFloat(f.id) * 0.5
        if headlamp != nil && T.anglerLures && !f.isPlayer { node.addChild(Self.anglerLure(phase: CGFloat(f.id))) }
        nodes[f.id] = node
        fishLayer.addChild(node)
    }

    // MARK: - Phases

    private func setPhase(_ newPhase: Phase) {
        // Awake only while you're playing: the card before a level, the pause menu, the result, and the maps let the
        // phone sleep as it normally would. Only a scene on screen decides: headless runs (tests and the planner's
        // studies) leave the phone alone.
        if view != nil { UIApplication.shared.isIdleTimerDisabled = Self.keepsScreenAwake(newPhase) }
        if newPhase != .won && newPhase != .lost { accessibilityElements = nil }
        if newPhase == .ready || newPhase == .paused || phase == .ready || phase == .paused {
            frameAccumulator = 0
            simulationAccumulator = 0
            if newPhase == .ready || newPhase == .paused || phase == .paused { lastUpdate = nil }
            capturePresentation()
        }
        #if DEBUG
        switch (phase, newPhase) {
        case (_, .paused): noteHitch(.pause)
        case (.paused, .playing): noteHitch(.resume)
        default: noteHitch(.phase, newPhase.name)
        }
        #endif
        if (newPhase == .paused) != (phase == .paused) { onPause?(newPhase == .paused) }
        phase = newPhase
        #if DEBUG
        if view != nil { hitchLog?.updateScene(self, hitchContext) }
        #endif
        pauseButton.isHidden = newPhase != .playing
        pauseMenu.isHidden = newPhase != .paused
        // The pause menu names the level itself.
        levelIndicator.isHidden = newPhase == .paused
        if newPhase == .paused {
            refreshSoundToggles()
            configurePauseAccessibility()
        }
        switch newPhase {
        case .ready:
            resultPanel = nil
            if isTutorial {
                // No card: the finger shows you, and your first touch starts it and lifts you.
                hideMessage()
                if let caption = tutorialCaptionPending {
                    tutorialCaptionPending = nil
                    showTutorialCaption(caption)
                }
            } else if replaying {
                // Again straight after playing it: no card, just the prompt (your first touch starts it, as ever).
                messageNode.position = CGPoint(x: size.width * 0.63, y: size.height / 2)
                showStartPrompt()
            } else {
                // The level and its pips; a world's first level also says what's new in it, until it's beaten.
                messageNode.position = CGPoint(x: size.width * 0.63, y: size.height / 2)
                let introduces = levelIndex == 0 && hasCleared?(0) != true
                showMessage(levelTitle, lines: introduces ? arcadeWorld.rules : [],
                            progress: worldProgress(won: false).map { WorldProgressStrip(progress: $0, next: levelIndex, captioned: false) })
            }
        case .playing, .paused:
            hideMessage()
        case .won:
            if isTutorial {
                // A moment to enjoy the catch, then its closing line, then off to the map.
                showTutorialFinale()
                pendingConqueredExitAt = realClock + T.tutorialFinaleSeconds
            } else if leavesForConqueredScreen {
                pendingConqueredExitAt = realClock + T.conqueredExitDelay
            } else {
                showResult(passed: true)
            }
        case .lost:
            // The tutorial's line steps aside for the Retry card (Retry brings it back).
            if isTutorial { hideTutorialCaption() }
            if pendingLossResultAt == nil { showResult(passed: false) }
        }
    }

    private var plannerName: String? {
        #if DEBUG
        return plannerLevel?.meetingPlan.map { "\($0.spec.name) planner" }
        #else
        return nil
        #endif
    }
    private var levelTitle: String { plannerName ?? arcadeWorld.levelTitles[levelIndex] }

    /// How far through its world's run this level is (nil for the tutorial and Xcode-only test levels). `won` counts
    /// this level as cleared, as a practice run's win isn't saved.
    private func worldProgress(won: Bool) -> WorldProgress? {
        guard !isTutorial, plannerName == nil else { return nil }
        let level = levelIndex
        return WorldProgress(world: arcadeWorld, level: level) { index in
            (won && index == level) || hasCleared?(index) == true
        }
    }

    private func showResult(passed: Bool) {
        holdTouches.removeAll()
        messageNode.removeAllActions()
        messageNode.removeAllChildren()
        messageNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let detail: String
        if !passed {
            detail = lossReason
        } else if isWorldFinale {
            detail = "\(arcadeWorld.title) conquered!"
        } else if isFinalLevel {
            detail = plannerName.map { "\($0) complete!" }
                ?? (ArcadeWorld.isDeepEnd(levelIndex) ? "The Deep End conquered!" : "\(arcadeWorld.title) complete!")
        } else {
            detail = "\(levelTitle) complete!"
        }
        // After a win, the world's pips: this level's fills in if it's a first clear, and the next one pulses.
        var strip: WorldProgressStrip?
        if passed, let progress = worldProgress(won: true) {
            let next = progress.run.contains(levelIndex + 1) ? levelIndex + 1 : nil
            strip = WorldProgressStrip(progress: progress, next: next, earned: clearedBeforeRun ? nil : levelIndex)
            if !clearedBeforeRun { strip?.playEarned(levelIndex, after: 0.85) }
        }
        // In the tutorial, being eaten offers one thing: try again, at once (its Skip button leaves).
        #if DEBUG
        noteHitch(.result, passed ? "won" : "lost")
        #endif
        let panel = ArcadeResultPanel(size: size, passed: passed, hasNext: !isFinalLevel && !isWorldFinale, detail: detail,
                                      progress: strip, retryOnly: isTutorial)
        panel.onSelect = { [weak self] action in self?.selectResult(action) }
        messageNode.addChild(panel)
        resultPanel = panel
        messageNode.alpha = 0
        messageNode.run(.sequence([.wait(forDuration: passed ? 0.5 : 0.2), .fadeIn(withDuration: 0.2)]))
        configureResultAccessibility(panel)
    }

    private func configureResultAccessibility(_ panel: ArcadeResultPanel) {
        guard let view else { return }
        view.isAccessibilityElement = false
        isAccessibilityElement = false
        // SKView exposes its scene as the accessibility container.
        accessibilityElements = panel.controls.map { control in
            let element = ArcadeResultAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = control.action.title
            element.accessibilityTraits = .button
            let lower = convertPoint(toView: panel.convert(control.frame.origin, to: self))
            let upper = convertPoint(toView: panel.convert(CGPoint(x: control.frame.maxX, y: control.frame.maxY), to: self))
            let frame = CGRect(x: min(lower.x, upper.x), y: min(lower.y, upper.y),
                               width: abs(upper.x - lower.x), height: abs(upper.y - lower.y))
            element.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(frame, in: view)
            element.activate = { [weak self, weak panel] in
                guard let self, self.resultPanel === panel,
                      self.phase == .won || self.phase == .lost,
                      self.realClock - self.endedAt >= T.restartDelay else { return false }
                self.selectResult(control.action)
                return true
            }
            return element
        }
    }

    private func selectResult(_ action: ArcadeResultAction) {
        switch action {
        case .nextLevel:
            guard phase == .won, !isFinalLevel, !isWorldFinale else { return }
            if levelNeedsUnlock?(levelIndex + 1) == true {
                #if DEBUG
                finishRunRecording("level_map")
                #endif
                leftForUnlock = true
                onExit?()
                return
            }
            levelIndex += 1
            layoutStatic()
            resetGame(startPlaying: false)
        case .playAgain, .tryAgain:
            replayLevel()
        case .levels, .world:
            #if DEBUG
            finishRunRecording("level_map")
            #endif
            onExit?()
        }
    }

    /// The same level again (Retry, Play again, or Restart, by touch or VoiceOver): no card first, just the prompt.
    private func replayLevel() {
        replaying = true
        resetGame(startPlaying: false)
    }

    private func startRun() {
        prepareHaptics()
        if arcadeWorld.hasJellies && showsJellyLesson {
            onJellyLesson?()
            showsJellyLesson = false
        }
        simClock = 0
        replaying = false
        clearedBeforeRun = hasCleared?(levelIndex) ?? false
        // A world still being prototyped (Xcode builds only) never reports: the stats server knows only the campaign's
        // worlds and death causes, and drops a whole batch over one it doesn't.
        var collects = analytics?.enabled == true && !isTutorial && ArcadeWorld.campaign.contains(arcadeWorld)
        #if DEBUG
        collects = collects && !simulationHeadless && !debugPracticeRun && ArcadePlaytest.selection == nil
        #endif
        if collects {
            metricAccumulator = ArcadeMetricAccumulator()
            fatalMetrics = nil; metricDeathCause = "none"
            let context = metricContext, count = arcadeWorld.levelCount
            let cleared = hasCleared?(levelIndex) ?? false
            enqueueMetricOperation { $0.start(context, worldLevelCount: count, alreadyCleared: cleared) }
            observeMetrics()
        }
        setPhase(.playing)
        #if DEBUG
        startRunRecording()
        #endif
    }

    private func pauseRun() {
        buildPauseMenu()
        setPhase(.paused)
        holdTouches.removeAll()
        observeMetrics()
        if let summary = metricAccumulator?.summary { enqueueMetricOperation { $0.checkpoint(summary) } }
        #if DEBUG
        recordRunEvent("pause")
        recordRunSnapshot(force: true)
        runRecorder?.checkpoint()
        #endif
    }

    private func win() {
        observeMetrics(); finishMetrics("win")
        #if DEBUG
        finishRunRecording("won")
        if !isTutorial && onClear != nil { noteHitch(.save, "level cleared") }
        #endif
        if !isTutorial { onClear?(levelIndex, Double(simClock)) }
        playSound(.clear)
        // Conquering a world (its first level-10 win) is felt a little more than any other win.
        buzz(leavesForConqueredScreen ? .conquer : .win)
        setPhase(.won)
        endedAt = realClock
        slowMoFactor = T.winSlowFactor
        slowMoRemaining = T.winSlowDuration
        dimNode.run(.fadeAlpha(to: 0.35, duration: 0.6))

        let glow = SKShapeNode(circleOfRadius: player.radius * zoom * 1.8)
        glow.strokeColor = SKColor(white: 1, alpha: 0.8)
        glow.fillColor = .clear
        glow.lineWidth = 3
        // Over your dorsal fin (30 less 1) and under your body (30). At the fin's own depth it could draw either way:
        // the scene ignores sibling order.
        glow.zPosition = 29.25
        glow.run(.repeatForever(.sequence([
            .group([.scale(to: 1.6, duration: 1.0), .fadeOut(withDuration: 1.0)]),
            .scale(to: 1, duration: 0),
            .fadeAlpha(to: 0.8, duration: 0),
        ])))
        fishLayer.addChild(glow)
        winGlow = glow
    }

    /// `soundsAtResult`: a delayed result (a sting) sounds the loss when it appears; a hook has sounded it already.
    private func lose(resultDelay: CGFloat = 0, soundsAtResult: Bool = true) {
        if resultDelay > 0 { pendingLossResultAt = realClock + resultDelay }
        lossSoundsAtResult = soundsAtResult
        finishMetrics("death")
        #if DEBUG
        finishRunRecording("lost", fields: ["reason": lossReason])
        noteHitch(.death, resultDelay > 0 ? (reel != nil ? "hooked" : "stung") : "eaten")
        #endif
        // A delayed result (a sting) sounds the loss when the result appears, after the zap.
        if resultDelay == 0 { playSound(.lose) }
        setPhase(.lost)
        endedAt = realClock
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasHolding = isHolding
        defer {
            #if DEBUG
            if isHolding != wasHolding { recordRunEvent("input", fields: ["holding": isHolding]) }
            #endif
        }
        for touch in touches {
            let p = touch.location(in: self)
            switch phase {
            case .ready:
                startRun()
                holdTouches.insert(touch)
            case .playing:
                if hypot(p.x - pauseButton.position.x, p.y - pauseButton.position.y) < 36 {
                    pauseRun()
                } else {
                    holdTouches.insert(touch)
                }
            case .paused:
                if resumeButton.hitFrame.insetBy(dx: -8, dy: -4).contains(p) {
                    setPhase(.playing)
                    #if DEBUG
                    recordRunEvent("resume")
                    #endif
                } else if restartButton.hitFrame.insetBy(dx: -8, dy: -4).contains(p) {
                    replayLevel()
                } else if effectsButton.hitFrame.insetBy(dx: -8, dy: -4).contains(p) {
                    toggleSound(effects: true)
                } else if musicButton.hitFrame.insetBy(dx: -8, dy: -4).contains(p) {
                    toggleSound(effects: false)
                } else if vibrationButton.hitFrame.insetBy(dx: -8, dy: -4).contains(p) {
                    toggleVibration()
                } else if mapButton.hitFrame.insetBy(dx: -8, dy: -4).contains(p) {
                    #if DEBUG
                    finishRunRecording("level_map")
                    #endif
                    onExit?()
                    return
                }
            case .won, .lost:
                if realClock - endedAt >= T.restartDelay, let resultPanel {
                    resultPanel.handleTap(at: resultPanel.convert(p, from: self))
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasHolding = isHolding
        holdTouches.subtract(touches)
        #if DEBUG
        if isHolding != wasHolding { recordRunEvent("input", fields: ["holding": isHolding]) }
        #endif
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasHolding = isHolding
        holdTouches.subtract(touches)
        #if DEBUG
        if isHolding != wasHolding { recordRunEvent("input", fields: ["holding": isHolding]) }
        #endif
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt else { return }
        #if DEBUG
        // Every frame in every phase, timed from SpriteKit's own clock (the game's `lastUpdate` restarts at each pause).
        hitchLog?.frameBegan(self, timestamp: currentTime)
        defer { hitchLog?.frameEnded(self) }
        if let previewResult, !didPreviewResult {
            didPreviewResult = true
            setPhase(previewResult ? .won : .lost)
            endedAt = realClock
        }
        #endif
        let frameElapsed = max(lastUpdate.map { CGFloat(currentTime - $0) } ?? 0, 0)
        let realDt = min(frameElapsed, T.maximumFrameElapsed)
        lastUpdate = currentTime
        advanceFrame(realDt)

        let presentation = render()
        let cameraDelta = world.delta(from: lastCameraX, to: presentation.cameraX) * presentation.zoom
        lastCameraX = presentation.cameraX
        updateSpecks(realDt: phase == .paused ? 0 : realDt, cameraDelta: cameraDelta)
        updateSunRays(cameraDelta: cameraDelta, time: realClock)
    }

    /// Display frames only contribute elapsed time. Both real-time slow motion and
    /// gameplay consume fixed ticks, so batching frames cannot change the ecology.
    private func advanceFrame(_ elapsed: CGFloat, beforeStep: (() -> Void)? = nil) {
        let step = T.simulationStep
        let epsilon: CGFloat = 1e-10
        frameAccumulator += min(max(elapsed, 0), T.maximumFrameElapsed)
        while frameAccumulator + epsilon >= step {
            frameAccumulator = max(0, frameAccumulator - step)
            realClock += step
            if let at = pendingLossResultAt, realClock >= at {
                pendingLossResultAt = nil
                if phase == .lost {
                    if lossSoundsAtResult { playSound(.lose) }
                    showResult(passed: false)
                }
            }
            if let at = pendingConqueredExitAt, realClock >= at {
                pendingConqueredExitAt = nil
                if phase == .won { selectResult(.world) }
            }
            guard phase != .ready && phase != .paused else { continue }
            if slowMoRemaining > 0 {
                slowMoRemaining = max(0, slowMoRemaining - step)
                timeScale = slowMoFactor
            } else {
                timeScale = min(1, timeScale + step * T.slowMotionRecoveryRate)
            }
            simulationAccumulator += step * timeScale
            while simulationAccumulator + epsilon >= step {
                simulationAccumulator = max(0, simulationAccumulator - step)
                beforeStep?()
                capturePresentation()
                simulate(step)
            }
        }
    }

    private func simulate(_ dt: CGFloat) {
        simClock += dt
        updateZoom(dt)
        let previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
        // All protected swimmers steer from the same snapshot, not update-order-dependent positions.
        encounterNeighbors = level.meetingPlan == nil ? [] : fish.compactMap {
            !$0.isPlayer && $0.state == .swimming
                ? EncounterNeighbor(id: $0.id, position: $0.position, velocity: $0.velocity, radius: $0.radius) : nil
        }
        for f in fish where f.isAlive {
            if f.isPlayer { movePlayer(f, dt) } else { moveAI(f, dt) }
        }
        releaseWaitingFish()
        #if DEBUG
        for (id, lease) in encounterLeases where !lease.isProtected(distance: forwardDistance) {
            if recordedEncounterReleases.insert(id).inserted {
                recordRunEvent("encounter_release", fields: ["encounter": lease.index + 1, "fishID": id,
                    "forwardDistance": forwardDistance, "releaseDistance": lease.releaseDistance])
            }
        }
        #endif
        if phase == .playing { updateJellies(dt, previousFish: previous) }
        if phase == .playing { updateHooks() }
        advanceSwallows(dt)
        advanceGrowth(dt)
        advanceTutorial()
        if phase == .playing {
            resolveCollisions()
            if hasWon { win() }
            #if DEBUG
            recordRunSnapshot()
            #endif
        }
    }

    private func movePlayer(_ p: Fish, _ dt: CGFloat) {
        // Keep the winner in place; rendering and the victory ring continue animating.
        guard phase != .won else { p.velocity = .zero; return }
        bounceRemaining = max(0, bounceRemaining - dt)
        bounceCooldown = max(0, bounceCooldown - dt)
        var motion = T.motion
        if bounceRemaining > 0 {
            motion.maxRiseSpeed = T.jellyBounceSpeed
            motion.fallAcceleration *= 0.35
        }
        if inKelp(p.position) {
            motion.riseAcceleration *= T.kelpDrag
            motion.fallAcceleration *= T.kelpDrag
            motion.maxRiseSpeed *= T.kelpDrag
            motion.maxFallSpeed *= T.kelpDrag
        }
        let (y, vy) = tutorialHoldsYou ? (heldTutorialY(p, dt), 0) : PlayerMotion.step(
            y: p.position.y, vy: p.velocity.dy, holding: isHolding, dt: dt,
            minY: waterBottom + p.radius * 0.95, maxY: waterTop - p.radius * 0.95,
            zoom: zoom, tuning: motion
        )
        p.velocity = CGVector(dx: playerSpeed, dy: vy)
        forwardDistance += max(0, playerSpeed * dt)
        metricAccumulator?.advance(seconds: Double(simClock), circuits: Double(forwardDistance / world.width))
        p.position = CGPoint(x: world.wrap(p.position.x + playerSpeed * dt), y: y)
        p.facing = 1
    }

    private func updateZoom(_ dt: CGFloat) {
        guard player.isAlive else { return }
        if isTutorial {
            zoom = T.tutorialZoom
            return
        }
        let growth = player.radius / (T.baseRadius * T.zoomStartSize)
        let target = growth > 1 ? max(T.minZoom, pow(1 / growth, T.zoomExponent)) : 1
        zoom += (target - zoom) * min(1, dt * T.zoomEase)
    }

    /// How fast a fish roaming free rises and dives (world points a second): kept the same on screen as the camera zooms
    /// out where `GameTuning.zoomedRoamingWorlds` says.
    private var roamingVerticalSpeed: CGFloat {
        level.aiVerticalSpeed / (T.zoomedRoamingWorlds.contains(arcadeWorld) ? zoom : 1)
    }

    private func moveAI(_ f: Fish, _ dt: CGFloat) {
        if let scripted = tutorialPaths[f.id] {
            moveScripted(f, scripted, dt)
            return
        }
        if let swim = tutorialSwims[f.id] {
            moveTutorialSwimmer(f, swim, dt)
            return
        }
        if let approach = approachEnds[f.id] {
            // Held to its line, so nothing it passes on the way can push it off its meeting.
            if forwardDistance < approach.until {
                guard let path = approach.path else {
                    f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
                    f.position = CGPoint(x: world.wrap(f.position.x + f.velocity.dx * dt), y: approach.y)
                    f.facing = f.heading
                    return
                }
                let offset = path.offset(at: simClock - approach.start, heading: approach.heading, speed: f.cruiseSpeed)
                let next = CGPoint(x: world.wrap(path.meeting.x + offset.dx), y: path.meeting.y + offset.dy)
                f.velocity = CGVector(dx: world.delta(from: f.position.x, to: next.x) / dt, dy: (next.y - f.position.y) / dt)
                f.position = next
                // A turning fish shows its tail, then swings round to face you.
                f.heading = f.velocity.dx >= 0 ? 1 : -1
                f.facing += (f.heading - f.facing) * min(1, dt * T.freeEncounterFacingRate)
                return
            }
            approachEnds[f.id] = nil
            f.targetY = f.position.y
        }
        var movementRNG = aiMovementRNGs[f.id] ?? movementGenerator(for: f.id)
        defer { aiMovementRNGs[f.id] = movementRNG }
        let minY = waterBottom + f.radius
        let maxY = max(minY, waterTop - f.radius)
        let steered = FreeSwim.steer(f, dt: dt, clock: simClock, minY: minY, maxY: maxY,
            verticalSpeed: roamingVerticalSpeed, rng: &movementRNG)
        var vx = steered.dx, vy = steered.dy

        if encounterProtected(f.id) {
            // A planned fish only steers around other planned fish you haven't met, and only where you can see it;
            // anyone else gives way to it.
            for other in encounterNeighbors where other.id != f.id
                && encounterProtected(other.id) && plannedContactVisible(f.position.x) {
                if let separation = EncounterSteering.separation(
                    relative: CGVector(dx: world.delta(from: other.position.x, to: f.position.x), dy: f.position.y - other.position.y),
                    velocity: CGVector(dx: vx - other.velocity.dx, dy: vy - other.velocity.dy),
                    reach: (f.radius + other.radius) * T.collisionScale + T.encounterSeparationPadding,
                    stableDirection: f.id < other.id ? -1 : 1) {
                    vx += separation.dx * min(1, dt * 4)
                    vy += separation.dy * min(1, dt * 4)
                }
            }
        }
        if plannedFishMeetsJellies(f), let avoidance = bloomAvoidance(for: f, velocity: CGVector(dx: vx, dy: vy)) {
            let steered = JellySwim.steer(f, velocity: CGVector(dx: vx, dy: vy), toward: avoidance, dt: dt, minY: minY, maxY: maxY)
            vx = steered.dx
            vy = steered.dy
        }

        FreeSwim.integrate(f, velocity: CGVector(dx: vx, dy: vy), dt: dt, minY: minY, maxY: maxY, world: world)
        // Facing follows horizontal velocity, so turns read as a smooth flip through side-on.
        let swimX = f.velocity.dx
        let direction: CGFloat = abs(swimX) > 2 ? (swimX >= 0 ? 1 : -1) : f.heading
        f.facing += (direction - f.facing) * min(1, dt * T.freeEncounterFacingRate)
    }

    // MARK: - Kelp Forest

    private func spawnKelp() {
        silhouetteShade.removeAll()
        for bed in kelpBeds { bed.back.removeFromParent(); bed.front.removeFromParent() }
        kelpBeds = (level.meetingPlan?.kelp ?? []).enumerated().map { index, bed in
            // Drawn from below the bottom of the screen to just above its top.
            let height = size.height + T.kelpCanopy - T.kelpRootY
            let back = KelpNode(width: bed.halfWidth * 2, height: height, seed: UInt64(index), front: false)
            let front = KelpNode(width: bed.halfWidth * 2, height: height, seed: UInt64(index) &+ 101, front: true)
            // Back fronds behind every part of every fish; front fronds in front of all of the other fish
            // (up to 1 + 0.5 per id, plus their parts up to +4), so those inside show as silhouettes, but behind
            // all of you (30, tail at -2).
            back.zPosition = -3
            front.zPosition = 26
            fishLayer.addChild(back)
            fishLayer.addChild(front)
            return (bed, back, front)
        }
    }

    /// In kelp, a fish is one solid dark shape, eye and all, so you judge it by its outline alone. It fades in as
    /// the fish crosses the kelp's edge: `shade` 0 is its own colors, 1 the silhouette.
    /// Each shape keeps its own colors in its `userData` while shaded, so they go wherever the shape goes.
    private func setSilhouette(_ node: SKNode, _ shade: CGFloat) {
        for child in node.children {
            if let shape = child as? SKShapeNode {
                let saved = shape.userData?[Self.ownColorsKey] as? [SKColor]
                let original = saved ?? [shape.fillColor, shape.strokeColor]
                if shade > 0 {
                    if saved == nil {
                        let data = shape.userData ?? NSMutableDictionary()
                        data[Self.ownColorsKey] = original
                        shape.userData = data
                    }
                } else {
                    shape.userData?.removeObject(forKey: Self.ownColorsKey)
                }
                shape.fillColor = Self.shaded(original[0], shade)
                shape.strokeColor = Self.shaded(original[1], shade)
            }
            setSilhouette(child, shade)
        }
    }
    private static let ownColorsKey = "kelpOwnColors"

    /// `color` darkened `shade` of the way to the silhouette color, keeping its own transparency, so the whole fish
    /// darkens together and ends as one dark shape.
    private static func shaded(_ color: SKColor, _ shade: CGFloat) -> SKColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var toRed: CGFloat = 0, toGreen: CGFloat = 0, toBlue: CGFloat = 0, toAlpha: CGFloat = 0
        guard shade > 0, color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0,
              T.kelpSilhouette.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha) else { return color }
        return SKColor(red: red + (toRed - red) * shade, green: green + (toGreen - green) * shade,
                       blue: blue + (toBlue - blue) * shade, alpha: alpha)
    }

    /// How far into the kelp a fish is: 0 a body's width outside every column, 1/2 centered on an edge, 1 a body's
    /// width inside.
    private func kelpShade(_ position: CGPoint, radius: CGFloat) -> CGFloat {
        let depth = kelpBeds.map { $0.bed.halfWidth - abs(world.delta(from: $0.bed.x, to: position.x)) }.max() ?? -.infinity
        return ((depth + radius) / (2 * max(radius, 1))).clamped(0, 1)
    }

    private func layoutHeadlamp() {
        headlamp?.removeFromParent()
        headlamp = nil
        guard arcadeWorld == .midnightZone else { return }
        let node = SKSpriteNode(texture: Self.headlampTexture)
        node.blendMode = .multiply
        // Big enough that the dark covers the screen at any angle, with the beam reaching as far as tuned.
        let side = 2 * size.width * T.headlampReach / Self.headlampTextureReach
        node.size = CGSize(width: side, height: side)
        // Under all of your own fish (the fish layer's 10, plus 30, less 2 for its tail: 38) and over every other
        // fish's highest part (10, plus 1 + half its ID, plus 3 for its eye: 31.5 with Midnight Zone's most fish).
        node.zPosition = Self.headlampDepth
        addChild(node)
        headlamp = node
    }

    /// An anglerfish lure at the fish's reference size, facing right: a stalk from its forehead, under the dark so
    /// it only shows in your beam, and at its tip a light over the dark, held to one size whatever the fish's.
    private static let anglerLureName = "anglerLure", anglerLightName = "anglerLight"
    private static func anglerLure(phase: CGFloat) -> SKNode {
        let r = FishNode.referenceRadius, tip = CGPoint(x: 1.4 * r, y: 1.25 * r)
        let rig = SKNode()
        rig.name = anglerLureName
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.75 * r, y: 0.72 * r))
        path.addQuadCurve(to: tip, control: CGPoint(x: 1.0 * r, y: 1.6 * r))
        let stalk = SKShapeNode(path: path)
        stalk.strokeColor = SKColor(white: 0.8, alpha: 0.9)
        stalk.lineWidth = 2
        stalk.lineCap = .round
        stalk.zPosition = 2
        rig.addChild(stalk)
        let light = SKNode()
        light.name = anglerLightName
        light.position = tip
        // Over the dark and every fish: the fish layer's 10, plus this fish's at least 1, plus 30.
        light.zPosition = 30
        let halo = SKSpriteNode(texture: lureTexture, color: T.lureColor, size: CGSize(width: T.lureHalo * 2, height: T.lureHalo * 2))
        halo.colorBlendFactor = 1
        halo.blendMode = .add
        halo.alpha = 0.55
        let core = SKSpriteNode(texture: lureTexture, color: .white, size: CGSize(width: T.lureCore * 2, height: T.lureCore * 2))
        // The bright core over its halo: the scene ignores sibling order.
        core.zPosition = 0.1
        light.addChild(halo)
        light.addChild(core)
        light.run(.sequence([.wait(forDuration: Double(phase.truncatingRemainder(dividingBy: 7)) * 0.13), .repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8),
        ]))]))
        rig.addChild(light)
        return rig
    }
    private static let lureTexture: SKTexture = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            let colors = [SKColor.white.cgColor, SKColor.white.withAlphaComponent(0).cgColor] as CFArray
            context.cgContext.drawRadialGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!,
                startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }
        return SKTexture(image: image)
    }()

    /// Where the dark sits among the fish (see `layoutHeadlamp`).
    static let headlampDepth: CGFloat = 36
    /// How far the beam reaches across the headlamp texture, as a share of its half-width; the rest is dark margin.
    private static let headlampTextureReach: CGFloat = 0.55
    /// The dark everywhere, a soft-edged beam pointing right from the center fading with distance, and a glow
    /// around the center. Opaque, for multiplying.
    private static let headlampTexture: SKTexture = {
        let side: CGFloat = 1024, center = CGPoint(x: side / 2, y: side / 2), reach = side / 2 * headlampTextureReach
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            T.midnightDark.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let light = SKColor(red: 1, green: 0.96, blue: 0.86, alpha: 1)
            func fading(_ alpha: CGFloat, holdUntil: CGFloat) -> CGGradient {
                CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [light.withAlphaComponent(alpha).cgColor, light.withAlphaComponent(alpha).cgColor,
                                    light.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, holdUntil, 1])!
            }
            // Layered wedges, the widest drawn as faintly as the narrowest, so the beam is brightest down its middle
            // and soft at its edges.
            let layers = 10
            for layer in 0..<layers {
                let half = T.headlampHalfAngle * (0.55 + 0.8 * CGFloat(layer) / CGFloat(layers - 1))
                let wedge = CGMutablePath()
                wedge.move(to: center)
                wedge.addArc(center: center, radius: reach * 1.05, startAngle: -half, endAngle: half, clockwise: false)
                wedge.closeSubpath()
                cg.saveGState()
                cg.addPath(wedge)
                cg.clip()
                cg.drawRadialGradient(fading(0.17, holdUntil: 0.6), startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: reach, options: [])
                cg.restoreGState()
            }
            cg.drawRadialGradient(fading(0.8, holdUntil: 0.35), startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: reach * T.headlampGlow, options: [])
        }
        return SKTexture(image: image)
    }()

    // MARK: - Tutorial

    /// The beat playing, the one a retry starts from, and when it started.
    private var tutorialBeat: ArcadeTutorial.Beat = .holdToRise
    private var tutorialCheckpoint: ArcadeTutorial.Beat = .holdToRise
    private var tutorialBeatStart: CGFloat = 0
    /// The beat's fish, by the part each plays.
    private var tutorialMeal: Int?
    private var tutorialBigFish: Int?
    private var tutorialMissedFish: Int?
    private var tutorialMissedMeals: [Int] = []
    private var tutorialMissedLane: CGFloat = 0.8
    private var tutorialWall: [Int] = []
    /// The wall's fish size, the two meals that make you big enough for it, and the wall fish you're eating your way through.
    private var tutorialWallSize: CGFloat = 0
    private var tutorialWallMeals: [Int] = []
    private var tutorialWallBreach: Int?
    /// Fish swimming freely as in a level (the last beat's), and how each swims.
    private var tutorialSwims: [Int: TutorialSwim] = [:]
    /// The opening's finger, your lowest while it asks you to rise, your highest since letting go, and when the finger
    /// shows again.
    private lazy var tutorialHint = TutorialHint(spot: CGPoint(x: size.width * T.tutorialFingerSpot.x, y: size.height * T.tutorialFingerSpot.y))
    private var tutorialLowest: CGFloat?
    private var tutorialPeak: CGFloat = 0
    private var tutorialHintAt: CGFloat = 0
    /// Whether the beat's glowing meal went into you (rather than swimming off).
    private var tutorialMealWasEaten = false
    /// When the next beat starts, after a breath, and when the missed fish next comes round.
    private var tutorialNextBeatAt: CGFloat?
    private var tutorialComesRoundAt: CGFloat?
    /// Fish on a scripted swim: the path, when it started, and whether to take the fish away at its end.
    private var tutorialPaths: [Int: (path: TutorialPath, start: CGFloat, leaves: Bool)] = [:]
    private let tutorialCaption = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let tutorialCaptionPill = SKShapeNode()
    /// A beat's line, shown once you're playing (not behind the card before the first tap).
    private var tutorialCaptionPending: String?

    /// While held, you glide down low and stay there, out of the way of the race just under the line at the top.
    private func heldTutorialY(_ p: Fish, _ dt: CGFloat) -> CGFloat {
        let target = waterBottom + T.tutorialHeldShare * (waterTop - waterBottom), most = T.tutorialHeldGlide * dt
        return p.position.y + ((target - p.position.y) * min(1, dt * 2.5)).clamped(-most, most)
    }

    /// The opening's arrows stay by your fish.
    private func followTutorialHint() {
        guard let node = nodes[player.id], let parent = node.parent else { return }
        tutorialHint.follow(fish: parent.convert(node.position, to: uiLayer), radius: player.radius * zoom)
    }

    /// While the fish you missed eats, you're held (still swimming on), so you watch rather than eat its meals.
    private var tutorialHoldsYou: Bool { isTutorial && phase == .playing && tutorialBeat == .missedFishEats && tutorialNextBeatAt == nil }

    /// How far up the water a height is, as on screen: 0 the bottom, 1 the top.
    private func waterShare(_ y: CGFloat) -> CGFloat { (y - waterBottom) / max(1, waterTop - waterBottom) }

    /// Starts the tutorial (or a retry) from its checkpoint, with you the size the earlier beats made you.
    private func startTutorial() {
        if tutorialCheckpoint == .holdToRise { analytics?.tutorial(.started) }
        tutorialPaths.removeAll()
        tutorialMeal = nil; tutorialBigFish = nil; tutorialMissedFish = nil; tutorialMissedMeals = []
        tutorialWall = []; tutorialWallBreach = nil; tutorialWallMeals = []; tutorialSwims = [:]
        tutorialNextBeatAt = nil
        tutorialComesRoundAt = nil
        tutorialCaptionPending = nil
        tutorialLowest = nil
        if tutorialHint.parent == nil {
            tutorialHint.zPosition = 6
            uiLayer.addChild(tutorialHint)
        }
        tutorialHint.hide()
        player.radius = ArcadeTutorial.radius(startingAt: tutorialCheckpoint)
        player.targetRadius = player.radius
        if tutorialCaption.parent == nil {
            tutorialCaption.fontSize = T.tutorialCaptionSize
            tutorialCaption.fontColor = .white
            tutorialCaption.verticalAlignmentMode = .center
            tutorialCaptionPill.fillColor = SKColor(white: 0, alpha: 0.3)
            tutorialCaptionPill.strokeColor = .clear
            tutorialCaptionPill.zPosition = -1
            tutorialCaption.addChild(tutorialCaptionPill)
            uiLayer.addChild(tutorialCaption)
        }
        tutorialCaption.position = CGPoint(x: size.width / 2, y: size.height - 30 - T.tutorialCaptionSize / 2)
        tutorialCaption.removeAllActions()
        tutorialCaption.alpha = 0
        beginTutorialBeat(tutorialCheckpoint)
    }

    private func beginTutorialBeat(_ beat: ArcadeTutorial.Beat) {
        tutorialBeat = beat
        tutorialCheckpoint = beat.checkpoint
        tutorialBeatStart = simClock
        tutorialNextBeatAt = nil
        #if DEBUG
        if view != nil { hitchLog?.updateScene(self, hitchContext) }
        #endif
        let lane = waterShare(player.position.y).clamped(0.25, 0.75)
        switch beat {
        case .holdToRise:
            tutorialCaptionPending = beat.caption
            tutorialLowest = nil
            tutorialHint.show(.hold)
            tutorialHintAt = simClock + T.tutorialHintSeconds
        case .letGoToFall:
            tutorialCaptionPending = beat.caption
            tutorialPeak = player.position.y
            tutorialHint.show(.letGo)
            tutorialHintAt = simClock + T.tutorialHintSeconds
        case .eatSmaller:
            // Above you, so the first thing you do is hold to rise.
            tutorialMeal = spawnTutorialFish(T.tutorialFirstMeal, path: .headOn(share: 0.7, crossing: T.tutorialMealCrossing), glows: true)
            tutorialCaptionPending = beat.caption
        case .dodgeBigger:
            tutorialBigFish = spawnTutorialFish(T.tutorialBigFish, path: .headOn(share: lane, crossing: T.tutorialBigFishCrossing))
            tutorialCaptionPending = beat.caption
        case .missedFishEats:
            // Just under the line at the top, so you can read it and watch while you hold low. Its two little meals
            // swim ahead of it (they set off in `advanceTutorial`), and it catches them as it goes by you.
            tutorialMissedLane = T.tutorialRaceLane
            tutorialMissedMeals = []
            // Up as soon as you're held, so you've read it by the time the fish come in.
            tutorialCaptionPending = beat.caption
        case .catchItBack:
            tutorialCaptionPending = beat.caption
            let you = player.targetRadius
            let rival = tutorialMissedFish.flatMap { fishByID[$0]?.targetRadius } ?? ArcadeTutorial.missedFishGrown
            tutorialMeal = spawnTutorialFish(ArcadeTutorial.lastMeal(you: you, rival: rival),
                                             path: .headOn(share: lane, crossing: T.tutorialMealCrossing), glows: true)
            tutorialComesRoundAt = simClock + T.tutorialWrapDelay / T.tutorialPace
        case .eatEnough:
            tutorialCaptionPending = beat.caption
            tutorialWallSize = ArcadeTutorial.wallFish(you: player.targetRadius)
            tutorialWallBreach = nil
            // Like a level: two meals and then the wall swim freely ahead of you, all well off screen for now. The two
            // meals together make you big enough for the wall, and one isn't enough.
            let meal = ArcadeTutorial.wallMeal(you: player.targetRadius, wall: tutorialWallSize)
            tutorialWallMeals = T.tutorialWallMeals.enumerated().map { index, swim in
                var generator = SeededGenerator(seed: T.spawnSeed &+ UInt64(index + 1) &* 104_729)
                return spawnTutorialSwimmer(meal, style: FishStyle.random(using: &generator), swim: swim, glows: true)
            }
            let heights = ArcadeTutorial.wallHeights(bottom: waterBottom, top: waterTop)
            tutorialWall = heights.map { y in
                spawnTutorialSwimmer(tutorialWallSize, style: ArcadeTutorial.wallStyle,
                                     swim: TutorialSwim(ahead: T.tutorialWallAhead, home: waterShare(y), wander: 0, heading: -1,
                                                        speed: T.tutorialWallSwim, bob: T.tutorialWallBob))
            }
            lossReason = "Eat both fish to get through."
        case .lastFish:
            tutorialCaptionPending = beat.caption
            // The rest of the wall, smaller than you now, turns and bolts ahead, strung out, then tires for you to catch.
            let rest = tutorialWall.filter { $0 != tutorialWallBreach && fishByID[$0] != nil }
            for (id, dash) in zip(rest, T.tutorialFleeDashes) {
                guard var swim = tutorialSwims[id] else { continue }
                swim.heading = 1
                swim.bob = 0
                swim.wander = 0.05
                swim.speed = T.tutorialFleeSpeed
                swim.dashSpeed = playerSpeed * T.tutorialFleeDash
                swim.dashUntil = simClock + dash
                tutorialSwims[id] = swim
            }
        }
    }

    /// The fish that got away comes round the reef again: in from ahead of you on its side of the water, turning
    /// toward wherever you are.
    private func bringMissedFishRound() {
        tutorialComesRoundAt = nil
        guard let id = tutorialMissedFish, fishByID[id] != nil else { return }
        let toward = waterShare(player.position.y).clamped(0.2, 0.8), speed: CGFloat = 0.55
        let turn: CGFloat = 0.45, enters = TutorialPath.enters, leaves = TutorialPath.leaves
        let turned = (enters - turn) / speed
        tutorialPaths[id] = (TutorialPath(points: [(0, enters, tutorialMissedLane), (turned, turn, toward),
                                                   (turned + (turn - leaves) / speed, leaves, toward)]), simClock, false)
    }

    private func advanceTutorial() {
        guard isTutorial, phase == .playing else { return }
        if let caption = tutorialCaptionPending {
            tutorialCaptionPending = nil
            showTutorialCaption(caption)
        }
        let elapsed = tutorialTime(since: tutorialBeatStart)
        if let at = tutorialNextBeatAt {
            if simClock >= at, let next = ArcadeTutorial.Beat(rawValue: tutorialBeat.rawValue + 1) { beginTutorialBeat(next) }
            return
        }
        func gone(_ id: Int?) -> Bool { id.map { fishByID[$0] == nil } ?? true }
        func finished(_ id: Int) -> Bool { tutorialPaths[id].map { tutorialTime(since: $0.start) >= $0.path.duration } ?? true }
        // The pause before the next beat is in the tutorial's own timings too, so it keeps pace with the fish.
        func next(after delay: CGFloat) { tutorialNextBeatAt = simClock + delay / T.tutorialPace }
        let water = waterTop - waterBottom
        switch tutorialBeat {
        case .holdToRise:
            followTutorialHint()
            // Risen far enough above your lowest: one short hold does it, and so do a few taps.
            let lowest = min(tutorialLowest ?? player.position.y, player.position.y)
            tutorialLowest = lowest
            let nearTop = player.position.y >= waterTop - player.radius * 0.95 - water * 0.04
            if player.position.y - lowest >= T.tutorialRiseShare * water || nearTop {
                hideTutorialCaption()
                next(after: 0.15)
            } else if simClock >= tutorialHintAt {
                tutorialHint.show(.hold)
                tutorialHintAt = simClock + T.tutorialHintSeconds
            }
        case .letGoToFall:
            followTutorialHint()
            tutorialPeak = max(tutorialPeak, player.position.y)
            if !isHolding, tutorialPeak - player.position.y >= T.tutorialFallShare * water {
                tutorialHint.hide()
                hideTutorialCaption()
                next(after: 0.5)
            } else if simClock >= tutorialHintAt {
                tutorialHint.show(.letGo)
                tutorialHintAt = simClock + T.tutorialHintSeconds
            }
        case .eatSmaller:
            if gone(tutorialMeal) {
                if tutorialMealWasEaten { hideTutorialCaption(); next(after: 0.7) }
                // Missed: another one, below you this time.
                else { tutorialMeal = spawnTutorialFish(T.tutorialFirstMeal, path: .headOn(share: 0.3, crossing: T.tutorialMealCrossing), glows: true) }
            }
        case .dodgeBigger:
            if gone(tutorialBigFish) { hideTutorialCaption(); next(after: 0.5) }
        case .missedFishEats:
            let lane = tutorialMissedLane, sets = T.tutorialMissedFishSets
            // Its meals first, ahead of it and slower; then the missed fish itself, which swims on past them and off.
            let leads = ArcadeTutorial.missedMealLeads.sorted(by: >)
            if tutorialMissedMeals.count < leads.count, elapsed >= sets - leads[tutorialMissedMeals.count] {
                tutorialMissedMeals.append(spawnTutorialFish(T.tutorialMissedFishMeal,
                    path: .straight(share: lane, speed: T.tutorialMissedMealSpeed)))
            }
            if tutorialMissedFish == nil, elapsed >= sets {
                tutorialMissedFish = spawnTutorialFish(T.tutorialMissedFish, style: ArcadeTutorial.missedStyle,
                    path: .straight(share: lane, speed: T.tutorialMissedFishSpeed), leaves: false)
            }
            guard let missed = tutorialMissedFish else { return }
            if fishByID[missed] == nil {
                // You ate it after all: one that already grew is off round the reef, and it's coming back.
                tutorialMissedFish = spawnTutorialFish(max(ArcadeTutorial.missedFishGrown, player.targetRadius * 1.12),
                    style: ArcadeTutorial.missedStyle, path: TutorialPath(points: [(0, TutorialPath.leaves, lane)]), leaves: false)
                next(after: 0.6)
            } else if finished(missed) {
                // Off screen behind you, bigger now.
                next(after: 0.3)
            }
        case .catchItBack:
            guard let missed = tutorialMissedFish.flatMap({ fishByID[$0] }) else {
                // Caught it: on to the last beat.
                tutorialMissedFish = nil
                hideTutorialCaption()
                next(after: 0.8)
                return
            }
            if let at = tutorialComesRoundAt {
                if simClock >= at { bringMissedFishRound() }
            } else if finished(missed.id) {
                // It got past: around it comes again, with another meal if you still need one.
                if gone(tutorialMeal) && player.targetRadius <= missed.targetRadius {
                    tutorialMeal = spawnTutorialFish(ArcadeTutorial.lastMeal(you: player.targetRadius, rival: missed.targetRadius),
                        path: .headOn(share: waterShare(player.position.y).clamped(0.25, 0.75), crossing: T.tutorialMealCrossing), glows: true)
                }
                tutorialComesRoundAt = simClock + T.tutorialWrapDelay / T.tutorialPace
            }
        case .eatEnough:
            // Played like a level, so nothing here steers anything: once you bite into a wall fish you're through, and
            // the rest of the wall bolts. The wall eating you ends it like any level, and Retry starts the wall again.
            if tutorialWallBreach != nil { beginTutorialBeat(.lastFish) }
        case .lastFish:
            let rest = tutorialWall.compactMap { fishByID[$0] }
            if rest.isEmpty && swallows.isEmpty {
                // The last fish swimming: the tutorial is done.
                hideTutorialCaption()
                analytics?.tutorial(.completed)
                onTutorialFinished?()
                win()
                return
            }
            // One that got past you comes round the reef again: in from off screen ahead, swimming away from you.
            for f in rest where f.state == .swimming && world.delta(from: player.position.x, to: f.position.x) < -size.width * 0.45 / zoom {
                f.position = CGPoint(x: world.wrap(player.position.x + 0.85 * size.width / zoom), y: f.position.y)
                f.velocity = CGVector(dx: T.tutorialFleeSpeed, dy: 0)
                previousPresentation[f.id] = FishPresentation(f)
            }
        }
    }

    private func spawnTutorialFish(_ radius: CGFloat, style: FishStyle? = nil, path: TutorialPath, leaves: Bool = true,
                                   glows: Bool = false) -> Int {
        let id = nextFishID
        nextFishID += 1
        let start = path.at(0)
        let f = Fish(id: id, isPlayer: false, position: CGPoint(x: world.wrap(player.position.x + start.ahead * size.width / zoom),
                                                                 y: waterBottom + start.share * (waterTop - waterBottom)), radius: radius)
        f.heading = -1
        f.facing = -1
        // Seeded by size, not id, so a meal that comes round again looks the same as the one you missed.
        var generator = SeededGenerator(seed: T.spawnSeed &+ UInt64(radius.rounded()) &* 7_919)
        add(f, style: style ?? FishStyle.random(using: &generator))
        tutorialPaths[id] = (path, simClock, leaves)
        if glows { addTutorialGlow(id, radius: radius) }
        return id
    }

    /// A fish that swims freely, as in a level (see `TutorialSwim`), starting where `swim` says, off screen ahead.
    private func spawnTutorialSwimmer(_ radius: CGFloat, style: FishStyle, swim: TutorialSwim, glows: Bool = false) -> Int {
        let id = nextFishID
        nextFishID += 1
        let f = Fish(id: id, isPlayer: false, position: CGPoint(x: world.wrap(player.position.x + swim.ahead * size.width / zoom),
                                                                 y: waterBottom + swim.home * (waterTop - waterBottom)), radius: radius)
        f.heading = swim.heading
        f.facing = swim.heading
        f.velocity = CGVector(dx: swim.heading * swim.speed, dy: 0)
        f.targetY = f.position.y
        f.phase = CGFloat(id) * 1.7
        add(f, style: style)
        tutorialSwims[id] = swim
        if glows { addTutorialGlow(id, radius: radius) }
        return id
    }

    /// The ring that pulses round a fish for you to eat.
    private func addTutorialGlow(_ id: Int, radius: CGFloat) {
        tutorialMealWasEaten = false
        let ring = SKShapeNode(circleOfRadius: radius * 1.7)
        ring.strokeColor = SKColor(white: 1, alpha: 0.8)
        ring.fillColor = .clear
        ring.lineWidth = 2.5
        // Over the fish's body (0), under its belly and the rest (0.5 and up), as it was drawn when added last.
        ring.zPosition = 0.25
        ring.run(.repeatForever(.sequence([.group([.scale(to: 1.35, duration: 0.8), .fadeOut(withDuration: 0.8)]),
                                           .scale(to: 1, duration: 0), .fadeAlpha(to: 1, duration: 0)])))
        nodes[id]?.addChild(ring)
    }

    /// A fish in the last beat swims like one in a level: on at its own pace, a little faster and slower as it goes,
    /// wandering gently up and down near its height, and turning to face the way it swims. A wall fish holds its place
    /// in the wall instead: a steady pace, so the three stay side by side with no way round, and only a bob.
    private func moveTutorialSwimmer(_ f: Fish, _ swim: TutorialSwim, _ dt: CGFloat) {
        var generator = aiMovementRNGs[f.id] ?? movementGenerator(for: f.id)
        defer { aiMovementRNGs[f.id] = generator }
        let water = waterTop - waterBottom, home = waterBottom + swim.home * water
        let reach = swim.bob > 0 ? swim.bob + 1 : swim.wander * water
        let low = max(waterBottom + f.radius, home - reach), high = max(low, min(waterTop - f.radius, home + reach))
        let pulse = swim.bob > 0 ? 0 : 0.2 * sin(simClock * 0.9 + f.phase)
        // Bolting, a fish is up to speed in a moment; after, it tires back to its pace gradually.
        let dashing = simClock < swim.dashUntil
        let pace = dashing ? swim.dashSpeed : swim.speed * (1 + pulse)
        let cruise = swim.heading * pace
        let vx = f.velocity.dx + (cruise - f.velocity.dx) * min(1, dt * (dashing ? 6 : 1.5))
        let desiredVY: CGFloat
        if swim.bob > 0 {
            desiredVY = (home + sin(simClock * 1.1 + f.phase) * swim.bob - f.position.y) * 3
        } else {
            f.retargetTimer -= dt
            if f.retargetTimer <= 0 || abs(f.targetY - f.position.y) < 4 {
                f.targetY = CGFloat.random(in: low...high, using: &generator)
                f.retargetTimer = CGFloat.random(in: 1.2...2.4, using: &generator)
            }
            desiredVY = ((f.targetY - f.position.y) * 0.9).clamped(-T.tutorialMealWander, T.tutorialMealWander)
                + sin(simClock * 1.3 + f.phase) * 6
        }
        let vy = f.velocity.dy + (desiredVY - f.velocity.dy) * min(1, dt * 2)
        FreeSwim.integrate(f, velocity: CGVector(dx: vx, dy: vy), dt: dt, minY: low, maxY: high, world: world)
        f.heading = swim.heading
        f.facing += (swim.heading - f.facing) * min(1, dt * T.freeEncounterFacingRate)
    }

    /// Seconds of the tutorial's own timings since `start`, run at `tutorialPace`.
    private func tutorialTime(since start: CGFloat) -> CGFloat { (simClock - start) * T.tutorialPace }

    private func moveScripted(_ f: Fish, _ scripted: (path: TutorialPath, start: CGFloat, leaves: Bool), _ dt: CGFloat) {
        // Paths are measured from you, so once you're caught they stop: you're carried into whoever caught you, and a
        // fish placed from you would chase you ahead, sweeping the screen along. It swims on as it was going instead
        // (and doesn't leave mid-bite). Only once you're caught: while you're eating, you swim on, and so do they.
        switch player.state {
        case .beingSwallowed, .removed:
            f.position = CGPoint(x: world.wrap(f.position.x + f.velocity.dx * dt), y: f.position.y)
            return
        case .swimming, .swallowing:
            break
        }
        let t = tutorialTime(since: scripted.start)
        // A fish mid-bite finishes its meal first.
        if scripted.leaves && t > scripted.path.duration && f.state == .swimming {
            removeFish(f)
            return
        }
        let at = scripted.path.at(t)
        let next = CGPoint(x: world.wrap(player.position.x + at.ahead * size.width / zoom),
                           y: waterBottom + at.share * (waterTop - waterBottom))
        // A fish coming round the reef jumps from behind you to ahead of you off screen: no speed from that.
        let jumped = abs(world.delta(from: f.position.x, to: next.x)) > size.width * 0.3 / zoom
        f.velocity = jumped ? .zero : CGVector(dx: world.delta(from: f.position.x, to: next.x) / max(dt, 0.0001),
                                               dy: (next.y - f.position.y) / max(dt, 0.0001))
        f.position = next
        // Drawn there at once: smoothing from where it was would sweep it across the screen past you.
        if jumped { previousPresentation[f.id] = FishPresentation(f) }
        // Every tutorial fish swims at you, as fish you meet in a level do.
        f.heading = -1
        f.facing = -1
    }

    private func showTutorialCaption(_ text: String) {
        #if DEBUG
        noteHitch(.card, "tutorial caption")
        #endif
        tutorialCaption.text = text
        let pill = CGSize(width: tutorialCaption.frame.width + T.tutorialCaptionSize * 1.4, height: T.tutorialCaptionSize * 1.9)
        tutorialCaptionPill.path = CGPath(roundedRect: CGRect(x: -pill.width / 2, y: -pill.height / 2, width: pill.width, height: pill.height),
                                          cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil)
        tutorialCaption.removeAllActions()
        tutorialCaption.run(.fadeAlpha(to: 0.95, duration: 0.25))
    }

    private func hideTutorialCaption() {
        tutorialCaption.removeAllActions()
        tutorialCaption.run(.fadeOut(withDuration: 0.25))
    }

    private func showTutorialFinale() {
        #if DEBUG
        noteHitch(.card, "tutorial finale")
        #endif
        messageNode.removeAllActions()
        messageNode.removeAllChildren()
        let line = label(ArcadeTutorial.finale, fontSize: 34, heavy: true)
        let maxWidth = size.width - 80
        if line.frame.width > maxWidth { line.fontSize *= maxWidth / line.frame.width }
        let panel = SKShapeNode(rectOf: CGSize(width: line.frame.width + 70, height: 84), cornerRadius: 24)
        panel.fillColor = SKColor(white: 0, alpha: 0.3)
        panel.strokeColor = .clear
        // Under its line: the scene ignores sibling order.
        panel.zPosition = -1
        messageNode.addChild(panel)
        messageNode.addChild(line)
        messageNode.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
        messageNode.alpha = 0
        messageNode.setScale(0.92)
        messageNode.run(.sequence([.wait(forDuration: TimeInterval(T.tutorialFinaleDelay)),
                                   .group([.fadeIn(withDuration: 0.35), .scale(to: 1, duration: 0.35)])]))
    }

    /// Leaves the tutorial for the map (its skip control).
    func skipTutorial() {
        guard isTutorial else { return }
        analytics?.tutorial(.skipped)
        #if DEBUG
        finishRunRecording("level_map")
        #endif
        onExit?()
    }

    private func inKelp(_ position: CGPoint) -> Bool {
        kelpBeds.contains { abs(world.delta(from: $0.bed.x, to: position.x)) <= $0.bed.halfWidth }
    }

    /// Columns stay screen-tall at any zoom and narrow as the camera zooms out.
    private func renderKelp(cameraX: CGFloat, zoom: CGFloat, time: CGFloat) {
        for (bed, back, front) in kelpBeds {
            let x = size.width * T.playerScreenX + world.delta(from: cameraX, to: bed.x) * zoom
            let half = bed.halfWidth * zoom + 40
            let hidden = x + half < 0 || x - half > size.width
            back.isHidden = hidden
            front.isHidden = hidden
            if hidden { continue }
            for node in [back, front] {
                node.position = CGPoint(x: x, y: T.kelpRootY)
                node.xScale = zoom
                node.sway(time: time)
            }
        }
    }

    // MARK: - Sunset Cove

    /// Depths, from the hazard layer's 8. A hook's rig sits behind every fish (whose lowest part, the first fish's
    /// tail, is at the fish layer's 10, plus 1.5, less 2: 9.5): its line at 5.5, the hook's shank at 5.75 (over the
    /// bait's tail and fin, under its body), the boat at 6, and the bait's own parts from 4.25 (its tail) to 9.45 (its
    /// open mouth). Each hook's rig is a hair deeper than the one before, so two overlapping can't swap. A splash, at 7.
    private static let hookLineDepth: CGFloat = 5.5 - 8, hookMetalDepth: CGFloat = 5.75 - 8
    private static let hookBoatDepth: CGFloat = 6 - 8, hookBaitDepth: CGFloat = 6.25 - 8, hookSplashDepth: CGFloat = 7 - 8

    private func spawnHooks() {
        reel = nil
        let hooks = level.meetingPlan?.hooks ?? []
        hookRigs = hooks.enumerated().map { index, hook in
            let offset = CGFloat(index) * 0.002
            let boat = HookBoatNode(seed: hook.styleSeed)
            boat.zPosition = Self.hookBoatDepth + offset
            let line = SKShapeNode()
            line.strokeColor = T.sunsetLineColor
            line.lineWidth = 1
            line.zPosition = Self.hookLineDepth + offset
            let metal = HookMetal.make()
            metal.zPosition = Self.hookMetalDepth + offset
            var style = SeededGenerator(seed: hook.styleSeed)
            let bait = FishNode(style: FishStyle.random(using: &style), isPlayer: false, tailPhase: CGFloat(index) * 1.3)
            bait.zPosition = Self.hookBaitDepth + offset
            for node in [boat, line, metal, bait] as [SKNode] {
                node.isHidden = true
                hazardLayer.addChild(node)
            }
            // One boat fishes both of the gate's lines: the first's rod is just ahead of the second's, under its hull.
            let sharesBoat = hook.role == .gate && hooks.indices.contains(index + 1) && hooks[index + 1].role == .gate
            return HookRig(hook: hook, boat: boat, line: line, metal: metal, bait: bait, sharesBoat: sharesBoat)
        }
    }

    /// Where a hook is now, in the wrapped world.
    private func hookPosition(_ hook: PlannedHook, time: CGFloat) -> CGPoint {
        let at = HookMotion.position(hook, time: time)
        return CGPoint(x: world.wrap(at.x), y: at.y)
    }

    /// Your fish touching a bait or a hook is caught. The line is harmless, and other fish pass hooks by: they never
    /// take the bait.
    private func updateHooks() {
        guard !hookRigs.isEmpty, reel == nil, player.isAlive else { return }
        #if DEBUG
        if simulationEcologyProbe { return }
        #endif
        for (index, rig) in hookRigs.enumerated() {
            let at = hookPosition(rig.hook, time: simClock)
            if HookRules.catches(player.position, radius: player.radius, hook: at, bait: rig.hook.baitRadius, world: world) {
                catchOnHook(index, at: at)
                return
            }
        }
    }

    /// Caught: you're reeled up the line and out of the water (`renderHooks`), then the result.
    private func catchOnHook(_ index: Int, at hook: CGPoint) {
        let reason = "Caught on a hook."
        if metricAccumulator != nil {
            // Never sent while Sunset Cove is a prototype (`startRun`); the stats server would need this cause first.
            observeMetrics()
            metricDeathCause = "hook"
            fatalMetrics = metricAccumulator?.summary
        }
        #if DEBUG
        recordRunEvent("hazard_death", fields: ["fishID": player.id, "reason": reason, "hook": index,
                                               "x": player.position.x, "y": player.position.y, "radius": player.radius])
        #endif
        releaseSwallows(of: player)
        player.state = .removed
        reel = (index, realClock, hook, false)
        // You took the bait.
        hookRigs[index].bait.isHidden = true
        lossReason = reason
        buzz(.eaten)
        playSound(.lose)
        lose(resultDelay: T.sunsetReelResultDelay, soundsAtResult: false)
    }

    /// Each boat at the surface over its hook, its line down to the hook, and the bait wriggling on it; you, if caught,
    /// reeled up the line by your mouth and out of the water.
    private func renderHooks(cameraX: CGFloat, zoom: CGFloat, fraction: CGFloat, time: CGFloat) {
        guard !hookRigs.isEmpty else { return }
        let anchorX = size.width * T.playerScreenX
        // Between the last two steps, as the fish are drawn.
        let hookTime = max(0, simClock - T.simulationStep * (1 - fraction))
        let waterline = screenWaterTop + 5
        func screen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: anchorX + world.delta(from: cameraX, to: point.x) * zoom, y: waterCenter + (point.y - waterCenter) * zoom)
        }
        for (index, rig) in hookRigs.enumerated() {
            let bait = rig.hook.baitRadius * zoom
            var at = screen(hookPosition(rig.hook, time: hookTime))
            // Measured from its own hook, not the shorter way round the lap from you: for a hook about half a lap away,
            // that could put its rod on the far side of the screen, with a line all the way across.
            let rodX = at.x + (HookMotion.rodX(rig.hook, time: hookTime) - HookMotion.position(rig.hook, time: hookTime).x) * zoom
            let rod = CGPoint(x: rodX, y: waterline + 4 * zoom)
            // The boat runs ahead of its rod, to the left, and a caught fish swings out round its hook.
            let left = min(at.x, rodX - (T.sunsetBoatLength + 40) * zoom) - 3 * max(bait, player.radius * zoom)
            let right = max(at.x, rodX) + 3 * max(bait, player.radius * zoom)
            let hidden = right < 0 || left > size.width
            for node in [rig.line, rig.metal] as [SKNode] { node.isHidden = hidden }
            rig.boat.isHidden = hidden || rig.sharesBoat
            rig.bait.isHidden = hidden || reel?.rig == index
            if hidden { continue }
            var lineShows = true
            if let caught = reel, caught.rig == index {
                // Up the line to the rod, quicker as it goes, then straight up out of the water.
                let start = screen(caught.from)
                let u = ((time - caught.start) / T.sunsetReelSeconds).clamped(0, 1)
                let up = hypot(rod.x - start.x, rod.y - start.y)
                let travelled = u * u * (up + size.height - rod.y + 4 * player.radius * zoom)
                at = travelled < up
                    ? CGPoint(x: start.x + (rod.x - start.x) * travelled / max(up, 1), y: start.y + (rod.y - start.y) * travelled / max(up, 1))
                    : CGPoint(x: rod.x, y: rod.y + travelled - up)
                lineShows = travelled < up
                if !caught.splashed && at.y >= waterline {
                    reel?.splashed = true
                    let splash = HookSplash.make(width: player.radius * zoom * 1.6)
                    splash.position = CGPoint(x: at.x, y: waterline)
                    splash.zPosition = Self.hookSplashDepth
                    hazardLayer.addChild(splash)
                }
                renderHookedPlayer(mouth: at, zoom: zoom, time: time)
            }
            rig.boat.position = CGPoint(x: rodX, y: waterline)
            rig.boat.setScale(zoom)
            let eye = CGPoint(x: at.x, y: at.y + HookMetal.eye * bait)
            let path = CGMutablePath()
            path.move(to: rod)
            path.addLine(to: eye)
            rig.line.path = path
            rig.line.isHidden = !lineShows
            let scale = bait / FishNode.referenceRadius
            rig.metal.position = at
            rig.metal.setScale(scale)
            rig.metal.lineWidth = max(1.3, 2.4 * zoom) / max(scale, 0.01)
            if reel?.rig != index {
                let phase = CGFloat(index) * 1.7
                rig.bait.position = at
                rig.bait.apply(radius: bait, facing: -1,
                               tilt: T.sunsetBaitWiggle * sin(time * 5.2 + phase) + 0.05 * sin(time * 13.1 + phase * 2),
                               stretchX: 1, stretchY: 1, mouthOpen: 0.12 + 0.1 * sin(time * 3.3 + phase), time: time, tailRate: 16)
            }
        }
    }

    /// You on the hook by your mouth, nose up and thrashing, as you're reeled in.
    private func renderHookedPlayer(mouth: CGPoint, zoom: CGFloat, time: CGFloat) {
        guard let node = nodes[player.id] else { return }
        let r = player.radius * zoom
        let tilt = .pi / 2 * 0.88 + 0.22 * sin(time * 26)
        // Your mouth is 1.32 radii ahead of your center and a tenth below it (`FishNode`), turned with you.
        let offset = CGPoint(x: 1.32 * r * cos(tilt) + 0.1 * r * sin(tilt), y: 1.32 * r * sin(tilt) - 0.1 * r * cos(tilt))
        node.isHidden = mouth.y - 2.5 * r > size.height
        node.position = CGPoint(x: mouth.x - offset.x, y: mouth.y - offset.y)
        node.apply(radius: r, facing: 1, tilt: tilt, stretchX: 1, stretchY: 1, mouthOpen: 0.55, time: time, tailRate: 42)
    }

    /// Sunset Cove's low sun, glowing at the surface, with soft shafts of its light slanting down through the water.
    private func layoutSunset() {
        sunRays.removeAll()
        guard arcadeWorld == .sunsetCove else { return }
        let sunX = size.width * T.sunsetSunX, surface = screenWaterTop + 5
        func glow(_ color: SKColor, width: CGFloat, height: CGFloat, alpha: CGFloat, y: CGFloat, z: CGFloat) {
            let node = SKSpriteNode(texture: ArcadeArt.glow, color: color, size: CGSize(width: width, height: height))
            node.colorBlendFactor = 1
            node.blendMode = .add
            node.alpha = alpha
            node.position = CGPoint(x: sunX, y: y)
            // Over the water (0) and under the surface line and the specks (1); every glow adds its light.
            node.zPosition = z
            backgroundLayer.addChild(node)
        }
        // A wide warm haze over the water near the sun, a golden shimmer along the surface, then the sun itself,
        // half under the surface, with a white-hot heart.
        glow(SKColor(red: 1, green: 0.6, blue: 0.42, alpha: 1), width: size.width * 1.2, height: size.height * 1.5, alpha: 0.32,
             y: surface, z: 0.2)
        glow(SKColor(red: 1, green: 0.82, blue: 0.5, alpha: 1), width: size.width * 0.95, height: 22, alpha: 0.5, y: surface, z: 0.5)
        glow(SKColor(red: 1, green: 0.86, blue: 0.55, alpha: 1), width: 170, height: 120, alpha: 0.95, y: surface + 2, z: 0.6)
        glow(.white, width: 70, height: 46, alpha: 0.9, y: surface + 4, z: 0.7)
        var rng = SeededGenerator(seed: 23)
        for index in 0..<8 {
            let ray = SKSpriteNode(texture: ArcadeArt.lightShaft, color: SKColor(red: 1, green: 0.8, blue: 0.58, alpha: 1),
                                   size: CGSize(width: CGFloat.random(in: 50...110, using: &rng),
                                                height: size.height * CGFloat.random(in: 0.9...1.3, using: &rng)))
            ray.anchorPoint = CGPoint(x: 0.5, y: 1)
            ray.colorBlendFactor = 1
            ray.blendMode = .add
            // The sun is low on the right, so its light slants down to the left.
            ray.zRotation = -CGFloat.random(in: 0.32...0.5, using: &rng)
            ray.position = CGPoint(x: 0, y: surface + 6)
            ray.zPosition = 0.3
            backgroundLayer.addChild(ray)
            sunRays.append(SunRay(node: ray, x: sunX - 560 + CGFloat(index) * 85 + CGFloat.random(in: -20...20, using: &rng),
                                  strength: CGFloat.random(in: 0.6...1, using: &rng), phase: CGFloat.random(in: 0...6, using: &rng)))
        }
        updateSunRays(cameraDelta: 0, time: 0)
    }

    /// The shafts drift slowly against your swim (the sun itself, far off, stays put), breathing as they go, and are
    /// brightest near the sun.
    private func updateSunRays(cameraDelta: CGFloat, time: CGFloat) {
        guard !sunRays.isEmpty else { return }
        let sunX = size.width * T.sunsetSunX, span: (from: CGFloat, to: CGFloat) = (sunX - 620, sunX + 140)
        for index in sunRays.indices {
            var x = sunRays[index].x - cameraDelta * T.sunsetRayParallax
            if x < span.from { x += span.to - span.from } else if x > span.to { x -= span.to - span.from }
            sunRays[index].x = x
            let ray = sunRays[index]
            let near = 1 - min(1, abs(x - sunX) / (span.to - span.from))
            ray.node.position.x = x
            ray.node.alpha = (0.05 + 0.11 * near) * ray.strength * (0.75 + 0.25 * sin(time * 0.6 + ray.phase))
        }
    }

    // MARK: - Jelly Bloom (arcade-only; no shared engine changes)

    private func spawnJellies() {
        // Planned jellies drift exactly where the planner put them, in its order.
        guard let layout = level.jellies, let planned = level.meetingPlan?.jellies else { return }
        for jelly in planned {
            let node = JellyfishNode(radius: layout.radius, tentacleLength: layout.tentacleLength, phase: jelly.phase,
                                     night: layout.night)
            hazardLayer.addChild(node)
            let start = JellyDrift.position(origin: jelly.origin, phase: jelly.phase, time: 0, screenWidth: size.width, world: world)
            jellies.append(BloomJelly(node: node, origin: jelly.origin, position: start, phase: jelly.phase))
        }
    }

    private func updateJellies(_ dt: CGFloat, previousFish: [Int: CGPoint]) {
        guard let layout = level.jellies else { return }
        for i in jellies.indices {
            let previousJelly = jellies[i].position
            jellies[i].position = JellyDrift.position(origin: jellies[i].origin, phase: jellies[i].phase, time: simClock,
                                                      screenWidth: size.width, world: world)
            let jelly = jellies[i]
            for f in fish.filter({ $0.isAlive }) {
                #if DEBUG
                if simulationEcologyProbe && f.isPlayer { continue }
                #endif
                guard let old = previousFish[f.id], plannedFishMeetsJellies(f) else { continue }
                let touch = JellySwim.contact(f, old: old, jelly: jelly.position, previousJelly: previousJelly,
                                              layout: layout, world: world)
                switch touch.contact {
                case .none: break
                case .bounce:
                    guard !f.isPlayer || bounceCooldown <= 0 else { continue }
                    let ceiling = waterTop - f.radius * (f.isPlayer ? 0.95 : 1)
                    if !f.isPlayer && JellySwim.slideIfCramped(f, at: touch.at, jellyY: jelly.position.y, layout: layout,
                                                               ceiling: ceiling) { continue }
                    let remaining = JellySwim.bounce(f, at: touch.at, previous: touch.previous, jellyY: jelly.position.y,
                        layout: layout, speed: T.jellyBounceSpeed / zoom, dt: dt, ceiling: ceiling)
                    jelly.node.bounce()
                    #if DEBUG
                    debugBounces.append((f.id, i, simClock, size.width * T.playerScreenX
                        + world.delta(from: player.position.x, to: f.position.x) * zoom))
                    recordRunEvent("bounce", fields: ["fishID": f.id, "jellyID": i, "remainingFrame": remaining,
                                                     "x": f.position.x, "y": f.position.y, "vy": f.velocity.dy])
                    #endif
                    if f.isPlayer {
                        metricAccumulator?.bounce()
                        bounceRemaining = T.jellyBounceSeconds
                        bounceCooldown = T.jellyBounceCooldown
                        f.pulse = T.pulseDuration
                        buzz(.bounce)
                        playSound(.bounce)
                    }
                case .tentacles:
                    if f.isPlayer { jelly.node.sting(); removeByTentacles(f); return }
                    // NPCs steer around stingers; contact never removes ecosystem food.
                    if let avoidance = bloomAvoidance(for: f, velocity: f.velocity) {
                        f.velocity = avoidance
                    }
                }
            }
        }
    }

    private func removeByTentacles(_ victim: Fish) {
        let reason = "Caught in the tentacles."
        if victim.isPlayer && metricAccumulator != nil {
            observeMetrics()
            metricDeathCause = "tentacles"
            fatalMetrics = metricAccumulator?.summary
        }
        #if DEBUG
        recordRunEvent("hazard_death", fields: ["fishID": victim.id, "reason": reason,
                                               "x": victim.position.x, "y": victim.position.y, "radius": victim.radius])
        #endif
        // If a predator hits a curtain mid-swallow, its prey escapes rather than getting stuck.
        releaseSwallows(of: victim)
        victim.state = .removed
        if let node = nodes[victim.id] {
            let zap = ZapNode(seed: UInt64(victim.id) &+ UInt64(simClock * 60))
            zap.zPosition = node.zPosition + 0.25
            fishLayer.addChild(zap)
            stungFish.append(StungFish(id: victim.id, node: node, zap: zap, start: realClock,
                position: victim.position, radius: victim.radius, facing: victim.facing >= 0 ? 1 : -1))
        }
        if victim.isPlayer {
            lossReason = reason
            buzz(.sting)
            playSound(.sting)
            lose(resultDelay: T.stingResultDelay)
        } else {
            // Its node stays on screen for the sting (`stungFish`).
            removeFish(victim, keepingNode: true)
        }
    }

    /// Takes a fish out of the game, and everything kept about it. A swallow it was part of ends, so its partner swims
    /// on rather than waiting forever on a meal that's gone. `keepingNode`: its node stays on screen (a sting's death).
    private func removeFish(_ victim: Fish, keepingNode: Bool = false) {
        releaseSwallows(of: victim)
        victim.state = .removed
        if !keepingNode { nodes[victim.id]?.removeFromParent() }
        let id = victim.id
        nodes[id] = nil
        fish.removeAll { $0.id == id }
        fishByID[id] = nil
        aiMovementRNGs[id] = nil
        movementVariants[id] = nil
        encounterLeases[id] = nil
        approachEnds[id] = nil
        silhouetteShade[id] = nil
        previousPresentation[id] = nil
        tutorialPaths[id] = nil
        tutorialSwims[id] = nil
    }

    /// Ends any swallow `victim` is part of, letting the other fish go.
    private func releaseSwallows(of victim: Fish) {
        for swallow in swallows where swallow.predatorID == victim.id || swallow.preyID == victim.id {
            let otherID = swallow.predatorID == victim.id ? swallow.preyID : swallow.predatorID
            if let survivor = fishByID[otherID], survivor.state != .removed {
                survivor.state = .swimming
                survivor.shrink = 1
                survivor.struggle = 0
                survivor.chew = 0
                survivor.squash = 0
            }
        }
        swallows.removeAll { $0.predatorID == victim.id || $0.preyID == victim.id }
    }

    private func renderJellies(cameraX: CGFloat, zoom: CGFloat, fraction: CGFloat, time: CGFloat) {
        for (index, jelly) in jellies.enumerated() {
            let position = index < previousJellyPositions.count
                ? PresentationInterpolation.position(from: previousJellyPositions[index], to: jelly.position,
                    fraction: fraction, world: world) : jelly.position
            let x = size.width * T.playerScreenX + world.delta(from: cameraX, to: position.x) * zoom
            jelly.node.isHidden = x < -100 || x > size.width + 100
            jelly.node.position = CGPoint(x: x, y: waterCenter + (position.y - waterCenter) * zoom)
            jelly.node.setScale(zoom)
            let previous = index < previousJellyPositions.count ? previousJellyPositions[index] : jelly.position
            jelly.node.animate(time: time, drift: CGVector(dx: world.delta(from: previous.x, to: jelly.position.x) / T.simulationStep,
                                                           dy: (jelly.position.y - previous.y) / T.simulationStep))
        }
    }

    /// Jelly Bloom's swimmers steer around tentacles.
    private func bloomAvoidance(for f: Fish, velocity: CGVector) -> CGVector? {
        guard let layout = level.jellies else { return nil }
        return JellySwim.avoidance(for: f, velocity: velocity, jellies: jellies.map(\.position), layout: layout,
                                   world: world, waterBottom: waterBottom, waterTop: waterTop, zoom: zoom)
    }

    private func advanceGrowth(_ dt: CGFloat) {
        for f in fish {
            if f.growElapsed < T.growDuration {
                f.growElapsed += dt
                let t = min(1, f.growElapsed / T.growDuration)
                let eased = 1 - pow(1 - t, 3)
                f.radius = f.growFrom + (f.targetRadius - f.growFrom) * eased
            }
            if f.pulse > 0 { f.pulse = max(0, f.pulse - dt) }
            if case .swallowing = f.state {
                f.mouth = min(1, f.mouth + dt / T.mouthOpenSeconds)
            } else {
                f.mouth = max(0, f.mouth - dt / T.mouthCloseSeconds)
            }
        }
    }

    // MARK: - Collisions and swallowing

    private func resolveCollisions() {
        let candidates = fish.filter { f in
            #if DEBUG
            if simulationEcologyProbe && f.isPlayer { return false }
            #endif
            return f.state == .swimming
        }
        guard candidates.count > 1 else { return }
        let aiMayEat = T.aiFishCanEatEachOther && level.aiCanEat && simClock >= T.aiEatingGracePeriod

        for i in 0..<(candidates.count - 1) {
            for j in (i + 1)..<candidates.count {
                let a = candidates[i], b = candidates[j]
                guard a.state == .swimming, b.state == .swimming else { continue }
                // The tutorial's wall only eats you, never its meals.
                if isTutorial && !a.isPlayer && !b.isPlayer && (tutorialWall.contains(a.id) || tutorialWall.contains(b.id)) { continue }
                let protectedPair = !a.isPlayer && !b.isPlayer && (encounterProtected(a.id) || encounterProtected(b.id))
                if !a.isPlayer && !b.isPlayer && !aiMayEat && !protectedPair { continue }

                let dx = world.delta(from: a.position.x, to: b.position.x)
                let dy = b.position.y - a.position.y
                let reach = (a.radius + b.radius) * T.collisionScale
                guard dx * dx + dy * dy < reach * reach else { continue }
                if protectedPair {
                    // Kelp Forest fish swimming in to their meetings pass each other rather than be pushed off course.
                    let approaching = approachEnds[a.id] != nil || approachEnds[b.id] != nil
                    if level.meetingPlan == nil || plannedPairSeparates(a, b) && !approaching {
                        separateProtectedFish(a, b, dx: dx, dy: dy)
                    }
                    continue
                }

                let encounter = GameRules.encounter(a.radius, b.radius, firstIsPlayer: a.isPlayer, secondIsPlayer: b.isPlayer)
                #if DEBUG
                // A bot safe from fish passes through a bigger one.
                if simulationSafeFromFish && (encounter == .firstEatsSecond && b.isPlayer || encounter == .secondEatsFirst && a.isPlayer
                                              || encounter == .tooClose && (a.isPlayer || b.isPlayer)) { continue }
                #endif
                switch encounter {
                case .firstEatsSecond: beginSwallow(predator: a, prey: b)
                case .secondEatsFirst: beginSwallow(predator: b, prey: a)
                case .tooClose: bump(a, b, dx: dx, dy: dy, reach: reach)
                }
            }
        }
    }

    /// Off screen, a planned fish you haven't met passes jellies by, like it passes other unmet fish, so
    /// bells can't throw its meeting off; on screen it steers and bounces as usual.
    private func plannedFishMeetsJellies(_ f: Fish) -> Bool {
        level.meetingPlan == nil || f.isPlayer || !encounterProtected(f.id) || plannedContactVisible(f.position.x)
    }

    /// Off screen, two planned fish you haven't met pass each other so their meetings stay on time.
    private func plannedPairSeparates(_ a: Fish, _ b: Fish) -> Bool {
        guard encounterProtected(a.id) && encounterProtected(b.id) else { return true }
        let visible = plannedContactVisible(a.position.x) || plannedContactVisible(b.position.x)
        #if DEBUG
        if visible { debugVisibleUnmetContacts += 1 }
        #endif
        return visible
    }

    /// Whether a contact at `x` could be seen, with room for the steering look-ahead.
    private func plannedContactVisible(_ x: CGFloat) -> Bool {
        let dx = world.delta(from: player.position.x, to: x)
        return dx > -size.width * T.playerScreenX / zoom - T.plannedContactScreenMargin
            && dx < size.width * (1 - T.playerScreenX) / zoom + T.plannedContactScreenMargin
    }

    /// Protected fish visibly yield rather than crossing through one another.
    /// Horizontal separation works even when both swimmers are against a water boundary.
    private func separateProtectedFish(_ a: Fish, _ b: Fish, dx: CGFloat, dy: CGFloat) {
        let direction: CGFloat = abs(dx) > 0.001 ? (dx > 0 ? 1 : -1) : (a.id < b.id ? 1 : -1)
        let bodyReach = (a.radius + b.radius) * T.collisionScale
        let gap = sqrt(max(0, bodyReach * bodyReach - dy * dy)) + T.protectedFishContactPadding
        let shift = max(0, gap - abs(dx)) / 2
        if level.meetingPlan != nil, encounterProtected(a.id) != encounterProtected(b.id) {
            // A fish you haven't met holds its planned line; the fish you've passed turns away instead.
            let mover = encounterProtected(a.id) ? b : a
            let away = mover === a ? -direction : direction
            mover.position.x = world.wrap(mover.position.x + away * 2 * shift)
            mover.heading = away
            mover.velocity.dx = away * max(abs(mover.velocity.dx), mover.cruiseSpeed)
            mover.turnTimer = max(mover.turnTimer, T.protectedFishTurnHoldSeconds)
            #if DEBUG
            recordRunEvent("ai_avoidance_contact", fields: ["firstID": a.id, "secondID": b.id, "yieldingID": mover.id])
            #endif
            return
        }
        a.position.x = world.wrap(a.position.x - direction * shift)
        b.position.x = world.wrap(b.position.x + direction * shift)
        // Turn an approaching fish, leaving a swimmer that's already moving away alone.
        // For head-on contacts the faster fish yields and swims away ahead of the other.
        let approachingA = a.velocity.dx * direction > 0
        let approachingB = b.velocity.dx * direction < 0
        let yieldsA = approachingA != approachingB ? approachingA
            : (a.cruiseSpeed > b.cruiseSpeed || (a.cruiseSpeed == b.cruiseSpeed && a.id < b.id))
        let yielding = yieldsA ? a : b
        let away = yieldsA ? -direction : direction
        yielding.heading = away
        yielding.velocity.dx = away * max(abs(yielding.velocity.dx), yielding.cruiseSpeed)
        yielding.turnTimer = max(yielding.turnTimer, T.protectedFishTurnHoldSeconds)
        #if DEBUG
        recordRunEvent("ai_avoidance_contact", fields: ["firstID": a.id, "secondID": b.id, "yieldingID": yielding.id])
        #endif
    }

    /// Near-equal fish gently drift apart vertically instead of producing an arbitrary winner.
    private func bump(_ a: Fish, _ b: Fish, dx: CGFloat, dy: CGFloat, reach: CGFloat) {
        let dir: CGFloat = dy >= 0 ? 1 : -1 // b is above a when positive
        let push: CGFloat = 4
        if a.isPlayer {
            b.position.y += dir * push
            a.velocity.dy -= dir * 60
        } else if b.isPlayer {
            a.position.y -= dir * push
            b.velocity.dy += dir * 60
        } else {
            a.position.y -= dir * push / 2
            b.position.y += dir * push / 2
        }
        for f in [a, b] where !f.isPlayer {
            f.position.y = f.position.y.clamped(waterBottom + f.radius, max(waterBottom + f.radius, waterTop - f.radius))
        }
    }

    private func beginSwallow(predator: Fish, prey: Fish) {
        if isTutorial && predator.isPlayer && prey.id == tutorialMeal {
            tutorialMealWasEaten = true
        }
        if isTutorial && predator.isPlayer && tutorialWall.contains(prey.id) && tutorialWallBreach == nil { tutorialWallBreach = prey.id }
        if prey.isPlayer && metricAccumulator != nil {
            observeMetrics()
            metricDeathCause = "predator"
            metricAccumulator?.fatal(ratio: Double(predator.radius / prey.radius))
            fatalMetrics = metricAccumulator?.summary
            finishMetrics("death") // The fatal interaction is committed; do not reclassify its animation as a quit.
        }
        #if DEBUG
        if predator.isPlayer { mealLog.append((prey.id, simClock)) }
        recordRunEvent("swallow_start", fields: ["predatorID": predator.id, "preyID": prey.id,
                                                "predatorRadius": predator.radius, "preyRadius": prey.radius])
        noteHitch(.swallow, prey.isPlayer ? "you're eaten" : predator.isPlayer ? "you eat" : "fish eats fish")
        #endif
        predator.state = .swallowing(preyID: prey.id)
        prey.state = .beingSwallowed(predatorID: predator.id)
        let ratio = prey.radius / predator.radius
        swallows.append(Swallow(
            predatorID: predator.id,
            preyID: prey.id,
            duration: SwallowTiming.duration(sizeRatio: ratio, curve: T.swallowDurationCurve),
            ratio: ratio,
            startOffset: CGVector(
                dx: world.delta(from: predator.position.x, to: prey.position.x),
                dy: prey.position.y - predator.position.y
            )
        ))
        if let predatorNode = nodes[predator.id], let preyNode = nodes[prey.id] {
            preyNode.zPosition = predatorNode.zPosition - 0.25
        }

        observeMetrics()
        guard predator.isPlayer || prey.isPlayer else { return }
        if ratio >= T.slowMoRatio {
            slowMoFactor = T.closeCallSlowFactor
            slowMoRemaining = T.closeCallSlowDuration
        }
        if prey.isPlayer { buzz(.eaten) }
    }

    private func advanceSwallows(_ dt: CGFloat) {
        var finished: [Int] = []
        for i in swallows.indices {
            swallows[i].elapsed += dt
            let s = swallows[i]
            guard let predator = fishByID[s.predatorID], let prey = fishByID[s.preyID] else { continue }

            let t = min(1, s.elapsed / s.duration)
            let eased = t * t * (3 - 2 * t)
            let dir: CGFloat = predator.facing >= 0 ? 1 : -1
            let mouth = CGVector(dx: dir * predator.radius * 1.05, dy: -predator.radius * 0.1)
            let ox = s.startOffset.dx + (mouth.dx - s.startOffset.dx) * eased
            let oy = s.startOffset.dy + (mouth.dy - s.startOffset.dy) * eased
            prey.position = CGPoint(x: world.wrap(predator.position.x + ox), y: predator.position.y + oy)
            prey.shrink = 1 - 0.9 * eased

            let closeness = ((s.ratio - 0.7) / 0.3).clamped(0, 1)
            prey.struggle = closeness * (1 - t)
            predator.squash = closeness * 0.09 * sin(s.elapsed * 30) * (1 - t)
            predator.chew = closeness * (1 - t)

            if t >= 1 { finished.append(i) }
        }
        for i in finished.reversed() {
            completeSwallow(swallows.remove(at: i))
        }
    }

    private func completeSwallow(_ s: Swallow) {
        guard let predator = fishByID[s.predatorID], let prey = fishByID[s.preyID] else { return }
        #if DEBUG
        let mealWorkStarted = ProcessInfo.processInfo.systemUptime
        defer {
            let workSeconds = ProcessInfo.processInfo.systemUptime - mealWorkStarted
            if workSeconds > Double(T.debugMealHitchSeconds) {
                recordRunEvent("meal_hitch", fields: ["workSeconds": workSeconds,
                    "predatorID": s.predatorID, "preyID": s.preyID, "sizeRatio": s.ratio])
            }
        }
        #endif

        removeFish(prey)

        predator.state = .swimming
        predator.squash = 0
        predator.chew = 0
        predator.targetRadius = GameRules.grownRadius(
            predator: predator.targetRadius, prey: prey.radius, efficiency: level.effectiveAbsorptionEfficiency
        )
        predator.growFrom = predator.radius
        predator.growElapsed = 0
        predator.pulse = T.pulseDuration
        #if DEBUG
        recordRunEvent("eat", fields: ["predatorID": predator.id, "preyID": prey.id,
                                      "preyRadius": prey.radius, "radiusAfter": predator.targetRadius])
        #endif

        if !prey.isPlayer { metricAccumulator?.meal(player: predator.isPlayer, ratio: Double(s.ratio)) }
        observeMetrics()
        if predator.isPlayer {
            mealsEaten += 1
            playSound(.eat)
        }
        // Every meal is felt: a light tap, or a sharper one for a close call.
        if predator.isPlayer { buzz(s.ratio >= T.closeCallRatio ? .closeCall : .meal) }
        if prey.isPlayer {
            #if DEBUG
            recordRunEvent("player_eaten", fields: ["predatorID": predator.id, "radius": predator.radius])
            #endif
            lose()
        } else if phase == .playing && hasWon {
            win()
        }
    }

    // MARK: - Rendering

    private func capturePresentation() {
        previousPresentation = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, FishPresentation($0)) })
        previousJellyPositions = jellies.map(\.position)
        previousZoom = zoom
    }

    private var presentationFraction: CGFloat {
        PresentationInterpolation.fraction(simulationRemainder: simulationAccumulator,
            frameRemainder: frameAccumulator, timeScale: timeScale, step: T.simulationStep)
    }

    private func presentationPose(_ fish: Fish, fraction: CGFloat) -> FishPresentation {
        let current = FishPresentation(fish)
        return previousPresentation[fish.id]?.interpolated(to: current, fraction: fraction, world: world) ?? current
    }

    private func render() -> (cameraX: CGFloat, zoom: CGFloat) {
        let fraction = presentationFraction
        let zoom = previousZoom + (self.zoom - previousZoom) * fraction
        let time = realClock + frameAccumulator
        let cameraX = presentationPose(player, fraction: fraction).position.x
        let anchorX = size.width * T.playerScreenX
        renderJellies(cameraX: cameraX, zoom: zoom, fraction: fraction, time: time)
        renderKelp(cameraX: cameraX, zoom: zoom, time: time)
        renderHooks(cameraX: cameraX, zoom: zoom, fraction: fraction, time: time)
        for f in fish {
            // A stung fish, or you on a hook, is drawn by its own animation.
            guard let node = nodes[f.id], !stungFish.contains(where: { $0.id == f.id }), !(f.isPlayer && reel != nil) else { continue }
            let pose = presentationPose(f, fraction: fraction)
            let screenX = anchorX + world.delta(from: cameraX, to: pose.position.x) * zoom
            let margin = pose.radius * zoom * 3
            node.isHidden = screenX < -margin || screenX > size.width + margin
            if node.isHidden { continue }
            node.position = CGPoint(x: screenX, y: waterCenter + (pose.position.y - waterCenter) * zoom)
            if !kelpBeds.isEmpty && !f.isPlayer {
                // In steps of a twentieth, so a fish is only recolored while it's crossing an edge.
                let shade = (kelpShade(pose.position, radius: pose.radius) * 20).rounded() / 20
                if shade != silhouetteShade[f.id] ?? 0 {
                    silhouetteShade[f.id] = shade > 0 ? shade : nil
                    setSilhouette(node, shade)
                }
            }

            var stretch: CGFloat = 1
            if pose.pulse > 0 {
                stretch += sin((1 - pose.pulse / T.pulseDuration) * .pi) * T.pulseAmount
            }
            let stretchX = stretch * (1 + pose.squash) * pose.shrink
            let stretchY = stretch * (1 - pose.squash) * pose.shrink

            let rawTilt = f.isPlayer
                ? pose.velocity.dy * zoom / T.motion.maxRiseSpeed * T.motion.maxTilt
                : pose.velocity.dy / roamingVerticalSpeed * T.aiMaxTilt
            let facingSign: CGFloat = pose.facing >= 0 ? 1 : -1
            let tilt = rawTilt.clamped(-T.motion.maxTilt, T.motion.maxTilt) * facingSign
                + pose.struggle * sin(time * 45) * 0.35

            // Close calls chew: the mouth works while the prey struggles.
            let mouth = pose.mouth * (1 - 0.35 * pose.chew * (0.5 + 0.5 * sin(time * 38)))

            node.apply(
                radius: pose.radius * zoom, facing: pose.facing, tilt: tilt,
                stretchX: stretchX, stretchY: stretchY, mouthOpen: mouth,
                time: time, tailRate: f.isPlayer ? 14 : 9
            )
            if let lure = node.childNode(withName: Self.anglerLureName) {
                // Turned and scaled like the fish's own rig, so the stalk grows from its forehead.
                let flip = (pose.facing < 0 ? -1 : 1) * max(abs(pose.facing), 0.05)
                let scale = pose.radius * zoom / FishNode.referenceRadius
                lure.xScale = scale * stretchX * flip
                lure.yScale = scale * stretchY
                lure.zRotation = tilt
                if let light = lure.childNode(withName: Self.anglerLightName) {
                    light.xScale = 1 / lure.xScale
                    light.yScale = 1 / lure.yScale
                }
            }
            if f.isPlayer, let headlamp {
                // Strapped to your head, pointing where you're swimming: rising or falling fast swings it off the
                // far right of the screen.
                let r = pose.radius * zoom
                headlamp.position = CGPoint(x: node.position.x + r * (0.75 * cos(tilt) - 0.3 * sin(tilt)),
                                            y: node.position.y + r * (0.75 * sin(tilt) + 0.3 * cos(tilt)))
                headlamp.zRotation = (pose.velocity.dy * zoom / T.motion.maxRiseSpeed).clamped(-1, 1) * T.headlampMaxTilt
            }
        }
        renderStungFish(cameraX: cameraX, zoom: zoom, time: time)
        if let glow = winGlow, let playerNode = nodes[player.id] {
            glow.position = playerNode.position
        }
        return (cameraX, zoom)
    }

    /// A jolt with sparks, then the fish rolls belly-up and sinks as it fades.
    private func renderStungFish(cameraX: CGFloat, zoom: CGFloat, time: CGFloat) {
        guard !stungFish.isEmpty else { return }
        func ease(_ t: CGFloat) -> CGFloat { let t = t.clamped(0, 1); return t * t * (3 - 2 * t) }
        for stung in stungFish {
            let elapsed = time - stung.start
            let jolting = elapsed < T.stingJoltSeconds
            let limp = max(0, elapsed - T.stingJoltSeconds)
            let roll = ease(limp / T.stingRollSeconds)
            let shake = jolting ? CGPoint(x: sin(time * 97) * 2.5, y: cos(time * 83) * 2.5) : .zero
            let sink = limp * (22 + 18 * limp)
            let x = size.width * T.playerScreenX + world.delta(from: cameraX, to: stung.position.x) * zoom
            stung.node.position = CGPoint(x: x + shake.x,
                                          y: waterCenter + (stung.position.y - waterCenter) * zoom - sink + shake.y)
            stung.node.alpha = 1 - ease((elapsed - T.stingFadeStart) / (T.stingSeconds - T.stingFadeStart))
            let buzz = jolting ? sin(time * 53) * 0.1 : 0
            stung.node.apply(radius: stung.radius * zoom, facing: stung.facing,
                             tilt: jolting ? sin(time * 61) * 0.3 : -0.3 * roll * stung.facing,
                             stretchX: 1 + buzz, stretchY: jolting ? 1 - buzz : cos(roll * .pi),
                             mouthOpen: jolting ? 0.7 : 0.3, time: jolting ? time : stung.start,
                             tailRate: jolting ? 40 : 0)
            stung.zap.isHidden = !jolting
            stung.zap.position = stung.node.position
            if jolting { stung.zap.update(time: time, radius: stung.radius * zoom) }
        }
        for stung in stungFish where time - stung.start >= T.stingSeconds {
            stung.zap.removeFromParent()
            // The player's node stays for the next run's reset; anyone else's goes now.
            if stung.id != player.id { stung.node.removeFromParent() } else { stung.node.isHidden = true }
        }
        stungFish.removeAll { time - $0.start >= T.stingSeconds && $0.id != player.id }
    }

    private func updateSpecks(realDt: CGFloat, cameraDelta: CGFloat) {
        let w = size.width, h = size.height
        for speck in specks {
            var p = speck.node.position
            p.x -= cameraDelta * speck.parallax
            p.y += speck.rise * realDt
            if p.x < -8 { p.x += w + 16 } else if p.x > w + 8 { p.x -= w + 16 }
            if p.y > h + 8 { p.y = -8 }
            speck.node.position = p
        }
    }

    // MARK: - Static layout

    private func layoutStatic() {
        backgroundLayer.removeAllChildren()
        specks.removeAll()
        layoutHeadlamp()

        let gradient = SKSpriteNode(texture: arcadeWorld.hasJellies
                                    ? ArcadeArt.bloomWater(night: level.jellies?.night == true)
                                    : arcadeWorld == .kelpForest ? ArcadeArt.kelpWater()
                                    : arcadeWorld == .sunsetCove ? ArcadeArt.sunsetWater() : WaterTextures.gradient())
        gradient.anchorPoint = .zero
        gradient.size = size
        backgroundLayer.addChild(gradient)
        layoutSunset()

        let surface = SKSpriteNode(color: SKColor(white: 1, alpha: 0.22), size: CGSize(width: size.width, height: 2))
        surface.anchorPoint = .zero
        surface.position = CGPoint(x: 0, y: screenWaterTop + 4)
        surface.zPosition = 1
        backgroundLayer.addChild(surface)

        var speckRNG = SeededGenerator(seed: 7)
        let dot = WaterTextures.dot()
        for _ in 0..<55 {
            let parallax = CGFloat.random(in: 0.15...0.7, using: &speckRNG)
            let node = SKSpriteNode(texture: dot)
            let d = 1.5 + parallax * 4
            node.size = CGSize(width: d, height: d)
            node.alpha = 0.12 + parallax * 0.3
            node.position = CGPoint(
                x: CGFloat.random(in: 0...size.width, using: &speckRNG),
                y: CGFloat.random(in: 0...size.height, using: &speckRNG)
            )
            node.zPosition = 1
            backgroundLayer.addChild(node)
            specks.append(Speck(node: node, parallax: parallax, rise: CGFloat.random(in: 4...14, using: &speckRNG)))
        }

        dimNode.size = size
        dimNode.position = CGPoint(x: size.width / 2, y: size.height / 2)

        // Right of center so the player (at 30% width) stays visible behind messages.
        messageNode.position = CGPoint(x: size.width * 0.63, y: size.height / 2)
        buildPauseButton()
        buildPauseMenu()
    }

    /// World and current level only; reference presets use the same header.
    private func buildLevelIndicator() {
        levelIndicator.removeAllChildren()
        if isTutorial { return }
        // "Shallow Reef 2 3" would read as one number; spell out its level.
        let heading = "\(arcadeWorld.title) \(levelIndex + 1)"
        let text = label(plannerName ?? heading, fontSize: 13, heavy: true)
        text.horizontalAlignmentMode = .left
        text.alpha = 0.9
        levelIndicator.addChild(text)
        levelIndicator.position = CGPoint(x: 64, y: size.height - 36)
    }

    private func buildPauseButton() {
        pauseButton.removeAllChildren()
        let circle = SKShapeNode(circleOfRadius: 20)
        circle.fillColor = SKColor(white: 0, alpha: 0.25)
        circle.strokeColor = SKColor(white: 1, alpha: 0.5)
        circle.lineWidth = 1.5
        // Under its bars: the scene ignores sibling order, and its dark fill drawn last would dim them.
        circle.zPosition = -1
        pauseButton.addChild(circle)
        for x in [-5.0, 5.0] {
            let bar = SKShapeNode(rect: CGRect(x: x - 2.5, y: -8, width: 5, height: 16), cornerRadius: 1.5)
            bar.fillColor = SKColor(white: 1, alpha: 0.85)
            bar.strokeColor = .clear
            pauseButton.addChild(bar)
        }
        pauseButton.position = CGPoint(x: size.width - 64, y: size.height - 36)
    }

    /// The pause menu, in Settings' language: its deep-blue backdrop over the paused game, "Paused" and the level, then
    /// two columns: Play (Resume as the game's gold button, then Restart level and Level map) and Sound (the switches).
    /// Built with the scene and on each pause; pausing sets the switches to the current settings.
    private func buildPauseMenu() {
        pauseMenu.removeAllChildren()
        let backdrop = MenuBackdrop.node(size: size)
        backdrop.name = "pauseBackdrop"
        pauseMenu.addChild(backdrop)

        let title = label("Paused", fontSize: 28, heavy: true)
        title.position = CGPoint(x: size.width / 2, y: size.height - 80)
        pauseMenu.addChild(title)
        if !isTutorial {
            let subtitle = label(plannerName ?? "\(arcadeWorld.title) \(levelIndex + 1)", fontSize: 14, heavy: false)
            subtitle.alpha = 0.65
            subtitle.position = CGPoint(x: size.width / 2, y: size.height - 106)
            pauseMenu.addChild(subtitle)
        }

        let width = MenuSwitchRow.size.width, gap: CGFloat = 40
        let left = size.width / 2 - (width + gap) / 2, right = size.width / 2 + (width + gap) / 2
        let headingY = size.height - 158
        func rowY(_ row: Int) -> CGFloat { headingY - 34 - CGFloat(row) * 54 }
        for (text, x) in [("Play", left), ("Sound", right)] {
            let heading = menuHeading(text)
            heading.position = CGPoint(x: x - width / 2, y: headingY)
            pauseMenu.addChild(heading)
        }
        for (row, button) in [resumeButton, restartButton, mapButton].enumerated() {
            button.removeFromParent()
            button.position = CGPoint(x: left, y: rowY(row))
            pauseMenu.addChild(button)
        }
        for (row, toggle) in [effectsButton, musicButton, vibrationButton].enumerated() {
            toggle.removeFromParent()
            toggle.position = CGPoint(x: right, y: rowY(row))
            pauseMenu.addChild(toggle)
        }
        refreshSoundToggles()
    }

    /// The switches as the settings stand, each time the game pauses (Settings may have changed them since).
    private func refreshSoundToggles() {
        effectsButton.setOn(settings.soundEffectsOn, animated: false)
        musicButton.setOn(settings.musicOn, animated: false)
        vibrationButton.setOn(settings.vibrationOn, animated: false)
    }

    private func toggleVibration() {
        settings.vibrationOn.toggle()
        vibrationButton.setOn(settings.vibrationOn, animated: true)
        configurePauseAccessibility()
    }

    private func toggleSound(effects: Bool) {
        if effects { settings.soundEffectsOn.toggle() } else { settings.musicOn.toggle() }
        effectsButton.setOn(settings.soundEffectsOn, animated: true)
        musicButton.setOn(settings.musicOn, animated: true)
        configurePauseAccessibility()
    }

    /// VoiceOver reaches the pause menu's actions and sound switches, like the result panel's controls.
    private func configurePauseAccessibility() {
        guard let view, phase == .paused else { return }
        view.isAccessibilityElement = false
        isAccessibilityElement = false
        func element(_ node: SKNode, _ label: String, value: String? = nil,
                     _ action: @escaping (GameScene) -> Void) -> UIAccessibilityElement {
            let element = ArcadeResultAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = label
            element.accessibilityValue = value
            element.accessibilityTraits = .button
            let box = node.calculateAccumulatedFrame()
            let lower = convertPoint(toView: convert(CGPoint(x: box.minX, y: box.minY), from: node.parent ?? self))
            let upper = convertPoint(toView: convert(CGPoint(x: box.maxX, y: box.maxY), from: node.parent ?? self))
            element.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(
                CGRect(x: min(lower.x, upper.x), y: min(lower.y, upper.y), width: abs(upper.x - lower.x), height: abs(upper.y - lower.y)),
                in: view)
            element.activate = { [weak self] in
                guard let self, self.phase == .paused else { return false }
                action(self)
                return true
            }
            return element
        }
        accessibilityElements = [
            element(resumeButton, "Resume") { $0.setPhase(.playing) },
            element(restartButton, "Restart level") { $0.replayLevel() },
            element(mapButton, "Level map") { scene in
                #if DEBUG
                scene.finishRunRecording("level_map")
                #endif
                scene.onExit?()
            },
            element(effectsButton, "Sound effects", value: settings.soundEffectsOn ? "On" : "Off") { $0.toggleSound(effects: true) },
            element(musicButton, "Music", value: settings.musicOn ? "On" : "Off") { $0.toggleSound(effects: false) },
            element(vibrationButton, "Vibration", value: settings.vibrationOn ? "On" : "Off") { $0.toggleVibration() },
        ]
    }

    /// `progress`: the world's pips and crown, under the title.
    private func showMessage(_ title: String, lines: [String], delay: TimeInterval = 0, progress: WorldProgressStrip? = nil) {
        #if DEBUG
        noteHitch(.card, "ready card")
        #endif
        messageNode.removeAllActions()
        messageNode.removeAllChildren()

        let titleLabel = label(title, fontSize: 40, heavy: true)
        let lineLabels = lines.map { label($0, fontSize: 19, heavy: false) }
        let start = label("Tap to start", fontSize: 22, heavy: true)
        start.name = "beginPrompt"
        let maxTextWidth = max(240, (size.width - messageNode.position.x - 28) * 2 - 70)
        for text in [titleLabel, start] + lineLabels + [progress?.caption].compactMap({ $0 }) where text.frame.width > maxTextWidth {
            text.fontSize *= maxTextWidth / text.frame.width
        }
        let lineSpacing: CGFloat = 30
        let progressHeight: CGFloat = progress.map { $0.depth + 24 } ?? 0
        let height = (lines.isEmpty ? 130 : 150) + CGFloat(lines.count) * lineSpacing + progressHeight
        let width = max(titleLabel.frame.width, start.frame.width, lineLabels.map(\.frame.width).max() ?? 0,
                        progress?.width ?? 0) + 70

        let panel = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        panel.fillColor = SKColor(white: 0, alpha: 0.3)
        panel.strokeColor = .clear
        panel.name = "readyCard"
        // Under its text: the scene ignores sibling order, so the same depth could draw it over them.
        panel.zPosition = -1
        messageNode.addChild(panel)

        var y = height / 2 - 45
        titleLabel.position = CGPoint(x: 0, y: y)
        messageNode.addChild(titleLabel)
        y -= 45
        if let progress {
            progress.position = CGPoint(x: 0, y: y + 4)
            messageNode.addChild(progress)
            y -= progressHeight
        }
        for line in lineLabels {
            line.position = CGPoint(x: 0, y: y)
            messageNode.addChild(line)
            y -= lineSpacing
        }
        start.position = CGPoint(x: 0, y: -height / 2 + 30)
        messageNode.addChild(start)

        messageNode.alpha = 0
        messageNode.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.25)]))
    }

    /// Before playing a level again: just the prompt, small, on its own.
    private func showStartPrompt() {
        #if DEBUG
        noteHitch(.card, "tap to start")
        #endif
        messageNode.removeAllActions()
        messageNode.removeAllChildren()
        let start = label("Tap to start", fontSize: 22, heavy: true)
        start.name = "beginPrompt"
        let pill = SKShapeNode(rectOf: CGSize(width: start.frame.width + 44, height: 48), cornerRadius: 24)
        pill.fillColor = SKColor(white: 0, alpha: 0.3)
        pill.strokeColor = .clear
        pill.name = "startPrompt"
        pill.zPosition = -1
        messageNode.addChild(pill)
        messageNode.addChild(start)
        messageNode.alpha = 0
        messageNode.run(.fadeIn(withDuration: 0.2))
    }

    private func hideMessage() {
        resultPanel = nil
        messageNode.removeAllActions()
        messageNode.run(.fadeOut(withDuration: 0.15))
    }

    private func label(_ text: String, fontSize: CGFloat, heavy: Bool) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: heavy ? "AvenirNext-Heavy" : "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
    #if DEBUG
    /// Where the hitch log says a slow frame happened: the level (or the tutorial's beat) and its phase.
    var hitchContext: HitchContext {
        isTutorial ? HitchContext(.tutorial, detail: String(describing: tutorialBeat), phase: phase.name)
            : HitchContext(.level, detail: "\(arcadeWorld.rawValue).\(levelIndex + 1)", phase: phase.name)
    }

    /// Notes what just happened, for the hitch log: from a scene on screen, not a headless study.
    private func noteHitch(_ kind: HitchEvent.Kind, _ detail: String = "") {
        guard view != nil, !simulationHeadless else { return }
        hitchLog?.note(kind, detail)
    }

    /// A slow frame during a recorded run goes into its recording, with the run's state.
    private func recordRunHitch(_ fields: [String: Any]) {
        var fields = fields
        fields["playerMeals"] = mealsEaten
        fields["fishCount"] = fish.count
        fields["timeScale"] = timeScale
        recordRunEvent("hitch", fields: fields)
    }

    // JSONL uses world coordinates; screen projection is defined by the snapshot's camera.
    private func recordRunEvent(_ name: String, fields: [String: Any] = [:]) {
        runRecorder?.event(name, time: Double(realClock - recordingStartedAt), simulationTime: Double(simClock), fields: fields)
        if ["bounce", "swallow_start", "hazard_death"].contains(name) { recordRunSnapshot(force: true) }
    }

    private func startRunRecording() {
        recordingStartedAt = realClock
        runRecorder = ArcadeRunRecorder.makeDefault()
        if runRecorder != nil, view != nil { hitchLog?.runRecording = { [weak self] in self?.recordRunHitch($0) } }
        recordRunEvent("start", fields: ["schema": 1, "world": arcadeWorld.rawValue, "level": levelIndex + 1,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "configuration": ["spawnSeed": String(ecosystemSeed),
                "aiMovementRandomVersion": 1,
                "protectedContactVersion": 1,
                "simulationStepSeconds": T.simulationStep, "maximumFrameElapsedSeconds": T.maximumFrameElapsed,
                "encounterForwardDistance": forwardDistance,
                "aiSurvivesTentacles": true,
                "aiCanEat": level.aiCanEat, "playerWinsTies": true, "absorptionEfficiency": level.effectiveAbsorptionEfficiency,
                "mealGrowthScale": T.mealGrowthScale, "practiceRun": debugPracticeRun,
                "configuredFishCount": level.meetingPlan?.fish.count ?? 0,
                "jellyCount": level.jellies?.count ?? 0,
                "screenCrossSeconds": level.screenCrossSeconds,
                "bounceSpeed": T.jellyBounceSpeed, "jellyRadius": level.jellies?.radius ?? 0,
                "tentacleLength": level.jellies?.tentacleLength ?? 0,
                "aiSpeedMin": level.aiSpeedRange.lowerBound, "aiSpeedMax": level.aiSpeedRange.upperBound,
                "aiVerticalSpeed": level.aiVerticalSpeed,
                "meetingPlan": recordedMeetingPlan()]])
        recordRunSnapshot(force: true)
    }

    /// Each planned fish's role and route numbers, so recordings can say which gate you missed.
    private func recordedMeetingPlan() -> [String: Any] {
        guard let plan = level.meetingPlan else { return [:] }
        let fish: [[String: Any]] = plan.fish.map { fish in
            let meeting = plan.analysis.meeting(fishID: fish.id)
            return ["id": fish.id, "role": fish.role.rawValue, "segment": fish.segment + 1,
                    "fork": fish.fork.map { $0 + 1 } ?? 0, "lane": fish.fork == nil ? "" : (fish.lane == 0 ? "long" : "short"),
                    "radius": fish.radius, "meetingDistance": fish.meetingDistance, "headOn": fish.headOn,
                    "minimumMeals": meeting?.minimumMeals ?? -1, "routes": meeting?.routes ?? 0,
                    "robustSlack": meeting?.robustSlack ?? -1, "danger": meeting?.danger ?? false]
        }
        var recorded: [String: Any] = ["name": plan.spec.name, "variation": plan.variation, "issues": plan.issues, "fish": fish]
        if let hooks = plan.hooks {
            recorded["hooks"] = hooks.map { ["motion": $0.motion.rawValue, "role": $0.role.rawValue, "passTime": $0.passTime,
                                            "baitRadius": $0.baitRadius] as [String: Any] }
        }
        return recorded
    }

    private func recordRunSnapshot(force: Bool = false) {
        guard let runRecorder, force || runRecorder.wantsSnapshot(time: Double(realClock - recordingStartedAt)) else { return }
        let fishStates: [[String: Any]] = fish.map { f in
            ["id": f.id, "player": f.isPlayer, "state": String(describing: f.state),
             "x": f.position.x, "y": f.position.y, "vx": f.velocity.dx, "vy": f.velocity.dy,
             "radius": f.radius, "targetRadius": f.targetRadius]
        }
        let jellyStates: [[String: Any]] = jellies.enumerated().map { ["id": $0.offset, "x": $0.element.position.x, "y": $0.element.position.y] }
        var fields: [String: Any] = [
            "phase": String(describing: phase), "holding": isHolding, "zoom": zoom, "timeScale": timeScale,
            "worldWidth": world.width, "screenWidth": size.width, "screenHeight": size.height,
            "cameraX": player.position.x, "forwardDistance": forwardDistance, "playerScreenX": T.playerScreenX, "waterCenter": waterCenter,
            "waterBottom": waterBottom, "waterTop": waterTop, "fish": fishStates, "jellies": jellyStates]
        if !hookRigs.isEmpty {
            fields["hooks"] = hookRigs.enumerated().map { index, rig -> [String: Any] in
                let at = hookPosition(rig.hook, time: simClock)
                return ["id": index, "x": at.x, "y": at.y, "baitRadius": rig.hook.baitRadius, "motion": rig.hook.motion.rawValue]
            }
        }
        runRecorder.snapshot(time: Double(realClock - recordingStartedAt), simulationTime: Double(simClock), fields: fields, force: force)
    }

    private func finishRunRecording(_ outcome: String, fields: [String: Any] = [:]) {
        guard let runRecorder else { return }
        hitchLog?.runRecording = nil
        recordRunSnapshot(force: true)
        var summary = fields
        summary["playerMeals"] = mealsEaten
        summary["playerRadius"] = player?.radius ?? 0
        summary["fishRemaining"] = fish.filter { !$0.isPlayer && $0.state != .removed }.count
        runRecorder.finish(outcome: outcome, time: Double(realClock - recordingStartedAt), simulationTime: Double(simClock), fields: summary)
        self.runRecorder = nil
    }

    /// Plays the level with one of `ArcadeSimulation`'s bots on the real controls, without presentation, audio,
    /// recording, or touches, until it's won, lost, or `limit` seconds have passed.
    func debugSimulate(policy: ArcadeSimulation.Policy, limit: CGFloat = 75) -> ArcadeSimulation.Result {
        simulationHeadless = true
        simulationEcologyProbe = false
        simulationHolding = false
        resetGame(startPlaying: true)
        var nextDecision: CGFloat = 0
        while phase == .playing && simClock < limit {
            if simClock >= nextDecision {
                let visible = fish.filter { !$0.isPlayer && $0.state == .swimming &&
                    abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width * 0.80 / zoom }
                func swimmer(_ f: Fish) -> ArcadeSimulation.Swimmer {
                    .init(x: f.position.x, y: f.position.y, vx: f.velocity.dx, vy: f.velocity.dy, radius: f.radius)
                }
                let bells = jellies.filter { abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width / zoom }
                    .map { ArcadeSimulation.Bell(x: $0.position.x, y: $0.position.y,
                        radius: level.jellies!.radius, tentacles: level.jellies!.tentacleLength) }
                simulationHolding = ArcadeSimulation.holding(.init(player: swimmer(player), fish: visible.map(swimmer),
                    bells: bells, width: world.width, screenWidth: size.width, zoom: zoom,
                    bottom: waterBottom, top: waterTop, speed: playerSpeed, bouncing: bounceRemaining > 0,
                    bounceSpeed: T.jellyBounceSpeed, hooks: botHooks), policy: policy)
                nextDecision = simClock + max(T.simulationStep, policy == .collector ? 0.16 : (policy == .cautious ? 0.10 : 0.08))
            }
            advanceFrame(T.simulationStep)
        }
        return .init(outcome: phase == .won ? "won" : (phase == .lost ? "lost" : "timeout"),
                     reason: phase == .lost ? lossReason : "", seconds: Double(simClock), playerMeals: mealsEaten)
    }

    /// Compare AI without player contacts. Isolated mode disables every collision,
    /// hazard, and camera update, so skipping another swimmer has no physical effect.
    func debugAuditRepeatability(frames: [CGFloat], isolatedAI: Bool = true,
                                 omittedIDs: Set<Int> = [], fixedZoom: CGFloat = 1,
                                 playerRadius: CGFloat = T.baseRadius, fixedStep: Bool = false,
                                 slowMotion: Bool = false, scriptedInput: Bool = false,
                                 removeOmittedFish: Bool = false) -> ArcadeSimulation.Audit {
        simulationHeadless = true
        simulationEcologyProbe = true
        simulationHolding = false
        resetGame(startPlaying: true)
        zoom = fixedZoom
        player.radius = playerRadius
        player.targetRadius = playerRadius
        if removeOmittedFish {
            for id in omittedIDs { if let omitted = fishByID[id] { removeFish(omitted) } }
        }
        if slowMotion {
            slowMoRemaining = T.closeCallSlowDuration
            slowMoFactor = T.closeCallSlowFactor
        }
        for dt in frames {
            if fixedStep {
                advanceFrame(dt) {
                    if scriptedInput { self.simulationHolding = Int(self.simClock * 4) % 2 == 0 }
                }
            } else if isolatedAI {
                simClock += dt
                for f in fish where !f.isPlayer && !omittedIDs.contains(f.id) { moveAI(f, dt) }
            } else {
                simulate(dt)
            }
        }
        return .init(seconds: Double(simClock), zoom: Double(zoom), waterBottom: Double(waterBottom),
                     waterTop: Double(waterTop), fish: fish.filter { (scriptedInput || !$0.isPlayer) && !omittedIDs.contains($0.id) }
            .sorted { $0.id < $1.id }.map {
                .init(id: $0.id, x: Double($0.position.x), y: Double($0.position.y),
                      vx: Double($0.velocity.dx), vy: Double($0.velocity.dy), radius: Double($0.radius),
                      targetY: Double($0.targetY), retargetTimer: Double($0.retargetTimer),
                      turnTimer: Double($0.turnTimer), state: String(describing: $0.state))
            })
    }

    var debugAIMovementStreamIDs: Set<Int> { Set(aiMovementRNGs.keys) }
    var debugGameplayClock: Double { Double(simClock) }

    func debugCheckPresentationIsolation() -> Bool {
        simulationHeadless = true
        simulationEcologyProbe = true
        simulationHolding = false
        resetGame(startPlaying: true)
        advanceFrame(T.simulationStep)
        let position = player.position
        let radius = player.radius
        let clock = simClock
        func nextDraws() -> [UInt64] {
            var streams = aiMovementRNGs
            return streams.keys.sorted().map { streams[$0]!.next() }
        }
        let randomControl = nextDraws()
        _ = render()
        let firstY = nodes[player.id]!.position.y
        frameAccumulator = T.simulationStep / 2
        _ = render()
        let secondY = nodes[player.id]!.position.y
        guard abs(firstY - secondY) > 1e-6, player.position == position, player.radius == radius, simClock == clock,
              !randomControl.isEmpty, nextDraws() == randomControl else { return false }
        setPhase(.paused)
        _ = render()
        let pausedY = waterCenter + (position.y - waterCenter) * zoom
        guard abs(nodes[player.id]!.position.y - pausedY) < 1e-4 else { return false }
        resetGame(startPlaying: true)
        _ = render()
        return previousPresentation.count == fish.count && abs(nodes[player.id]!.position.y - player.position.y) < 1e-4
    }

    func debugCheckFixedTimingLifecycle() -> Bool {
        simulationHeadless = true
        simulationEcologyProbe = true
        resetGame(startPlaying: true)
        let step = T.simulationStep
        advanceFrame(step / 2)
        guard simClock == 0 else { return false }
        advanceFrame(step / 2)
        guard abs(simClock - step) < 1e-10 else { return false }
        advanceFrame(step / 2)
        setPhase(.paused)
        let pausedClock = simClock
        advanceFrame(10)
        guard simClock == pausedClock else { return false }
        setPhase(.playing)
        advanceFrame(step / 2)
        guard simClock == pausedClock else { return false }
        advanceFrame(step / 2)
        guard abs(simClock - pausedClock - step) < 1e-10 else { return false }
        let beforeHitch = simClock
        advanceFrame(10)
        guard abs(simClock - beforeHitch - T.maximumFrameElapsed) < 1e-10 else { return false }
        advanceFrame(0)
        guard abs(simClock - beforeHitch - T.maximumFrameElapsed) < 1e-10 else { return false }
        resetGame(startPlaying: true)
        advanceFrame(step / 2)
        guard simClock == 0 else { return false }
        // Exercise SpriteKit timestamps too: a background gap must not be caught up
        // on the first resumed display frame.
        isBuilt = true
        resetGame(startPlaying: true)
        update(100)
        update(100 + Double(step))
        guard abs(simClock - step) < 1e-10 else { return false }
        setPhase(.paused)
        update(101)
        setPhase(.playing)
        update(1_000)
        guard abs(simClock - step) < 1e-10 else { return false }
        update(1_000 + Double(step))
        return abs(simClock - 2 * step) < 1e-10
    }

    // Integration-test fixtures exercise the real scene update and hazard resolution.
    func debugStart() { startRun() }
    /// Ends the run as if you'd been eaten.
    func debugLose() { lose() }
    /// Every bell landing this run: who, on which jelly, when, and where on screen.
    private(set) var debugBounces: [(fishID: Int, jelly: Int, time: CGFloat, screenX: CGFloat)] = []
    /// Plays the tutorial with a simple player on the real controls: it heads for the glowing meal, goes after the
    /// fish that outgrew it once it can eat it, and otherwise keeps away from anything bigger. Returns whether it
    /// finished, each beat it reached (with when), and how long it took.
    /// `greedy`: a player who goes after the missed fish's meals while it eats them.
    /// `missesAWallMeal`: a player who lets the wall's first meal go by. `from`: start at that beat (the size the beats
    /// before it make you). `lag`: a slower player, who steers for where things were that many seconds ago, and holds
    /// at least `lag` before changing their mind. `eatenOn`: on that beat, swims into the nearest bigger fish (how far you
    /// jump in a frame once caught is in `debugCaughtStep`). `letsTheLastFishGo`: doesn't chase the wall's last two.
    /// Ends when it's won or lost.
    func debugPlayTutorial(limit: CGFloat = 90, greedy: Bool = false, missesAWallMeal: Bool = false,
                           from start: ArcadeTutorial.Beat = .holdToRise, lag: CGFloat = 0, eatenOn: ArcadeTutorial.Beat? = nil,
                           letsTheLastFishGo: Bool = false,
                           onFrame: (() -> Void)? = nil) -> (finished: Bool, beats: [(beat: ArcadeTutorial.Beat, at: CGFloat)], seconds: CGFloat) {
        tutorialCheckpoint = start
        resetGame(startPlaying: true)
        debugCaughtStep = 0
        var lastX = player.position.x
        var beats: [(beat: ArcadeTutorial.Beat, at: CGFloat)] = [(tutorialBeat, 0)]
        var seen: [(at: CGFloat, target: CGFloat)] = []
        var holding = false, decidedAt: CGFloat = -1
        while simClock < limit && phase == .playing {
            let meal = tutorialMeal.flatMap { fishByID[$0] }
            let rival = tutorialMissedFish.flatMap { fishByID[$0] }
            let target: CGFloat
            if tutorialBeat == .holdToRise || tutorialBeat == .letGoToFall {
                target = tutorialBeat == .holdToRise ? waterTop : waterBottom
            } else if tutorialBeat == eatenOn, let threat = fish.filter({ !$0.isPlayer && $0.state == .swimming && $0.radius > player.radius })
                        .min(by: { abs(world.delta(from: player.position.x, to: $0.position.x)) < abs(world.delta(from: player.position.x, to: $1.position.x)) }) {
                target = threat.position.y
            } else if tutorialBeat == .lastFish && letsTheLastFishGo {
                target = (waterBottom + waterTop) / 2
            } else if tutorialBeat == .lastFish, let prey = fish.filter({ !$0.isPlayer && $0.state == .swimming && $0.radius < player.radius
                        && world.delta(from: player.position.x, to: $0.position.x) > -player.radius })
                        .min(by: { world.delta(from: player.position.x, to: $0.position.x) < world.delta(from: player.position.x, to: $1.position.x) }) {
                target = prey.position.y
            } else if tutorialBeat == .eatEnough,
                      let next = tutorialWallMeals.dropFirst(missesAWallMeal ? 1 : 0).compactMap({ fishByID[$0] })
                          .first(where: { $0.state == .swimming }) {
                target = next.position.y
            } else if greedy, tutorialBeat == .missedFishEats,
               let snack = tutorialMissedMeals.compactMap({ fishByID[$0] }).first(where: { $0.state == .swimming }) {
                target = snack.position.y
            } else if let meal, meal.state == .swimming {
                target = meal.position.y
            } else if tutorialBeat == .catchItBack, let rival,
                      GameRules.playerEncounter(player.targetRadius, rival.targetRadius) == .firstEatsSecond {
                target = rival.position.y
            } else {
                // Away from the nearest bigger fish ahead, toward whichever side of the water has more room.
                let threats = fish.filter { !$0.isPlayer && $0.state == .swimming && $0.radius > player.radius
                    && world.delta(from: player.position.x, to: $0.position.x) > -player.radius * 2 }
                let nearest = threats.min { abs(world.delta(from: player.position.x, to: $0.position.x))
                    < abs(world.delta(from: player.position.x, to: $1.position.x)) }
                target = nearest.map { $0.position.y > (waterBottom + waterTop) / 2 ? waterBottom + player.radius : waterTop - player.radius }
                    ?? player.position.y
            }
            seen.append((simClock, target))
            seen.removeAll { $0.at < simClock - lag - T.simulationStep }
            let wants = (seen.first?.target ?? target) > player.position.y + 3
            if wants != holding && simClock - decidedAt >= lag { holding = wants; decidedAt = simClock }
            simulationHolding = holding
            advanceFrame(T.simulationStep)
            onFrame?()
            if player.state != .swimming { debugCaughtStep = max(debugCaughtStep, abs(world.delta(from: lastX, to: player.position.x))) }
            lastX = player.position.x
            if beats.last?.beat != tutorialBeat {
                if tutorialBeat == .catchItBack { debugMissedFishGrewTo = rival?.targetRadius }
                beats.append((tutorialBeat, simClock))
            }
        }
        simulationHolding = nil
        return (phase == .won, beats, simClock)
    }

    /// The missed fish's size once its race beat was over, from the last `debugPlayTutorial`.
    private(set) var debugMissedFishGrewTo: CGFloat?
    /// The furthest you moved in one frame once caught, in the last `debugPlayTutorial`.
    private(set) var debugCaughtStep: CGFloat = 0
    /// The wall beat's fish still swimming, and how many fish are on scripted paths.
    var debugWallBeat: (meals: [Fish], wall: [Fish], scripted: Int) {
        (tutorialWallMeals.compactMap { fishByID[$0] }, tutorialWall.compactMap { fishByID[$0] }, tutorialPaths.count)
    }
    var debugTutorialBeat: ArcadeTutorial.Beat { tutorialBeat }
    /// The fish that got away, while it's around.
    var debugMissedFish: Fish? { tutorialMissedFish.flatMap { fishByID[$0] } }
    var debugPlayerRadius: CGFloat { player.targetRadius }
    /// How far up the water you are (0 the bottom, 1 the top), and holding on or off as a test's touch.
    var debugPlayerShare: CGFloat { waterShare(player.position.y) }
    func debugHold(_ on: Bool) { simulationHolding = on }
    /// Where a fish is: screens ahead of you (the way you're swimming, round the wrapped world), and share of the water.
    func debugTutorialPlace(_ f: Fish) -> (ahead: CGFloat, share: CGFloat) {
        var ahead = world.delta(from: player.position.x, to: f.position.x)
        if ahead < -size.width / zoom { ahead += world.width }
        return (ahead * zoom / size.width, waterShare(f.position.y))
    }
    /// Draws the scene as it stands, for frames rendered in tests.
    func debugRender() { _ = render() }
    /// A scripted fish whose path ends while it's eating, and a meal taken out of your mouth: whether the fish finished
    /// its meal before leaving, then left with nothing of it or its meal still swimming or swallowing, and you swam on.
    func debugLeavingMidSwallow() -> (stayedToEat: Bool, leftAfter: Bool, youSwimOn: Bool) {
        func spawn(_ radius: CGFloat, ahead: CGFloat) -> Fish {
            let f = Fish(id: nextFishID, isPlayer: false,
                         position: CGPoint(x: world.wrap(player.position.x + ahead * size.width / zoom), y: player.position.y), radius: radius)
            nextFishID += 1
            add(f, style: .player)
            return f
        }
        let eater = spawn(player.radius * 2, ahead: 0.5), meal = spawn(player.radius * 0.6, ahead: 0.5)
        // Its path ended long ago, so it would leave on its next move.
        tutorialPaths[eater.id] = (TutorialPath(points: [(0, 0.5, 0.5), (0.1, 0.5, 0.5)]), simClock - 10, true)
        beginSwallow(predator: eater, prey: meal)
        simulate(1.0 / 30)
        let stayed = fishByID[eater.id] != nil && fishByID[meal.id] != nil
        for _ in 0..<300 where fishByID[eater.id] != nil { simulate(1.0 / 30) }
        let left = fishByID[eater.id] == nil && fishByID[meal.id] == nil && nodes[eater.id] == nil && tutorialPaths.isEmpty
            && swallows.isEmpty
        let snack = spawn(player.radius * 0.5, ahead: 0)
        beginSwallow(predator: player, prey: snack)
        removeFish(snack)
        return (stayed, left, player.state == .swimming && swallows.isEmpty && fishByID[snack.id] == nil)
    }
    /// Before the scene is shown: the tutorial starts at `beat` (the size the beats before it make you), as a retry
    /// would, for playtesting one beat.
    func debugSetTutorialStart(_ beat: ArcadeTutorial.Beat) { tutorialCheckpoint = beat }
    /// Starts the tutorial at `beat` (the size the beats before it make you), playing at once.
    func debugStartTutorial(at beat: ArcadeTutorial.Beat) {
        tutorialCheckpoint = beat
        resetGame(startPlaying: true)
    }

    func debugAdvance(seconds: CGFloat) {
        for _ in 0..<Int((seconds / T.simulationStep).rounded(.up)) { advanceFrame(T.simulationStep) }
    }
    private(set) var debugBounceRiseInContactFrame: CGFloat = 0
    func debugFallOntoDome() -> Bool {
        guard let jelly = jellies.first, let layout = level.jellies else { return false }
        player.position = CGPoint(x: jelly.position.x,
                                  y: jelly.position.y + layout.radius * 0.65 + player.radius * T.hazardHitboxScale + 5)
        player.velocity.dy = -180
        simulate(1.0 / 30)
        let contactY = jellies[0].position.y + layout.radius * 0.65 + player.radius * T.hazardHitboxScale + 2
        // This fixture crosses near the center; use the actual curved surface after moving.
        let x = min(1, abs(world.delta(from: jellies[0].position.x, to: player.position.x)) /
                    (layout.radius + player.radius * T.hazardHitboxScale))
        debugBounceRiseInContactFrame = player.position.y - contactY + layout.radius * 0.65 * (1 - sqrt(max(0, 1 - x * x)))
        return phase == .playing && player.velocity.dy > T.motion.maxRiseSpeed && bounceRemaining > 0
    }
    func debugTouchTentacles(playerVictim: Bool) -> Bool {
        guard let jelly = jellies.first,
              let victim = playerVictim ? player : fish.first(where: { !$0.isPlayer && $0.isAlive }) else { return false }
        victim.position = CGPoint(x: jelly.position.x, y: jelly.position.y - 40)
        let previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
        updateJellies(0, previousFish: previous)
        return playerVictim ? phase == .lost : fishByID[victim.id] != nil && victim.isAlive
    }
    func debugPassOppositeJelly() -> Bool {
        guard let jelly = jellies.first else { return false }
        // Isolate the wrapped-distance regression from real contact with another jelly.
        jellies = [jelly]
        let old = CGPoint(x: world.wrap(jelly.position.x + world.width / 2 - 2), y: jelly.position.y - 40)
        player.position = CGPoint(x: world.wrap(old.x + 4), y: old.y)
        updateJellies(0, previousFish: [player.id: old])
        return phase == .playing
    }
    var debugLevelIndex: Int { levelIndex }
    /// Every haptic played, in order (only those Vibration let through).
    private(set) var debugHaptics: [Haptic] = []
    /// The world's pips on the card showing (the ready card or a win's), by their caption ("" for pips alone).
    var debugProgressCaption: String? {
        let strip = messageNode.children.lazy.compactMap { $0 as? WorldProgressStrip }.first
            ?? resultPanel?.children.lazy.compactMap { $0 as? WorldProgressStrip }.first
        return strip.map { $0.caption.isHidden ? "" : $0.caption.text ?? "" }
    }
    /// The words on the card before a level, top to bottom.
    var debugCardTexts: [String] { messageNode.children.compactMap { ($0 as? SKLabelNode)?.text } }
    var debugResultTitles: [String] { resultPanel?.controls.map { $0.action.title } ?? [] }
    func debugTapResult(_ action: ArcadeResultAction?) {
        guard let panel = resultPanel else { return }
        let frame = panel.controls.first { $0.action == action }?.frame
        panel.handleTap(at: frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 0, y: 80))
    }
    func debugApproachJelly() -> Bool {
        guard let jelly = jellies.first else { return false }
        for f in fish.filter({ !$0.isPlayer }) { removeByTentacles(f) }
        jellies = [jelly]
        player.position = CGPoint(x: world.wrap(jelly.position.x + 130), y: jelly.position.y - 40)
        let swimmer = Fish(id: nextFishID, isPlayer: false,
                           position: CGPoint(x: world.wrap(jelly.position.x - 100), y: jelly.position.y - 40),
                           radius: 28)
        nextFishID += 1
        swimmer.heading = 1
        swimmer.cruiseSpeed = 100
        swimmer.velocity = CGVector(dx: 100, dy: 0)
        swimmer.targetY = swimmer.position.y
        swimmer.turnTimer = 10
        swimmer.retargetTimer = 10
        add(swimmer, style: .player)
        for _ in 0..<90 {
            guard swimmer.isAlive else { break }
            let previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
            moveAI(swimmer, 1.0 / 30)
            updateJellies(0, previousFish: previous)
        }
        return swimmer.isAlive
    }
    func debugPassivePredatorVelocity(playerOffset: CGFloat) -> CGVector {
        let predator = fish.first { !$0.isPlayer && $0.radius > player.radius }!
        predator.position = CGPoint(x: 0, y: waterCenter)
        predator.velocity = CGVector(dx: 50, dy: 0)
        predator.heading = 1
        predator.targetY = waterCenter
        predator.turnTimer = 10
        predator.retargetTimer = 10
        player.position = CGPoint(x: world.wrap(playerOffset), y: waterCenter + 30)
        moveAI(predator, 0.1)
        return predator.velocity
    }
    /// A fish a little smaller than you eats one about half your size and is bigger than you after it.
    func debugAICompetition() -> (respectedGrace: Bool, becameThreat: Bool) {
        for f in fish.filter({ !$0.isPlayer }) { removeByTentacles(f) }
        let position = CGPoint(x: world.width / 2, y: waterCenter)
        let predator = Fish(id: nextFishID, isPlayer: false, position: position, radius: T.baseRadius * 0.95)
        nextFishID += 1
        let prey = Fish(id: nextFishID, isPlayer: false, position: position, radius: T.baseRadius * 0.6)
        nextFishID += 1
        add(predator, style: .player)
        add(prey, style: .player)
        simClock = T.aiEatingGracePeriod - 0.01
        resolveCollisions()
        let respectedGrace = predator.state == .swimming && prey.state == .swimming
        simClock = T.aiEatingGracePeriod + 0.01
        resolveCollisions()
        advanceSwallows(1)
        advanceGrowth(T.growDuration)
        return (respectedGrace, fishByID[prey.id] == nil &&
                GameRules.playerEncounter(player.radius, predator.radius) == .secondEatsFirst && mealsEaten == 0)
    }
    /// A fish you've met (planned fish you haven't pass bells by off screen) diving onto a bell lands on it.
    func debugAIMovementAllowsBellLanding() -> Bool {
        guard let jelly = jellies.first, let layout = level.jellies,
              let swimmer = fish.first(where: { !$0.isPlayer && $0.isAlive }) else { return false }
        jellies = [jelly]
        fish = [player, swimmer]
        encounterLeases[swimmer.id] = nil
        player.position.x = world.wrap(jelly.position.x + world.width / 2)
        swimmer.position = CGPoint(x: jelly.position.x,
            y: jelly.position.y + layout.radius * 0.65 + swimmer.radius * T.hazardHitboxScale + 12)
        swimmer.cruiseSpeed = 0
        swimmer.velocity = CGVector(dx: 0, dy: -140)
        swimmer.targetY = jelly.position.y - 40
        swimmer.retargetTimer = 100
        for _ in 0..<30 {
            simulate(T.simulationStep)
            if swimmer.velocity.dy > T.motion.maxRiseSpeed { return swimmer.isAlive }
        }
        return false
    }

    /// A fish you've met falling onto a bell bounces off it.
    func debugAIFallOntoDome() -> Bool {
        guard let jelly = jellies.first, let layout = level.jellies,
              let swimmer = fish.first(where: { !$0.isPlayer && $0.isAlive }) else { return false }
        encounterLeases[swimmer.id] = nil
        swimmer.position = CGPoint(x: jelly.position.x,
            y: jelly.position.y + layout.radius * 0.65 + swimmer.radius * T.hazardHitboxScale - 1)
        swimmer.velocity.dy = -180
        var previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
        previous[swimmer.id]!.y += 30
        updateJellies(T.simulationStep, previousFish: previous)
        return swimmer.isAlive && swimmer.velocity.dy > T.motion.maxRiseSpeed
    }

    /// Two planned fish you haven't met touch on screen: they part, the one swimming into the other turning away.
    /// Once you've passed them both, the bigger eats the smaller.
    func debugProtectedFishYieldCheck() -> Bool {
        guard let smaller = fish.first(where: { !$0.isPlayer }),
              let larger = fish.first(where: { !$0.isPlayer && $0.radius > smaller.radius / (1 - T.nearEqualThreshold) })
        else { return false }
        fish = [player, smaller, larger]
        let x = world.wrap(player.position.x + size.width * 0.3)
        smaller.position = CGPoint(x: x, y: waterTop - larger.radius)
        larger.position = CGPoint(x: world.wrap(x + 1), y: smaller.position.y)
        // An approaching swimmer yields when the other is already moving away.
        smaller.heading = 1
        smaller.velocity.dx = smaller.cruiseSpeed
        larger.heading = 1
        larger.velocity.dx = larger.cruiseSpeed
        encounterLeases[smaller.id] = EncounterLease(home: smaller.position, releaseDistance: 100)
        encounterLeases[larger.id] = EncounterLease(home: larger.position, releaseDistance: 100)
        forwardDistance = 99
        simClock = T.aiEatingGracePeriod + 1
        let radius = smaller.radius
        resolveCollisions()
        let dx = world.delta(from: larger.position.x, to: smaller.position.x)
        let reach = (smaller.radius + larger.radius) * T.collisionScale
        guard smaller.state == .swimming && larger.state == .swimming && smaller.radius == radius,
              abs(dx) >= reach, smaller.heading * dx > 0, smaller.velocity.dx * dx > 0 else { return false }
        // Once both have had their first chance, unequal-size contact resumes normal eating.
        forwardDistance = 100
        larger.position = smaller.position
        resolveCollisions()
        return smaller.state != .swimming
    }

    /// Exercise release boundaries and collisions directly, without relying on a controller.
    func debugEncounterProtectionLifecycle() -> Bool {
        guard let id = encounterLeases.keys.sorted().first, let lease = encounterLeases[id], let prey = fishByID[id],
              let predator = fish.first(where: { !$0.isPlayer && $0.radius > prey.radius / (1 - T.nearEqualThreshold) })
        else { return false }
        simClock = T.aiEatingGracePeriod + 1
        let originalRadius = prey.radius
        predator.position = prey.position
        forwardDistance = lease.releaseDistance - 0.001
        resolveCollisions()
        guard prey.state == .swimming, prey.radius == originalRadius, encounterProtected(id) else { return false }
        // Both sides must have been released. An already-released fish cannot raid a protected area.
        forwardDistance = (encounterLeases.values.map(\.releaseDistance).max() ?? lease.releaseDistance) + 0.001
        predator.position = prey.position
        resolveCollisions()
        return !encounterProtected(id) && prey.state != .swimming
    }

    var debugFishCount: Int { fish.count }
    /// The pause menu's switches: sound effects, music, and vibration.
    var debugSoundSwitches: [Bool] { [effectsButton.isOn, musicButton.isOn, vibrationButton.isOn] }
    /// How many backdrops the pause menu has drawn (one, however often it's paused).
    var debugPauseBackdrops: Int { pauseMenu.children.filter { $0.name == "pauseBackdrop" }.count }
    var debugPauseMenu: SKNode { pauseMenu }
    var debugPhase: Phase { phase }
    /// The card on screen (before a level, after it, or the tutorial's last line); faded out while you play.
    var debugMessage: SKNode { messageNode }
    var debugMealsEaten: Int { mealsEaten }
    var debugEdibleCount: Int {
        fish.filter { !$0.isPlayer && $0.isAlive && GameRules.playerEncounter(player.radius, $0.radius) == .firstEatsSecond }.count
    }
    func debugHazardWipeout() {
        for f in fish.filter({ !$0.isPlayer }) { removeByTentacles(f) }
        simulate(1.0 / 30)
    }
    func debugResolvePlayerTie(otherRatio: CGFloat, playerSecond: Bool) -> Bool {
        resetGame(startPlaying: true)
        for f in fish where !f.isPlayer { f.state = .removed }
        let other = Fish(id: nextFishID, isPlayer: false, position: player.position,
                         radius: player.radius * otherRatio)
        nextFishID += 1
        add(other, style: .player)
        if playerSecond { fish.reverse() }
        resolveCollisions()
        return player.state == .swallowing(preyID: other.id) && other.state == .beingSwallowed(predatorID: player.id)
    }

    func debugCommitFatalSwallowForMetrics() {
        let predator = Fish(id: nextFishID, isPlayer: false, position: player.position, radius: player.radius * 2)
        nextFishID += 1
        add(predator, style: .player)
        beginSwallow(predator: predator, prey: player)
    }

    func debugEatMeal() {
        let prey = Fish(id: nextFishID, isPlayer: false, position: player.position, radius: player.radius * 0.5)
        nextFishID += 1
        add(prey, style: .player)
        beginSwallow(predator: player, prey: prey)
        advanceSwallows(1)
    }
    func debugCompletionMotionCheck(replay: Bool) -> Bool {
        debugStart()
        debugClearLevel()
        let position = player.position
        let distance = forwardDistance
        let clock = realClock
        for _ in 0..<60 { advanceFrame(T.simulationStep) }
        guard phase == .won, player.position == position, forwardDistance == distance,
              player.velocity == .zero, realClock > clock, winGlow?.hasActions() == true else { return false }
        debugTapResult(replay ? .playAgain : .nextLevel)
        debugStart()
        advanceFrame(T.simulationStep)
        return phase == .playing && forwardDistance > 0 && winGlow == nil
    }

    func debugClearLevel() {
        for f in fish where !f.isPlayer { f.state = .removed }
        waitingFish.removeAll()
        simulate(1.0 / 30)
    }

    /// Play a planned test level instead of this campaign slot. Call before the scene is shown.
    func debugUsePlanner(_ spec: MeetingSpec, variation: Int = 0) {
        plannerLevel = MeetingPlanner.plan(spec, variation: variation).level
    }
    /// Play this exact plan (no replanning). Call before the scene is shown.
    func debugUsePlan(_ plan: MeetingPlan) { plannerLevel = plan.level }
    var debugMeetingPlan: MeetingPlan? { level.meetingPlan }

    /// A fish you've passed, touching a planned fish you haven't met, turns away; the planned fish keeps its line.
    func debugPlannedFishHoldTheirLine() -> Bool {
        resetGame(startPlaying: true)
        guard let plan = level.meetingPlan, plan.fish.count > 1,
              let unmet = fishByID[plan.fish[plan.fish.count - 1].id], let passed = fishByID[plan.fish[0].id] else { return false }
        forwardDistance = plan.fish[0].meetingDistance + size.width
        simClock = T.aiEatingGracePeriod + 1
        guard encounterProtected(unmet.id), !encounterProtected(passed.id) else { return false }
        passed.position = CGPoint(x: world.wrap(unmet.position.x - 1), y: unmet.position.y)
        let position = unmet.position, heading = unmet.heading
        resolveCollisions()
        let gap = abs(world.delta(from: unmet.position.x, to: passed.position.x))
        return unmet.position == position && unmet.heading == heading && passed.state == .swimming
            && gap >= (unmet.radius + passed.radius) * T.collisionScale && passed.heading == -1
    }

    /// Every fish crossing an untouchable player's path, in order. `radii` replays the player's size
    /// per simulation step (a reference route), so zoom and forward distance match a real run, and
    /// the `eaten` fish disappear as they cross, as that route's meals would.
    func debugEncounterCrossings(radii: [CGFloat]? = nil, eaten: Set<Int> = [], laps: CGFloat = 1) -> [EncounterCrossing] {
        simulationHeadless = true
        simulationEcologyProbe = true
        simulationHolding = false
        resetGame(startPlaying: true)
        var previous = Dictionary(uniqueKeysWithValues: fish.filter { !$0.isPlayer }.map {
            ($0.id, (dx: world.delta(from: player.position.x, to: $0.position.x), y: $0.position.y)) })
        var crossings: [EncounterCrossing] = []
        var crossed: Set<Int> = []
        var step = 0
        while phase == .playing && forwardDistance < world.width * laps {
            if let radii {
                player.radius = radii[min(step, radii.count - 1)]
                player.targetRadius = player.radius
            }
            let before = (time: simClock, distance: forwardDistance)
            advanceFrame(T.simulationStep)
            step += 1
            for f in fish where !f.isPlayer && f.state == .swimming {
                let dx = world.delta(from: player.position.x, to: f.position.x)
                defer { previous[f.id] = (dx, f.position.y) }
                // From ahead to level with (or behind) the player, away from the far side of the wrap.
                guard let last = previous[f.id], last.dx > 0, dx <= 0, last.dx < world.width / 4,
                      crossed.insert(f.id).inserted else { continue }
                let fraction = last.dx / (last.dx - dx)
                crossings.append(EncounterCrossing(fishID: f.id,
                    time: Double(before.time + (simClock - before.time) * fraction),
                    distance: Double(before.distance + (forwardDistance - before.distance) * fraction),
                    y: Double(last.y + (f.position.y - last.y) * fraction), radius: Double(f.radius),
                    headOn: f.velocity.dx < 0, zoom: Double(zoom)))
            }
            for id in eaten where crossed.contains(id) { if let gone = fishByID[id] { removeFish(gone) } }
        }
        return crossings
    }
    #endif

}

#if DEBUG
// MARK: - App Store captures (StoreCapture.swift)

extension GameScene {
    /// The scene as a capture sees it: every fish and jellyfish where it's drawn, in screen points.
    var debugCaptureView: StoreCapture.SceneView {
        func screen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: size.width * T.playerScreenX + world.delta(from: player.position.x, to: point.x) * zoom,
                    y: waterCenter + (point.y - waterCenter) * zoom)
        }
        func swimmer(_ f: Fish) -> StoreCapture.Swimmer {
            var prey: Int?
            if case .swallowing(let id) = f.state { prey = id }
            var eaten = false
            if case .beingSwallowed = f.state { eaten = true }
            return StoreCapture.Swimmer(id: f.id, center: screen(f.position), radius: f.radius * zoom, prey: prey,
                                        isEaten: eaten, shrink: f.shrink,
                                        shade: kelpBeds.isEmpty || f.isPlayer ? 0 : kelpShade(f.position, radius: f.radius))
        }
        return StoreCapture.SceneView(size: size, time: simClock, playing: phase == .playing, won: phase == .won,
                                      player: swimmer(player), rising: player.velocity.dy * zoom,
                                      fish: fish.filter { !$0.isPlayer && $0.state != .removed }.map(swimmer),
                                      jellies: jellies.map { screen($0.position) }, jellyRadius: (level.jellies?.radius ?? 0) * zoom,
                                      lastBounce: debugBounces.last { $0.fishID == player.id }?.time)
    }

    /// The diagnostics bot's call on the scene as it stands, seeing what it sees in `debugSimulate`.
    func debugBotHolds(_ policy: ArcadeSimulation.Policy) -> Bool {
        let visible = fish.filter { !$0.isPlayer && $0.state == .swimming &&
            abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width * 0.80 / zoom }
        func swimmer(_ f: Fish) -> ArcadeSimulation.Swimmer {
            .init(x: f.position.x, y: f.position.y, vx: f.velocity.dx, vy: f.velocity.dy, radius: f.radius)
        }
        let bells = level.jellies.map { layout in
            jellies.filter { abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width / zoom }
                .map { ArcadeSimulation.Bell(x: $0.position.x, y: $0.position.y, radius: layout.radius, tentacles: layout.tentacleLength) }
        } ?? []
        return ArcadeSimulation.holding(.init(player: swimmer(player), fish: visible.map(swimmer), bells: bells,
            width: world.width, screenWidth: size.width, zoom: zoom, bottom: waterBottom, top: waterTop, speed: playerSpeed,
            bouncing: bounceRemaining > 0, bounceSpeed: T.jellyBounceSpeed, hooks: botHooks), policy: policy)
    }

    /// The hooks within a screen of you, as the bots see them: the circle the bait and its bend catch you in, moving
    /// as they are now.
    var botHooks: [ArcadeSimulation.Swimmer] {
        hookRigs.compactMap { rig in
            let now = HookMotion.position(rig.hook, time: simClock), soon = HookMotion.position(rig.hook, time: simClock + 0.05)
            guard abs(world.delta(from: player.position.x, to: world.wrap(now.x))) < size.width / zoom else { return nil }
            let bait = rig.hook.baitRadius
            return .init(x: world.wrap(now.x), y: now.y - 0.1 * bait, vx: (soon.x - now.x) / 0.05, vy: (soon.y - now.y) / 0.05,
                         radius: 1.15 * bait)
        }
    }

    /// Plays a Sunset Cove level (or any planned level) along its reference route: it makes for each reference meal's
    /// planned meeting height in turn, steering round hooks and bigger fish on the way, then, once the route's meals are
    /// behind it, cleans up like the collector bot. Ends when it's won, lost, or `limit` seconds have passed.
    /// `safeFromFish`: nothing can eat it (it passes through a bigger fish), so the run tests the hooks, not the bot.
    func debugPlayReferenceRoute(limit: CGFloat = 90, safeFromFish: Bool = false,
                                 onFrame: (() -> Void)? = nil) -> ArcadeSimulation.Result {
        simulationHeadless = true
        simulationEcologyProbe = false
        simulationHolding = false
        simulationSafeFromFish = safeFromFish
        defer { simulationSafeFromFish = false }
        resetGame(startPlaying: true)
        guard let plan = level.meetingPlan else { return .init(outcome: "none", reason: "", seconds: 0, playerMeals: 0) }
        let reference = Set(plan.fish.filter(\.referenceMeal).map(\.id))
        let route = plan.predicted.filter { reference.contains($0.fishID) }.sorted { $0.time < $1.time }
        // A straight swim from each meeting to the next, from where you start, as the planner lays the big fish clear of.
        let stops = [(time: CGFloat(0), y: player.position.y)] + route.map { (time: CGFloat($0.time), y: CGFloat($0.y)) }
        func wanted(at time: CGFloat) -> (y: CGFloat, weight: CGFloat) {
            guard let after = stops.firstIndex(where: { $0.time > time }) else { return (stops.last!.y, 1) }
            let a = stops[max(0, after - 1)], b = stops[after]
            let y = a.y + (b.y - a.y) * ((time - a.time) / max(0.01, b.time - a.time)).clamped(0, 1)
            // Being there at a meeting matters most.
            return (y, min(time - a.time, b.time - time) < 0.06 ? 25 : 1)
        }
        var next = 0, nextDecision: CGFloat = 0
        while phase == .playing && simClock < limit {
            // Past a meal's meeting, or it's being eaten or gone: on to the next.
            while next < route.count, CGFloat(route[next].time) < simClock - 0.2
                    || (fishByID[route[next].fishID].map { $0.state != .swimming }
                        ?? !waitingFish.contains { $0.id == route[next].fishID }) {
                next += 1
            }
            if simClock >= nextDecision {
                var observation = botObservation
                if next < route.count {
                    // On the route: its own meals are the way (a gate is edible by the time you reach it), bigger fish are
                    // dodged only where they'd touch (so it threads a walled gate), and other meals are swum round, so
                    // it grows exactly as the route was timed.
                    let visible = fish.filter { !$0.isPlayer && $0.state == .swimming && !reference.contains($0.id)
                        && abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width * 0.8 / zoom }
                    func swimmer(_ f: Fish) -> ArcadeSimulation.Swimmer {
                        .init(x: f.position.x, y: f.position.y, vx: f.velocity.dx, vy: f.velocity.dy, radius: f.radius)
                    }
                    let yours = player.targetRadius
                    let edible = { (f: Fish) in GameRules.playerEncounter(yours, f.radius) == .firstEatsSecond }
                    // Safe from fish, it just bumps through them.
                    observation.fish = safeFromFish ? [] : visible.filter { !edible($0) }.map(swimmer)
                    observation.avoids = visible.filter(edible).map(swimmer)
                    observation.threatMargin = 10
                    observation.seeksFood = false
                } else {
                    // Cleaning up: after the nearest meal (only meals, safe from fish), giving hooks a wide berth.
                    if safeFromFish {
                        let yours = player.radius
                        observation.fish = observation.fish.filter { GameRules.playerEncounter(yours, $0.radius) == .firstEatsSecond }
                    }
                    observation.hookMargin = 40
                }
                let now = simClock
                simulationHolding = ArcadeSimulation.holding(observation, policy: .collector,
                                                             path: next < route.count ? { wanted(at: now + $0) } : nil)
                nextDecision = simClock + 0.05
            }
            advanceFrame(T.simulationStep)
            onFrame?()
        }
        return .init(outcome: phase == .won ? "won" : (phase == .lost ? "lost" : "timeout"),
                     reason: phase == .lost ? lossReason : "", seconds: Double(simClock), playerMeals: mealsEaten)
    }

    /// What the bots see now.
    private var botObservation: ArcadeSimulation.Observation {
        let visible = fish.filter { !$0.isPlayer && $0.state == .swimming &&
            abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width * 0.80 / zoom }
        func swimmer(_ f: Fish) -> ArcadeSimulation.Swimmer {
            .init(x: f.position.x, y: f.position.y, vx: f.velocity.dx, vy: f.velocity.dy, radius: f.radius)
        }
        return .init(player: swimmer(player), fish: visible.map(swimmer), bells: [], width: world.width,
                     screenWidth: size.width, zoom: zoom, bottom: waterBottom, top: waterTop, speed: playerSpeed,
                     bouncing: bounceRemaining > 0, bounceSpeed: T.jellyBounceSpeed, hooks: botHooks)
    }

    /// The other fish still swimming, and their sizes.
    var debugRemaining: [(id: Int, radius: CGFloat)] {
        fish.filter { !$0.isPlayer && $0.state != .removed }.map { ($0.id, $0.radius) }
    }
    /// Your meals this run: each fish's id, and when you bit it.
    var debugMealLog: [(id: Int, time: CGFloat)] { mealLog }

    /// The level's hooks, as planned.
    var debugHooks: [PlannedHook] { hookRigs.map(\.hook) }
    /// Why the last run was lost.
    var debugLossReason: String { lossReason }
    /// Whether you're being reeled up a hook's line.
    var debugReeling: Bool { reel != nil }
    /// Where hook `index` is now (wrapped world point).
    func debugHookPosition(_ index: Int) -> CGPoint { hookPosition(hookRigs[index].hook, time: simClock) }
    /// How wide each hook line on show was drawn across the screen (points).
    var debugHookLineWidths: [CGFloat] {
        hookRigs.filter { !$0.line.isHidden }.compactMap { $0.line.path?.boundingBoxOfPath.width }
    }

    /// Puts your fish on hook `index` (its bait's center, its bend under the bait, or its line well above the hook), as
    /// big as it is now, and checks the hooks. Returns whether you were caught.
    func debugTouchHook(_ index: Int, at part: HookPart) -> Bool {
        let hook = hookRigs[index].hook, at = hookPosition(hook, time: simClock), bait = hook.baitRadius
        player.position = switch part {
        case .bait: at
        case .bend: CGPoint(x: world.wrap(at.x + HookRules.bend.x * bait), y: at.y + HookRules.bend.y * bait)
        case .line: CGPoint(x: at.x, y: at.y + HookMetal.eye * bait + player.radius + 30)
        }
        updateHooks()
        return phase == .lost && reel != nil
    }
    enum HookPart { case bait, bend, line }

    /// Holds a fish you haven't eaten on hook `index`'s bait for `seconds` of play (you far off and untouchable), and
    /// returns whether it's still swimming and the hook still baited.
    func debugFishPassesHook(_ index: Int, seconds: CGFloat = 1) -> Bool {
        guard let other = fish.first(where: { !$0.isPlayer && $0.isAlive }) else { return false }
        let hook = hookRigs[index].hook
        player.position.x = world.wrap(hookPosition(hook, time: simClock).x + world.width / 2)
        simulationEcologyProbe = true
        defer { simulationEcologyProbe = false }
        let steps = Int((seconds / T.simulationStep).rounded())
        for _ in 0..<steps {
            other.position = hookPosition(hook, time: simClock)
            simulate(T.simulationStep)
            guard other.isAlive, fishByID[other.id] != nil else { return false }
        }
        return other.isAlive && fishByID[other.id] != nil && phase == .playing && reel == nil
    }

    /// The level from the start, playing at once, as a first touch starts it.
    func debugCaptureRestart() {
        resetGame(startPlaying: false)
        startRun()
    }

    /// No pause button, level name, or card over the frame.
    func debugHideInterface() { uiLayer.isHidden = true }
}
#endif
