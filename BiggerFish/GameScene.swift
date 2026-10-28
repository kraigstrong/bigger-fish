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
    /// When it went off the left of the screen behind you, boat and all: from then it's reeled up (`hookPosition`).
    var passedAt: CGFloat? = nil
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
        !isTutorial && !isOpenWater && GameRules.isWin(fish) && waitingFish.isEmpty
    }
    /// The Open Water's endless run (`OpenWater`), when that's what's playing: stage after stage, each a planned level
    /// of its own, until you're eaten. No campaign progress: its pearls and best runs are the app's (`onPearl`,
    /// `onOpenWaterRun`), and its runs are reported their own way (`openWaterMetrics`).
    private var openWater: OpenWaterRun?
    #if DEBUG
    /// The run as it started, for an App Store capture to play again from its first level (`debugCaptureRestart`).
    private var debugOpenWaterStart: OpenWaterRun?
    #endif
    /// The next run, its first levels planned while this run's result shows so Retry starts at once.
    private var nextOpenWaterRun: OpenWaterRun?
    /// Levels being planned off the main thread (`planOpenWaterLevelAhead`), each by its run's seed and its index.
    private var openWaterPlanning: Set<OpenWaterPlanKey> = []
    private struct OpenWaterPlanKey: Hashable {
        let seed: UInt64
        let index: Int
    }
    /// Retry was tapped (on the result card, or Restart on the pause menu) before the next run's first level was
    /// planned: it goes ahead once it is, if the game's still on that card or menu.
    private var openWaterRetryWaits: Phase?
    #if DEBUG
    /// The game's way of planning, for a test of a headless study (`plansOpenWaterAhead`).
    var debugPlansOpenWaterAhead = false
    /// Each level planned as it's reached, as a headless study plans: for footage drawn a frame at a time
    /// (`StoreFootage`), which a plan made off the main thread couldn't reach until it's done.
    var debugPlansOpenWaterInline = false
    #endif
    /// The level's last gate, which ends it once you eat it; other fish can't eat it, nor it them.
    private var openWaterFinale: Int?
    /// "Stage 2" as a new time round starts, and the fish and pearl counts at the top of the screen.
    private var openWaterBanner: SKLabelNode?
    /// The change into a new level (`beginOpenWaterLevel`), drawn over its first moments: when it began (real seconds),
    /// how much closer the camera starts than it ends (so your fish starts the size on screen it was), and a picture of
    /// the world you left.
    private var openWaterWash: (start: CGFloat, closer: CGFloat, leaving: SKSpriteNode?)?
    /// The level's pearls still in the water, each with its node, and those being gulped: each one's node, where it was
    /// on screen when you touched it, and when (real seconds).
    private var openWaterPearls: [(pearl: OpenWaterPearl, node: SKNode)] = []
    private var openWaterGulps: [(node: SKNode, from: CGPoint, start: CGFloat)] = []
    private let openWaterCounts = SKNode()
    /// A pearl was taken (the run's count is the scene's; the player's saved pearls are the app's), and the run's
    /// result card's Shop was tapped.
    var onPearl: (() -> Void)?
    var onShop: (() -> Void)?
    /// The player's pearls to spend (the app's), shown on a run's result card's Shop button, and kept up to date there
    /// as they're spent in the shop over it.
    var pearlsToSpend = 0 {
        didSet {
            guard pearlsToSpend != oldValue, let resultPanel else { return }
            resultPanel.showShopPearls(pearlsToSpend)
            configureResultAccessibility(resultPanel)
        }
    }
    /// The player's best run, in fish eaten (the app's), and each run's end with its fish and the furthest level it reached
    /// (from 0), for the app to keep a new best: it answers with the looks the run earned (`PearlItem.earnedBy`).
    var openWaterBest = 0
    var onOpenWaterRun: ((_ fish: Int, _ furthest: Int) -> [PearlItem])?
    /// The day's free runs still to take a pearl (the app's, `OpenWaterRuns`), or nil with the unlock: none left, a run's
    /// card offers the unlock instead of Retry. And a run's first pearl, which counts it as one of them.
    var openWaterRunsLeft: (() -> Int?)?
    var onOpenWaterRunCounted: (() -> Void)?
    /// The run just ended beat the best, and the looks it earned: its card says so.
    private var openWaterNewBest = false
    private var openWaterEarned: [PearlItem] = []
    /// The run's numbers for the stats (`ArcadeAnalytics.startOpenWater`), while a run from the first level is reported.
    private var openWaterMetrics: OpenWaterMetricAccumulator?
    /// How long runs' levels took to plan, the slowest by run seed (a run's first level is planned before the scene, so
    /// its time comes with the run: `startOpenWater`).
    private var openWaterSlowestPlan: [UInt64: Double] = [:]
    private var isOpenWater: Bool { openWater != nil }
    /// The Open Water's result card: what the run earned or "New best!" over it, and the best under how far it got.
    private var openWaterResultHeading: String? {
        guard openWater != nil else { return nil }
        if let earned = openWaterEarned.first {
            return openWaterEarned.count == 1 ? "You earned the \(earned.name)!" : "You earned \(openWaterEarned.count) new looks!"
        }
        return openWaterNewBest ? "New best!" : nil
    }
    private var openWaterResultNote: String? {
        guard openWater != nil else { return nil }
        let best = openWaterBest > 0 ? "Best: \(openWaterBest) fish" : nil
        let runs = openWaterRunsLeft?().map { left in
            left == 0 ? "\(T.freeOpenWaterRunsPerDay) more runs tomorrow" : left == 1 ? "1 run left today" : "\(left) runs left today"
        }
        let note = [best, runs].compactMap { $0 }.joined(separator: " · ")
        return note.isEmpty ? nil : note
    }
    /// The day's free Open Water runs are used up: no new run until tomorrow, or the unlock.
    private var outOfOpenWaterRuns: Bool { openWater != nil && openWaterRunsLeft?() == 0 }
    private var openWaterShopPearls: Int? {
        openWater != nil ? pearlsToSpend : nil
    }
    /// The Open Water's result line: how far the run got.
    private var openWaterSummary: String? {
        guard let openWater else { return nil }
        return "Stage \(openWater.leg.stage) · \(openWater.leg.world.title) · \(mealsEaten) fish · "
            + (openWater.pearls == 1 ? "1 pearl" : "\(openWater.pearls) pearls")
    }
    /// A tutorial (`ArcadeTutorial`) instead of a level: its beats bring their own fish, nothing is recorded as cleared,
    /// and it ends by leaving for its way to play.
    let tutorialCourse: ArcadeTutorial.Course?
    var isTutorial: Bool { tutorialCourse != nil }
    /// The beat the tutorial opens with: its first meal, for a player who already knows how to rise and fall.
    private let tutorialOpening: ArcadeTutorial.Beat
    /// The tutorial was left from its pause menu (Home), not finished or skipped: it goes home, not on into its way to
    /// play.
    private(set) var leftTutorialForHome = false
    /// The world being played. The Open Water moves from world to world as it goes.
    private(set) var arcadeWorld: ArcadeWorld
    private var levelIndex: Int {
        didSet { worldLevel = arcadeWorld.level(levelIndex) }
    }
    /// The level being played (it advances with Next level), for the map to return to.
    var currentLevelIndex: Int { levelIndex }
    /// This slot's level, looked up once: `level` is read for every fish on every step.
    private var worldLevel: Level
    private var level: Level {
        if isTutorial { return T.tutorialLevel }
        if let plannerLevel { return plannerLevel }
        return worldLevel
    }
    /// Beating a world's tenth level finishes its main run: the result leads back to the map, where the next
    /// world and the Deep End open, rather than straight on to the Deep End.
    private var isWorldFinale: Bool {
        if plannerLevel != nil { return false }
        return levelIndex == ArcadeWorld.mainLevelCount - 1
    }
    private var isFinalLevel: Bool {
        if plannerLevel != nil { return true }
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
        finishOpenWaterMetrics("quit")
        // Sent with the next batch, or when the app goes to the background.
        enqueueMetricOperation { $0.leave() }
    }

    var onClear: ((Int, Double) -> Void)?
    /// You died on the level at this index (not in the tutorial).
    var onDeath: ((Int) -> Void)?
    var onExit: (() -> Void)?
    /// What your fish wears (`PlayerLook`), from the next time it's drawn: a change on the result card shows from Retry.
    var playerLook = PlayerLook.plain
    /// Pausing and resuming, so the screen around the playfield (on an iPad) can darken with the pause menu.
    var onPause: ((Bool) -> Void)?
    /// The world changed mid-run (the Open Water), so the screen around the playfield can take its water.
    var onWorldChange: ((ArcadeWorld) -> Void)?
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
    /// A planned level played outside the campaign: the Open Water's, or (in Xcode builds) a test level.
    private var plannerLevel: Level?
    /// The pause menu's way out: Level map from a level, Home from the Open Water or the tutorial (`leavesForHome`).
    private var mapButton = MenuButtonRow(title: "Level map", symbol: "map.fill", style: .secondary, theme: .arcade)
    private var resultPanel: ArcadeResultPanel?
    #if DEBUG
    /// A test's or a bot's touch: holding or not, in place of real touches.
    private var simulationHolding: Bool?
    /// Played without a screen (tests, the planner's studies): no sound or analytics.
    private var simulationHeadless = false
    /// Your fish swims on untouchable: nothing eats it, it eats nothing, and jellies pass through it, so a run
    /// measures the fish alone (`debugEncounterCrossings`).
    private var simulationEcologyProbe = false
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

    /// `knowsControls`: the tutorial skips rising and falling (learned in the other tutorial, a level, or a run).
    init(world: ArcadeWorld = .shallowReef, levelIndex: Int = 0,
         showsJellyLesson: Bool = true, tutorial: ArcadeTutorial.Course? = nil, knowsControls: Bool = false) {
        arcadeWorld = world
        tutorialCourse = tutorial
        tutorialOpening = tutorial?.opening(knowsControls: knowsControls) ?? .holdToRise
        tutorialCheckpoint = tutorialOpening
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
    /// An Adventure level's fish still to eat, top middle, once `fishLeftShownFrom` or fewer are left.
    private let fishLeftLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var resumeButton = MenuButtonRow(title: "Resume", symbol: "play.fill", style: .primary, theme: .arcade)
    private var restartButton = MenuButtonRow(title: "Restart level", symbol: "arrow.counterclockwise", style: .secondary, theme: .arcade)
    private var effectsButton = MenuSwitchRow(title: "Sound effects", symbol: "speaker.wave.2.fill", isOn: true, theme: .arcade)
    private var musicButton = MenuSwitchRow(title: "Music", symbol: "music.note", isOn: true, theme: .arcade)
    private var vibrationButton = MenuSwitchRow(title: "Vibration", symbol: "iphone.radiowaves.left.and.right", isOn: true, theme: .arcade)

    private var holdTouches = Set<UITouch>()
    private var lastUpdate: TimeInterval?
    private var frameAccumulator = T.frameRemainderStart
    private var simulationAccumulator: CGFloat = 0
    /// How far behind the moment a frame stands for it draws, in game seconds: a step (a blend of the last two steps)
    /// until every frame simulates a step of its own, then the newest step (`GameTuning.newestStepAfterFrames`). It
    /// eases between them, and never drops below how far the frame is past the newest step, so a frame never guesses.
    private var presentationLag = T.simulationStep
    /// Display frames in a row that each took at least one step at full speed.
    private var steppedFrames = 0
    /// The game moment the last frame drew, while the game runs, so the next never draws an earlier one.
    private var lastDrawnMoment: CGFloat?
    private var previousPresentation: [Int: FishPresentation] = [:]
    private var previousJellyPositions: [CGPoint] = []
    private var previousZoom: CGFloat = 1
    private var realClock: CGFloat = 0
    /// Simulated seconds since the current run started playing.
    private var simClock: CGFloat = 0
    /// Your pace through the water: 1 normally, a current's speed while you're in one (eased). Riptide Reef's levels
    /// are planned with their currents (`MeetingDesigner`), so planned fish keep real time and still meet you where
    /// planned.
    private var currentPace: CGFloat = 1
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
    /// Bubbles rising from fish hidden deep in the kelp (`kelpHidesFish`), and when each fish lets out its next.
    private var kelpBubbles: [KelpBubble] = []
    /// Your trail's motes, when what you wear has one.
    private let trailMotes = PearlTrailMotes()
    private var nextKelpBubble: [Int: (time: CGFloat, count: Int)] = [:]
    /// After a sting, the result waits until the death animation has played.
    private var pendingLossResultAt: CGFloat?
    /// When a world-conquering win leaves for the conquered screen (see `leavesForConqueredScreen`).
    private var pendingConqueredExitAt: CGFloat?
    private var lastCameraX: CGFloat = 0
    private var hasLayers = false
    private var isBuilt = false

    private var closeCallHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private var eatenHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private var eatenNotification = UINotificationFeedbackGenerator()
    private var mealHaptic = UIImpactFeedbackGenerator(style: .light)
    private var winNotification = UINotificationFeedbackGenerator()
    private var haptics: [UIFeedbackGenerator] { [mealHaptic, closeCallHaptic, eatenHaptic, eatenNotification, winNotification] }
    /// Presented before its view is in a window (the game's view hands it the scene as it's made), so the haptics wait
    /// for the first frame on screen to be woken: iOS may ignore waking a generator for a view not in a window.
    private var hapticsWaitForWindow = false
    /// The Vibration setting (Settings, and the pause menu): off, the game plays no haptics.
    private var vibrates: Bool { ArcadeSettings.shared.vibrationOn }

    /// Makes the haptic generators for the view the scene is shown in, as iOS 17.5 and later expect: each then plays for
    /// that view's window.
    private func makeHaptics(for view: SKView) {
        guard #available(iOS 17.5, *) else { return }
        closeCallHaptic = UIImpactFeedbackGenerator(style: .rigid, view: view)
        eatenHaptic = UIImpactFeedbackGenerator(style: .heavy, view: view)
        eatenNotification = UINotificationFeedbackGenerator(view: view)
        mealHaptic = UIImpactFeedbackGenerator(style: .light, view: view)
        winNotification = UINotificationFeedbackGenerator(view: view)
    }

    /// Wakes the haptics before they're needed. A session's first haptic otherwise stalls while iOS sets them up: the
    /// first death (its two buzzes) froze. Called as the scene appears (once its view is on screen), as each run starts,
    /// and after each haptic, since a woken generator only stays ready a few seconds.
    private func prepareHaptics() {
        guard vibrates, let view else { return }
        guard view.window != nil else {
            hapticsWaitForWindow = true
            return
        }
        hapticsWaitForWindow = false
        #if DEBUG
        noteHitch(.hapticPrepare, "all five generators")
        #endif
        for generator in haptics { generator.prepare() }
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
        // Ready again for the next one.
        for generator in haptics { generator.prepare() }
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
            uiLayer.addChild(openWaterCounts)
            uiLayer.addChild(fishLeftLabel)
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillResignActive),
                name: UIApplication.willResignActiveNotification, object: nil
            )
        }
        #if DEBUG
        hitchLog?.enterScene(self, hitchContext, view: view)
        #endif
        _ = audio // Warm normal gameplay audio; headless studies never create the player pool.
        makeHaptics(for: view)
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

    /// The screen changed size under the level (`PlayfieldView`): an iPhone Duo opened or closed, the player's hands on
    /// the phone rather than the game. A run in play stops under the pause menu, as it does when the app is interrupted.
    func screenDidResize() {
        if phase == .playing { pauseRun() }
    }

    @objc private func appWillResignActive() {
        if phase == .playing { pauseRun() }
        holdTouches.removeAll()
        if let summary = metricAccumulator?.summary { enqueueMetricOperation { $0.checkpoint(summary) } }
        checkpointOpenWaterMetrics()
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
        currentPace = 1
        frameAccumulator = T.frameRemainderStart
        simulationAccumulator = 0
        lastUpdate = nil
        lastDrawnMoment = nil
        zoom = 1
        openWaterBanner?.removeFromParent()
        openWaterBanner = nil
        endOpenWaterWash()
        openWater?.finished = false
        openWaterFinale = openWater == nil ? nil : level.meetingPlan.flatMap(OpenWater.finale)
        spawnOpenWaterPearls()
        if let run = openWater { planOpenWaterLevelAhead(seed: run.seed, index: run.index + 1) }

        world = WrappedWorld(width: size.width * level.worldScreens)
        spawnJellies()
        spawnKelp()
        spawnHooks()
        spawnEcosystem()
        lastCameraX = player.position.x
        capturePresentation()
        // A tutorial retry past its opening goes straight back in; its opening waits for your first touch.
        setPhase(startPlaying || (isTutorial && tutorialCheckpoint != tutorialOpening) ? .playing : .ready)
        buildLevelIndicator()
        buildOpenWaterCounts()
        buildFishLeft()
        _ = render()
        // Now that your fish is drawn, the opening's arrows can sit by it.
        if isTutorial { followTutorialHint() }
    }

    private func spawnEcosystem() {
        let base = T.baseRadius
        let p = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: (waterBottom + waterTop) / 2), radius: base)
        p.velocity = CGVector(dx: playerSpeed, dy: 0)
        player = p
        add(p, style: playerLook.style)
        if let node = nodes[p.id] { playerLook.dress(node) }
        trailMotes.removeAll()

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
            approachEnds[f.id] = (planned.meetingDistance + size.width * T.kelpApproachReleaseScreens,
                                  planned.spawn.y, simClock, planned.approach, planned.headOn ? -1 : 1)
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
        // Yours shines your headlamp; every other fish's glows over the dark.
        if headlamp != nil && (f.isPlayer || T.anglerLures) { node.addChild(Self.anglerLure(phase: CGFloat(f.id), yours: f.isPlayer)) }
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
            frameAccumulator = T.frameRemainderStart
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
        openWaterCounts.isHidden = newPhase == .paused || !showsOpenWaterCounts
        fishLeftLabel.isHidden = newPhase == .paused || fishLeftLabel.text == nil
        if newPhase == .paused {
            refreshSoundToggles()
            configurePauseAccessibility()
        }
        switch newPhase {
        case .ready:
            resultPanel = nil
            if isTutorial {
                // The beat's line and the finger that shows you how: your first touch starts it and lifts you.
                showTutorialStart()
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
                // The Open Water's levels end on their last gate, not as a world's are won: its card names no rules.
                let introduces = !isOpenWater && levelIndex == 0 && hasCleared?(0) != true
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
        if openWater != nil { return "Open Water" }
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
            detail = openWaterSummary ?? lossReason
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
                                      progress: strip, retryOnly: isTutorial,
                                      heading: passed ? nil : openWaterResultHeading, note: passed ? nil : openWaterResultNote,
                                      shopPearls: openWaterShopPearls, outOfRuns: !passed && outOfOpenWaterRuns)
        panel.onSelect = { [weak self] action in self?.selectResult(action) }
        messageNode.addChild(panel)
        resultPanel = panel
        // The run's pearls count up into the rest on the Shop button, once the card's in (they were kept as taken).
        if let run = openWater, run.pearls > 0 {
            panel.countShopPearls(from: max(0, pearlsToSpend - run.pearls), after: 0.5)
        }
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
            element.accessibilityLabel = panel.spokenTitle(control.action)
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

    /// Leaving goes to the home screen, not a level map: the Open Water and the tutorial come from there. (Kraig: the
    /// same Level map button went home from one and to the levels from the other.)
    private var leavesForHome: Bool { openWater != nil || isTutorial }

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
        case .levels, .world, .home:
            #if DEBUG
            finishRunRecording("level_map")
            #endif
            onExit?()
        case .shop:
            // Over the card, which waits underneath: closing the shop comes back to it.
            onShop?()
        case .unlock:
            // The day's runs came back while the card was up (left open past midnight): Retry again, not the unlock.
            guard outOfOpenWaterRuns else {
                showResult(passed: false)
                return
            }
            leaveForOpenWaterUnlock()
        }
    }

    /// The same level again (Retry, Play again, or Restart, by touch or VoiceOver): no card first, just the prompt. In
    /// the Open Water, a new run from its first stage.
    private func replayLevel() {
        // The day's free runs are used up (Restart on the pause menu, mid-run): the unlock's screen instead.
        if outOfOpenWaterRuns {
            leaveForOpenWaterUnlock()
            return
        }
        if let run = openWater {
            // The new run's first level was planned off the main thread as this one ended. If it isn't ready yet (a
            // moment at most), Retry waits for it rather than freeze the game while it's planned here.
            let next = run.seed &+ 1
            if plansOpenWaterAhead && !hasOpenWaterPlan(seed: next, index: 0) {
                openWaterRetryWaits = phase
                planOpenWaterLevelAhead(seed: next, index: 0)
                return
            }
            startNextOpenWaterRun()
        }
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
        currentPace = 1
        replaying = false
        clearedBeforeRun = hasCleared?(levelIndex) ?? false
        // A world still being prototyped (Xcode builds only) never reports: the stats server knows only the campaign's
        // worlds and death causes, and drops a whole batch over one it doesn't.
        // The Open Water reports its runs its own way (`startOpenWaterMetrics`), never as a campaign level.
        var collects = analytics?.enabled == true && !isTutorial && !isOpenWater && ArcadeWorld.campaign.contains(arcadeWorld)
        #if DEBUG
        collects = collects && !simulationHeadless && !debugPracticeRun && ArcadePlaytest.selection == nil
        #endif
        metricDeathCause = "none"
        if collects {
            metricAccumulator = ArcadeMetricAccumulator()
            fatalMetrics = nil
            let context = metricContext, count = arcadeWorld.levelCount
            let cleared = hasCleared?(levelIndex) ?? false
            enqueueMetricOperation { $0.start(context, worldLevelCount: count, alreadyCleared: cleared) }
            observeMetrics()
        }
        startOpenWaterMetrics()
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
        checkpointOpenWaterMetrics()
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
        if !isTutorial { onDeath?(levelIndex) }
        #if DEBUG
        finishRunRecording("lost", fields: ["reason": lossReason])
        noteHitch(.death, resultDelay > 0 ? (reel != nil ? "hooked" : "stung") : "eaten")
        #endif
        // A delayed result (a sting) sounds the loss when the result appears, after the zap.
        if resultDelay == 0 { playSound(.lose) }
        finishOpenWaterMetrics("death")
        if let run = openWater {
            // The run's score is the fish it ate.
            openWaterNewBest = mealsEaten > openWaterBest
            openWaterBest = max(openWaterBest, mealsEaten)
            openWaterEarned = onOpenWaterRun?(mealsEaten, run.index) ?? []
        }
        planNextOpenWaterRunAhead()
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
                    leftTutorialForHome = isTutorial
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
        if hapticsWaitForWindow { prepareHaptics() }
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
        settlePresentationLag(elapsed: realDt, steps: advanceFrame(realDt))
        present(realDt)
    }

    /// Draws the frame `realDt` seconds after the last: the fish where the simulation has them, the camera, and the
    /// specks and sun rays drifting past.
    private func present(_ realDt: CGFloat) {
        let presentation = render()
        let cameraDelta = world.delta(from: lastCameraX, to: presentation.cameraX) * presentation.zoom
        lastCameraX = presentation.cameraX
        updateSpecks(realDt: phase == .paused ? 0 : realDt, cameraDelta: cameraDelta)
        updateSunRays(cameraDelta: cameraDelta, time: realClock)
    }

    /// Display frames only contribute elapsed time. Both real-time slow motion and
    /// gameplay consume fixed ticks, so batching frames cannot change the ecology.
    /// Returns how many real-time steps the frame took.
    @discardableResult
    private func advanceFrame(_ elapsed: CGFloat, beforeStep: (() -> Void)? = nil) -> Int {
        let step = T.simulationStep
        let epsilon: CGFloat = 1e-10
        var steps = 0
        frameAccumulator += min(max(elapsed, 0), T.maximumFrameElapsed)
        while frameAccumulator + epsilon >= step {
            frameAccumulator = max(0, frameAccumulator - step)
            steps += 1
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
        return steps
    }

    /// Frames that each take a step of their own (a 60 Hz display at full speed) draw the newest step; any others
    /// (120 Hz, slow motion) blend the last two. A frame with no time (the first after a pause) changes nothing.
    private func settlePresentationLag(elapsed: CGFloat, steps: Int) {
        guard elapsed > 0 else { return }
        steppedFrames = steps > 0 && timeScale == 1 ? steppedFrames + 1 : 0
        let drawsNewest = steppedFrames >= T.newestStepAfterFrames
        let target = drawsNewest ? 0 : T.simulationStep
        let fall = elapsed * (drawsNewest || timeScale == 1 ? T.presentationLagEase : T.presentationLagSettle)
        let eased = presentationLag + (target - presentationLag).clamped(-fall, elapsed * T.presentationLagEase)
        // Never past the newest step, and never back before what the last frame drew.
        let remainder = presentationRemainder
        let simulating = phase != .ready && phase != .paused
        let latest = lastDrawnMoment.map { simClock + remainder - $0 } ?? .infinity
        presentationLag = min(max(remainder, eased), latest)
        lastDrawnMoment = simulating ? simClock - T.simulationStep * (1 - presentationFraction) : nil
    }

    private func simulate(_ dt: CGFloat) {
        simClock += dt
        if !currents.isEmpty, player.isAlive {
            let pace = currentSpeed(atForwardDistance: forwardDistance, share: waterShare(player.position.y))
            currentPace += (pace - currentPace) * min(1, dt * T.currentEase)
        }
        updateZoom(dt)
        let previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
        // All protected swimmers steer from the same snapshot, not update-order-dependent positions.
        encounterNeighbors = level.meetingPlan == nil ? [] : fish.compactMap {
            !$0.isPlayer && $0.state == .swimming
                ? EncounterNeighbor(id: $0.id, position: $0.position, velocity: $0.velocity, radius: $0.radius) : nil
        }
        for f in fish where f.isAlive {
            if f.isPlayer { movePlayer(f, dt) } else { moveAI(f, dt); sweep(f, dt) }
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
        if phase == .playing { notePassedHooks(); updateHooks() }
        advanceSwallows(dt)
        advanceGrowth(dt)
        advanceTutorial()
        if phase == .playing {
            resolveCollisions()
            updateFishLeft()
            if hasWon { win() }
            if openWater != nil { advanceOpenWater() }
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
        let speed = playerSpeed * currentPace
        p.velocity = CGVector(dx: speed, dy: vy)
        forwardDistance += max(0, speed * dt)
        metricAccumulator?.advance(seconds: Double(simClock), circuits: Double(forwardDistance / world.width))
        p.position = CGPoint(x: world.wrap(p.position.x + speed * dt), y: y)
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
        for bubble in kelpBubbles { bubble.node.removeFromParent() }
        kelpBubbles.removeAll()
        nextKelpBubble.removeAll()
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

    /// How hidden a fish in the kelp is: as deep as it is in the kelp, unless it's near you (`kelpRevealDistance`).
    private func kelpHidden(depth: CGFloat, screenDistance: CGFloat) -> CGFloat {
        guard T.kelpHidesFish, depth > 0 else { return 0 }
        let near = T.kelpRevealDistance, share = screenDistance / size.width
        return depth * ((share - near.lowerBound) / (near.upperBound - near.lowerBound)).clamped(0, 1)
    }

    /// A bubble rising from a fish hidden in the kelp: where it rose in the world, when, and how it wobbles.
    private struct KelpBubble {
        let node: SKSpriteNode
        let x: CGFloat, y: CGFloat, born: CGFloat, alpha: CGFloat, phase: CGFloat
    }

    /// A hidden fish lets out a bubble from its mouth every so often, as faint as the fish is hidden. Over the front
    /// fronds (26) and under all of you (30, tail at -2).
    private func releaseKelpBubble(_ fish: Fish, at mouth: CGPoint, hidden: CGFloat, time: CGFloat) {
        guard hidden > 0.3 else { return }
        let next = nextKelpBubble[fish.id] ?? (time, 0)
        guard time >= next.time else { return }
        // Spacing and sizes vary bubble by bubble, the same way every run, never with the fish's size.
        func jitter(_ salt: Double) -> CGFloat {
            let x = sin(Double(fish.id) * 12.9898 + Double(next.count) * 78.233 + salt) * 43758.5453
            return CGFloat(x - x.rounded(.down))
        }
        let every = T.kelpBubbleEvery, size = T.kelpBubbleRadius
        nextKelpBubble[fish.id] = (time + every.lowerBound + (every.upperBound - every.lowerBound) * jitter(1), next.count + 1)
        let radius = size.lowerBound + (size.upperBound - size.lowerBound) * jitter(2)
        let node = SKSpriteNode(texture: Self.kelpBubbleTexture, size: CGSize(width: radius * 2, height: radius * 2))
        // Each a hair apart, so two can't swap: no two from one fish ten apart are ever up at once.
        node.zPosition = 27 + CGFloat(fish.id) * 0.01 + CGFloat(next.count % 10) * 0.001
        fishLayer.addChild(node)
        kelpBubbles.append(KelpBubble(node: node, x: mouth.x, y: mouth.y, born: time, alpha: 0.85 * min(1, hidden),
                                      phase: jitter(3) * 2 * .pi))
    }

    /// Each bubble where it rose in the water, risen and wobbling, fading out as it goes.
    private func renderKelpBubbles(cameraX: CGFloat, zoom: CGFloat, time: CGFloat) {
        guard !kelpBubbles.isEmpty else { return }
        kelpBubbles.removeAll { bubble in
            let age = time - bubble.born
            guard age < T.kelpBubbleSeconds else {
                bubble.node.removeFromParent()
                return true
            }
            bubble.node.position = CGPoint(
                x: screenAnchorX + world.delta(from: cameraX, to: bubble.x) * zoom + sin(age * 9 + bubble.phase) * 1.5,
                y: waterCenter + (bubble.y - waterCenter) * zoom + age * T.kelpBubbleRise)
            bubble.node.alpha = bubble.alpha * min(1, age / 0.1) * (1 - age / T.kelpBubbleSeconds)
            bubble.node.setScale(1 + 0.3 * age / T.kelpBubbleSeconds)
            return false
        }
    }
    private static let kelpBubbleTexture: SKTexture = {
        let side: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.setFillColor(SKColor(white: 1, alpha: 0.18).cgColor)
            cg.fillEllipse(in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
            cg.setStrokeColor(SKColor(white: 1, alpha: 0.9).cgColor)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: CGRect(x: 2.5, y: 2.5, width: side - 5, height: side - 5))
            // A glint up top, toward the light.
            cg.setFillColor(SKColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: side * 0.24, y: side * 0.2, width: side * 0.24, height: side * 0.24))
        }
        return SKTexture(image: image)
    }()

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
    /// Your own is gold, as in Midnight Zone's picture, and burns steady: your beam shines from it.
    private static let anglerLureName = "anglerLure", anglerLightName = "anglerLight"
    /// Where the lure's light hangs, at the fish's reference size facing right.
    static let anglerLureTip = CGPoint(x: 1.4 * FishNode.referenceRadius, y: 1.25 * FishNode.referenceRadius)
    private static func anglerLure(phase: CGFloat, yours: Bool) -> SKNode {
        let r = FishNode.referenceRadius, tip = anglerLureTip
        let rig = SKNode()
        rig.name = anglerLureName
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.75 * r, y: 0.72 * r))
        path.addQuadCurve(to: tip, control: CGPoint(x: 1.0 * r, y: 1.6 * r))
        let stalk = SKShapeNode(path: path)
        stalk.strokeColor = yours ? SKColor(red: 1, green: 0.84, blue: 0.4, alpha: 1) : SKColor(white: 0.8, alpha: 0.9)
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
        if !yours { light.run(.sequence([.wait(forDuration: Double(phase.truncatingRemainder(dividingBy: 7)) * 0.13), .repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8),
        ]))])) }
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
    private var tutorialCheckpoint: ArcadeTutorial.Beat
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
    /// Under the last beat's line: the fish still to eat.
    private let tutorialFishLeft = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    /// Pearls taken in the Open Water's tutorial: counted as a run counts them, and never kept.
    private var tutorialPearls = 0
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
        // The stats count Adventure's (the first-launch tutorial's events, from before there were others).
        if tutorialCourse == .adventure && tutorialCheckpoint == tutorialOpening { analytics?.tutorial(.started) }
        tutorialPaths.removeAll()
        tutorialMeal = nil; tutorialBigFish = nil; tutorialMissedFish = nil; tutorialMissedMeals = []
        tutorialWall = []; tutorialWallBreach = nil; tutorialWallMeals = []; tutorialSwims = [:]
        tutorialNextBeatAt = nil
        tutorialComesRoundAt = nil
        tutorialCaptionPending = nil
        tutorialLowest = nil
        tutorialPearls = 0
        mealsEaten = ArcadeTutorial.meals(before: tutorialCheckpoint)
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
            tutorialFishLeft.fontSize = T.tutorialCaptionSize * 0.6
            tutorialFishLeft.fontColor = .white
            tutorialFishLeft.verticalAlignmentMode = .center
            tutorialFishLeft.position = CGPoint(x: 0, y: -T.tutorialCaptionSize * 1.55)
            tutorialCaption.addChild(tutorialFishLeft)
            uiLayer.addChild(tutorialCaption)
        }
        tutorialFishLeft.text = nil
        // Under the fish and pearls counted at the top, in the Open Water's.
        let top: CGFloat = showsOpenWaterCounts ? 64 : 30
        tutorialCaption.position = CGPoint(x: size.width / 2, y: size.height - top - T.tutorialCaptionSize / 2)
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
        case .gatherPearls:
            tutorialCaptionPending = beat.caption
            spawnTutorialPearl(low: false)
        }
    }

    /// The Open Water's pearl beat: a pearl ahead of you, and a bigger fish swimming slowly at you just the other side of
    /// the middle, so you go round it to take the pearl, as a run's pearls sit by its big fish. `low`: the other way up.
    private func spawnTutorialPearl(low: Bool) {
        for entry in openWaterPearls { entry.node.removeFromParent() }
        let water = waterTop - waterBottom
        let share = low ? 1 - T.tutorialPearlShare : T.tutorialPearlShare
        let spot = CGPoint(x: world.wrap(player.position.x + T.tutorialPearlAhead * size.width / zoom), y: waterBottom + share * water)
        let node = pearlNode(T.openWaterPearlLook(arcadeWorld))
        // A ring pulsing round it, as round the tutorial's meals.
        let ring = SKShapeNode(circleOfRadius: T.openWaterPearlRadius * 2.2)
        ring.strokeColor = SKColor(white: 1, alpha: 0.8)
        ring.fillColor = .clear
        ring.lineWidth = 2
        ring.zPosition = 0.2
        ring.run(.repeatForever(.sequence([.group([.scale(to: 1.35, duration: 0.8), .fadeOut(withDuration: 0.8)]),
                                           .scale(to: 1, duration: 0), .fadeAlpha(to: 1, duration: 0)])))
        node.addChild(ring)
        fishLayer.addChild(node)
        openWaterPearls = [(OpenWaterPearl(position: spot, phase: 0), node)]
        var guarding = T.tutorialPearlGuard
        if low { guarding.home = 1 - guarding.home }
        var generator = SeededGenerator(seed: T.spawnSeed &+ UInt64(T.tutorialBigFish.rounded()) &* 7_919)
        tutorialBigFish = spawnTutorialSwimmer(T.tutorialBigFish, style: FishStyle.random(using: &generator), swim: guarding)
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
            if simClock >= at {
                if let next = tutorialCourse?.beat(after: tutorialBeat) { beginTutorialBeat(next) } else { finishTutorial() }
            }
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
                // Every fish eaten: the tutorial is done.
                finishTutorial()
                return
            }
            let left = rest.filter { $0.state == .swimming }.count
            tutorialFishLeft.text = left > 0 ? ArcadeTutorial.fishLeft(left) : nil
            // One that got past you comes round the reef again: in from off screen ahead, swimming away from you.
            for f in rest where f.state == .swimming && world.delta(from: player.position.x, to: f.position.x) < -size.width * 0.45 / zoom {
                f.position = CGPoint(x: world.wrap(player.position.x + 0.85 * size.width / zoom), y: f.position.y)
                f.velocity = CGVector(dx: T.tutorialFleeSpeed, dy: 0)
                previousPresentation[f.id] = FishPresentation(f)
            }
        case .gatherPearls:
            takeTouchedOpenWaterPearls()
            if tutorialPearls > 0 {
                // Taken: what pearls are for, a moment, and it's done.
                showTutorialCaption(ArcadeTutorial.pearlsAreFor)
                next(after: T.tutorialPearlsAreForSeconds)
            } else if let pearl = openWaterPearls.first?.pearl,
                      world.delta(from: player.position.x, to: pearl.position.x) < TutorialPath.leaves * size.width / zoom {
                // Missed: another, the other way up, once the fish by this one has gone by too.
                if let id = tutorialBigFish, let guarding = fishByID[id], guarding.state == .swimming { removeFish(guarding) }
                spawnTutorialPearl(low: pearl.position.y > waterBottom + (waterTop - waterBottom) / 2)
            }
        }
    }

    /// The last beat's done: its closing line, then off to its way to play.
    private func finishTutorial() {
        hideTutorialCaption()
        if tutorialCourse == .adventure { analytics?.tutorial(.completed) }
        onTutorialFinished?()
        win()
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
        tutorialFishLeft.text = nil
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
        let line = label(tutorialCourse?.finale ?? "", fontSize: 34, heavy: true)
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

    /// Until your first touch, only the beat's line and the finger that shows you how (Kraig, 2026-10-27: "Just start
    /// with 'hold anywhere to rise'"). After a tutorial before, with no finger to follow, Tap to start under the line,
    /// right of your fish and its arrows.
    private func showTutorialStart() {
        guard tutorialOpening != .holdToRise else {
            messageNode.removeAllActions()
            messageNode.removeAllChildren()
            return
        }
        showStartPrompt()
        let captionBottom = tutorialCaption.position.y - T.tutorialCaptionSize * 0.95
        messageNode.position = CGPoint(x: size.width * 0.64, y: captionBottom - 12 - 24)
    }

    /// Leaves the tutorial for its way to play (its skip control).
    func skipTutorial() {
        guard isTutorial else { return }
        if tutorialCourse == .adventure { analytics?.tutorial(.skipped) }
        #if DEBUG
        finishRunRecording("level_map")
        #endif
        onExit?()
    }

    /// Where your fish sits across the screen: `playerScreenX`, surging ahead in a fast current and easing back a
    /// little in a slow one. Presentation only; the game itself always reckons from `playerScreenX`.
    private var screenAnchorX: CGFloat {
        size.width * (T.playerScreenX + (currentPace - 1) * (currentPace > 1 ? T.currentSurgeAhead : T.currentSurgeBack))
    }
    private var wake: SKEmitterNode?

    /// Riptide Reef's currents, from the level's plan: only where a scenario needs one.
    private var currents: [PlannedCurrent] { level.meetingPlan?.currents ?? [] }

    /// How fast a current carries you at this point of your run and height: 1 outside them. A current is a place on the
    /// lap, there every time round.
    private func currentSpeed(atForwardDistance distance: CGFloat, share: CGFloat) -> CGFloat {
        let place = world.wrap(distance)
        return currents.first { $0.contains(distance: place, share: share) }?.speed ?? 1
    }

    /// A small fish that has met you drifts with any current it's in; big fish and fish on their way to you don't.
    private func sweep(_ f: Fish, _ dt: CGFloat) {
        guard !currents.isEmpty, f.state == .swimming, approachEnds[f.id] == nil, f.radius <= T.currentSweepsRadius else { return }
        guard let current = currents.first(where: { $0.contains(distance: f.position.x, share: waterShare(f.position.y)) }) else { return }
        f.position.x = world.wrap(f.position.x + (current.speed - 1) * playerSpeed * dt)
    }

    /// The currents on screen: each a faint patch along its stretch of the lap, with streaks flowing the way it
    /// pushes you (fast ones cool, slow ones warm). Shown on the first lap, where they are.
    private var currentPatches: [(current: PlannedCurrent, node: SKNode, band: SKSpriteNode, streaks: [(SKSpriteNode, CGFloat, CGFloat)])] = []
    private func layoutCurrents() {
        currentPatches.forEach { $0.node.removeFromParent() }
        currentPatches.removeAll()
        wake?.removeFromParent()
        wake = nil
        guard !currents.isEmpty else { return }
        var rng = SeededGenerator(seed: 0x52495054)
        for current in currents {
            let (bottom, top) = currentBand(current)
            let node = SKNode()
            // Over the water (0) and under the surface line and the specks (1); the scene ignores sibling order, so
            // depth alone decides.
            node.zPosition = 0.8
            let fast = current.speed > 1
            let band = SKSpriteNode(color: fast ? SKColor(red: 0.55, green: 0.92, blue: 1, alpha: 0.13)
                                               : SKColor(red: 1, green: 0.78, blue: 0.5, alpha: 0.11),
                                    size: CGSize(width: 1, height: top - bottom))
            band.anchorPoint = .zero
            node.addChild(band)
            var streaks: [(SKSpriteNode, CGFloat, CGFloat)] = []
            for _ in 0..<T.currentStreaks {
                let streak = SKSpriteNode(color: SKColor(white: 1, alpha: 0.35),
                                          size: CGSize(width: CGFloat.random(in: 18...46, using: &rng), height: 1.5))
                // Over the band.
                streak.zPosition = 0.1
                node.addChild(streak)
                streaks.append((streak, CGFloat.random(in: 0...1, using: &rng), CGFloat.random(in: 0.1...0.9, using: &rng) * band.size.height))
            }
            backgroundLayer.addChild(node)
            currentPatches.append((current, node, band, streaks))
        }
        let bubbles = SKEmitterNode()
        bubbles.particleTexture = WaterTextures.dot()
        bubbles.particleBirthRate = 0
        bubbles.particleLifetime = 0.5
        bubbles.particleLifetimeRange = 0.2
        bubbles.particleSize = CGSize(width: 5, height: 5)
        bubbles.particleScaleRange = 0.6
        bubbles.particleAlpha = 0.55
        bubbles.particleAlphaSpeed = -1
        bubbles.emissionAngle = .pi
        bubbles.emissionAngleRange = 0.25
        bubbles.particleSpeed = T.currentBubbleSpeed
        bubbles.particleSpeedRange = 60
        bubbles.particlePositionRange = CGVector(dx: 6, dy: 14)
        bubbles.zPosition = 29
        fishLayer.addChild(bubbles)
        bubbles.targetNode = fishLayer
        wake = bubbles
    }
    /// Where a current runs on screen, bottom to top: a full-height one fills the water edge to edge, past the margins
    /// your fish keeps from the floor and the surface.
    private func currentBand(_ current: PlannedCurrent) -> (bottom: CGFloat, top: CGFloat) {
        let span = screenWaterTop - screenWaterBottom
        return (current.low <= 0 ? 0 : screenWaterBottom + span * current.low,
                current.high >= 1 ? size.height : screenWaterBottom + span * current.high)
    }

    private func renderCurrents(cameraX: CGFloat, zoom: CGFloat, time: CGFloat) {
        for patch in currentPatches {
            // A place on the lap, measured from its middle, so the whole of it is placed one way round.
            let length = (patch.current.end - patch.current.start) * zoom
            let middle = world.delta(from: cameraX, to: world.wrap((patch.current.start + patch.current.end) / 2))
            let x = screenAnchorX + middle * zoom - length / 2
            patch.node.isHidden = x > size.width || x + length < 0
            if patch.node.isHidden { continue }
            patch.node.position = CGPoint(x: x, y: currentBand(patch.current).bottom)
            patch.band.size.width = length
            let direction: CGFloat = patch.current.speed > 1 ? 1 : -1
            for (streak, offset, y) in patch.streaks {
                let travel = (offset * length + direction * T.currentStreakSpeed * time).truncatingRemainder(dividingBy: max(length, 1))
                streak.position = CGPoint(x: travel < 0 ? travel + length : travel, y: y)
            }
        }
    }

    private func inKelp(_ position: CGPoint) -> Bool {
        kelpBeds.contains { abs(world.delta(from: $0.bed.x, to: position.x)) <= $0.bed.halfWidth }
    }

    /// Columns stay screen-tall at any zoom and narrow as the camera zooms out.
    private func renderKelp(cameraX: CGFloat, zoom: CGFloat, time: CGFloat) {
        for (bed, back, front) in kelpBeds {
            let x = screenAnchorX + world.delta(from: cameraX, to: bed.x) * zoom
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
    private func hookPosition(_ rig: HookRig, time: CGFloat) -> CGPoint {
        let at = HookMotion.position(rig.hook, time: time)
        // Passed: its line is reeled up until the bait hangs just under the surface, wherever the camera has zoomed to.
        guard let passedAt = rig.passedAt else { return CGPoint(x: world.wrap(at.x), y: at.y) }
        let lift = ((time - passedAt - T.sunsetReelUpAfter) / T.sunsetReelUpSeconds).clamped(0, 1)
        guard lift > 0 else { return CGPoint(x: world.wrap(at.x), y: at.y) }
        let shallow = max(at.y, waterTop - T.sunsetReeledDepth / zoom)
        return CGPoint(x: world.wrap(at.x), y: at.y + (shallow - at.y) * lift * lift * (3 - 2 * lift))
    }

    /// Whether a hook is where you'll meet it: passed already, or less than half a lap ahead along your route. One
    /// planned near the end of the lap is, round the loop, just behind where you start, and drawn there it hung behind
    /// you at the start of Sunset Cove 7, out of reach (Kraig: "There's a fish behind me at the beginning of level 7").
    /// Until it's coming up it isn't drawn, and it can't catch you.
    private func isComingUp(_ rig: HookRig, time: CGFloat) -> Bool {
        rig.passedAt != nil || HookMotion.position(rig.hook, time: time).x - forwardDistance < world.width / 2
    }

    /// Notes each hook as you leave it behind: once all of it, boat, line, and bait, is off the left of the screen. By
    /// how far you've really come, not when the planned route passes it, so a player behind the plan (smaller, so
    /// slower across the lap) never sees a hook reel up before they've passed it.
    private func notePassedHooks() {
        for index in hookRigs.indices where hookRigs[index].passedAt == nil {
            let hook = hookRigs[index].hook
            let right = max(HookMotion.position(hook, time: simClock).x, HookMotion.rodX(hook, time: simClock))
            let screenX = size.width * T.playerScreenX + (right - forwardDistance) * zoom
            if screenX + 3 * hook.baitRadius * zoom < 0 { hookRigs[index].passedAt = simClock }
        }
    }

    /// Your fish touching a bait or a hook is caught. The line is harmless, and other fish pass hooks by: they never
    /// take the bait.
    private func updateHooks() {
        guard !hookRigs.isEmpty, reel == nil, player.isAlive else { return }
        // Nor can one catch you once you've done an Open Water level.
        if openWaterLevelDone { return }
        #if DEBUG
        if simulationEcologyProbe { return }
        #endif
        for (index, rig) in hookRigs.enumerated() where isComingUp(rig, time: simClock) {
            let at = hookPosition(rig, time: simClock)
            if HookRules.catches(player.position, radius: player.radius, hook: at, bait: rig.hook.baitRadius, world: world) {
                catchOnHook(index, at: at)
                return
            }
        }
    }

    /// Caught: you're reeled up the line and out of the water (`renderHooks`), then the result.
    private func catchOnHook(_ index: Int, at hook: CGPoint) {
        let reason = "Caught on a hook."
        // The stats server takes this cause from 1.0 (kraigstrong/BrightBench); before that it dropped a batch with it.
        metricDeathCause = "hook"
        if metricAccumulator != nil {
            observeMetrics()
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
        let anchorX = screenAnchorX
        // Between the last two steps, as the fish are drawn.
        let hookTime = max(0, simClock - T.simulationStep * (1 - fraction))
        let waterline = screenWaterTop + 5
        func screen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: anchorX + world.delta(from: cameraX, to: point.x) * zoom, y: waterCenter + (point.y - waterCenter) * zoom)
        }
        for (index, rig) in hookRigs.enumerated() {
            let bait = rig.hook.baitRadius * zoom
            var at = screen(hookPosition(rig, time: hookTime))
            // Measured from its own hook, not the shorter way round the lap from you: for a hook about half a lap away,
            // that could put its rod on the far side of the screen, with a line all the way across.
            let rodX = at.x + (HookMotion.rodX(rig.hook, time: hookTime) - HookMotion.position(rig.hook, time: hookTime).x) * zoom
            let rod = CGPoint(x: rodX, y: waterline + 4 * zoom)
            // The boat runs ahead of its rod, to the left, and a caught fish swings out round its hook.
            let left = min(at.x, rodX - (T.sunsetBoatLength + 40) * zoom) - 3 * max(bait, player.radius * zoom)
            let right = max(at.x, rodX) + 3 * max(bait, player.radius * zoom)
            let hidden = right < 0 || left > size.width || !isComingUp(rig, time: hookTime)
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
                    // An Open Water level you've done can't catch you.
                    if f.isPlayer && openWaterLevelDone { continue }
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
        if victim.isPlayer { metricDeathCause = "tentacles" }
        if victim.isPlayer && metricAccumulator != nil {
            observeMetrics()
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
        nextKelpBubble[id] = nil
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
            let x = screenAnchorX + world.delta(from: cameraX, to: position.x) * zoom
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
                // An Open Water level's last gate is yours to eat: it doesn't eat other fish or get eaten by them.
                if let finale = openWaterFinale, !a.isPlayer, !b.isPlayer, a.id == finale || b.id == finale { continue }
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
                // A bot safe from fish passes through a bigger one, as you do once you've done an Open Water level.
                var safeFromFish = openWaterLevelDone
                #if DEBUG
                safeFromFish = safeFromFish || simulationSafeFromFish
                #endif
                if safeFromFish && (encounter == .firstEatsSecond && b.isPlayer || encounter == .secondEatsFirst && a.isPlayer
                                    || encounter == .tooClose && (a.isPlayer || b.isPlayer)) { continue }
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
        // A fish held to its way in (planned just in time) passes bells by: the plan keeps its way clear of them.
        if approachEnds[f.id] != nil { return false }
        return level.meetingPlan == nil || f.isPlayer || !encounterProtected(f.id) || plannedContactVisible(f.position.x)
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
        if prey.isPlayer { metricDeathCause = "predator" }
        if prey.isPlayer && metricAccumulator != nil {
            observeMetrics()
            metricAccumulator?.fatal(ratio: Double(predator.radius / prey.radius))
            fatalMetrics = metricAccumulator?.summary
            finishMetrics("death") // The fatal interaction is committed; do not reclassify its animation as a quit.
        }
        if prey.isPlayer { finishOpenWaterMetrics("death") }
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
            if openWater != nil {
                if prey.id == openWaterFinale { openWater?.finished = true }
                updateOpenWaterCounts()
            } else if showsOpenWaterCounts {
                updateOpenWaterCounts()
            }
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

    private var presentationRemainder: CGFloat {
        PresentationInterpolation.remainder(simulation: simulationAccumulator, frame: frameAccumulator, timeScale: timeScale)
    }

    private var presentationFraction: CGFloat {
        PresentationInterpolation.fraction(simulationRemainder: simulationAccumulator,
            frameRemainder: frameAccumulator, timeScale: timeScale, lag: presentationLag, step: T.simulationStep)
    }

    private func presentationPose(_ fish: Fish, fraction: CGFloat) -> FishPresentation {
        let current = FishPresentation(fish)
        return previousPresentation[fish.id]?.interpolated(to: current, fraction: fraction, world: world) ?? current
    }

    private func render() -> (cameraX: CGFloat, zoom: CGFloat) {
        let fraction = presentationFraction
        let zoom = previousZoom + (self.zoom - previousZoom) * fraction
        let time = realClock + frameAccumulator
        let playerPose = presentationPose(player, fraction: fraction)
        let cameraX = playerPose.position.x
        let anchorX = screenAnchorX
        let playerScreen = CGPoint(x: anchorX, y: waterCenter + (playerPose.position.y - waterCenter) * zoom)
        renderJellies(cameraX: cameraX, zoom: zoom, fraction: fraction, time: time)
        renderKelp(cameraX: cameraX, zoom: zoom, time: time)
        renderHooks(cameraX: cameraX, zoom: zoom, fraction: fraction, time: time)
        renderCurrents(cameraX: cameraX, zoom: zoom, time: time)
        for f in fish {
            // A stung fish, or you on a hook, is drawn by its own animation.
            guard let node = nodes[f.id], !stungFish.contains(where: { $0.id == f.id }), !(f.isPlayer && reel != nil) else { continue }
            let pose = presentationPose(f, fraction: fraction)
            let screenX = anchorX + world.delta(from: cameraX, to: pose.position.x) * zoom
            let margin = pose.radius * zoom * 3
            node.isHidden = screenX < -margin || screenX > size.width + margin
            if node.isHidden { continue }
            node.position = CGPoint(x: screenX, y: waterCenter + (pose.position.y - waterCenter) * zoom)
            let inKelp = !kelpBeds.isEmpty && !f.isPlayer
            var hidden: CGFloat = 0
            if inKelp {
                // In steps of a twentieth, so a fish is only recolored while it's crossing an edge.
                let depth = kelpShade(pose.position, radius: pose.radius)
                let shade = (depth * 20).rounded() / 20
                if shade != silhouetteShade[f.id] ?? 0 {
                    silhouetteShade[f.id] = shade > 0 ? shade : nil
                    setSilhouette(node, shade)
                }
                hidden = kelpHidden(depth: depth, screenDistance: hypot(node.position.x - playerScreen.x,
                                                                        node.position.y - playerScreen.y))
                node.alpha = 1 - hidden
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
            if inKelp {
                // From its mouth (`FishNode`'s, about 0.8 of its radius ahead).
                let ahead: CGFloat = pose.facing < 0 ? -0.8 : 0.8
                releaseKelpBubble(f, at: CGPoint(x: pose.position.x + ahead * pose.radius, y: pose.position.y),
                                  hidden: hidden, time: time)
            }
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
            if f.isPlayer, let trail = playerLook.trail, phase == .playing, f.isAlive {
                // Under your tail (28), over the kelp's bubbles (27).
                trailMotes.release(trail, position: pose.position, radius: pose.radius, facing: pose.facing, time: time,
                                   into: fishLayer, z: 27.9)
            }
            if f.isPlayer, let wake {
                // Off your tail in a fast current, from your face in a slow one, more the stronger it pushes.
                let r = pose.radius * zoom, push = abs(currentPace - 1) / 0.35
                wake.position = CGPoint(x: node.position.x + (currentPace > 1 ? -1.3 : 1.2) * r, y: node.position.y)
                wake.particleBirthRate = push > 0.08 ? T.currentBubbles * min(1, push) : 0
            }
            if f.isPlayer, let headlamp, let lure = node.childNode(withName: Self.anglerLureName),
               let light = lure.childNode(withName: Self.anglerLightName) {
                // Shining from your lure's light, pointing where you're swimming: rising or falling fast swings it
                // off the far right of the screen.
                headlamp.position = convert(light.position, from: lure)
                headlamp.zRotation = (pose.velocity.dy * zoom / T.motion.maxRiseSpeed).clamped(-1, 1) * T.headlampMaxTilt
            }
        }
        renderStungFish(cameraX: cameraX, zoom: zoom, time: time)
        renderKelpBubbles(cameraX: cameraX, zoom: zoom, time: time)
        trailMotes.render(playerLook.trail, time: time, scale: zoom) { point in
            CGPoint(x: anchorX + world.delta(from: cameraX, to: point.x) * zoom, y: waterCenter + (point.y - waterCenter) * zoom)
        }
        renderOpenWater(cameraX: cameraX, zoom: zoom, fraction: fraction, time: time)
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
            let x = screenAnchorX + world.delta(from: cameraX, to: stung.position.x) * zoom
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
        layoutCurrents()

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
        var heading = plannerName ?? "\(arcadeWorld.title) \(levelIndex + 1)"
        if let openWater { heading = "Open Water · Stage \(openWater.leg.stage)" }
        let text = label(heading, fontSize: 13, heavy: true)
        text.horizontalAlignmentMode = .left
        text.alpha = 0.9
        levelIndicator.addChild(text)
        levelIndicator.position = CGPoint(x: 64, y: size.height - 36)
    }

    /// An Adventure level counts its fish down; a tutorial has its own count, and the Open Water counts what you eat.
    private var showsFishLeft: Bool { !isTutorial && !isOpenWater }

    /// The fish still to eat before you win: every one alive, whoever eats it, and every one still to swim in.
    private var fishLeft: Int { fish.filter { !$0.isPlayer && $0.isAlive }.count + waitingFish.count }

    private func buildFishLeft() {
        fishLeftLabel.fontSize = 15
        fishLeftLabel.fontColor = .white
        fishLeftLabel.verticalAlignmentMode = .center
        fishLeftLabel.horizontalAlignmentMode = .center
        fishLeftLabel.alpha = 0.9
        fishLeftLabel.position = CGPoint(x: size.width / 2, y: size.height - 36)
        fishLeftLabel.text = nil
        updateFishLeft()
    }

    /// Shows the count once it's down to `fishLeftShownFrom`, each meal popping it, and hides it at zero (the win).
    private func updateFishLeft() {
        let left = showsFishLeft ? fishLeft : 0
        let text = left > 0 && left <= T.fishLeftShownFrom ? ArcadeTutorial.fishLeft(left) : nil
        fishLeftLabel.isHidden = phase == .paused || text == nil
        guard text != fishLeftLabel.text else { return }
        fishLeftLabel.text = text
        guard text != nil else { return }
        fishLeftLabel.removeAction(forKey: "pop")
        fishLeftLabel.setScale(left == 1 ? 1.45 : 1.25)
        fishLeftLabel.run(.scale(to: 1, duration: 0.2), withKey: "pop")
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
    /// two columns: Play (Resume as the game's gold button, then Restart level and Level map, or Home) and Sound (the
    /// switches). Built with the scene and on each pause; pausing sets the switches to the current settings.
    private func buildPauseMenu() {
        pauseMenu.removeAllChildren()
        // Built with the scene, before a run is known to be the Open Water's: named for where it goes by the first pause.
        if leavesForHome && mapButton.name != "home" {
            mapButton = MenuButtonRow(title: "Home", symbol: "house.fill", style: .secondary, theme: .arcade)
            mapButton.name = "home"
        }
        let backdrop = MenuBackdrop.node(size: size, theme: .arcade)
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
            element(mapButton, leavesForHome ? "Home" : "Level map") { scene in
                #if DEBUG
                scene.finishRunRecording("level_map")
                #endif
                scene.leftTutorialForHome = scene.isTutorial
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
                let at = hookPosition(rig, time: simClock)
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
        frameAccumulator += T.simulationStep / 4
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
        // A run starts, and resumes, partway to its first step.
        let halfwayToStep = (step - T.frameRemainderStart) / 2
        advanceFrame(halfwayToStep)
        guard simClock == 0 else { return false }
        advanceFrame(halfwayToStep)
        guard abs(simClock - step) < 1e-10 else { return false }
        advanceFrame(step / 2)
        setPhase(.paused)
        let pausedClock = simClock
        advanceFrame(10)
        guard simClock == pausedClock else { return false }
        setPhase(.playing)
        advanceFrame(halfwayToStep)
        guard simClock == pausedClock else { return false }
        advanceFrame(halfwayToStep)
        guard abs(simClock - pausedClock - step) < 1e-10 else { return false }
        let beforeHitch = simClock
        advanceFrame(10)
        guard abs(simClock - beforeHitch - T.maximumFrameElapsed) < 1e-10 else { return false }
        advanceFrame(0)
        guard abs(simClock - beforeHitch - T.maximumFrameElapsed) < 1e-10 else { return false }
        resetGame(startPlaying: true)
        advanceFrame(halfwayToStep)
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

    /// How long the game takes to draw a press, on a display refreshing every `frameInterval` seconds: from the frame
    /// the touch lands on to the first frame that draws you differently, averaged over landing on each frame of a
    /// step. (The display adds its own refresh on top.) Plays the level from the same start pressing once and never.
    func debugTouchToDrawSeconds(frameInterval: Double, level: Int = 0) -> Double {
        // Twelve landings cover every way frames fall against steps at 30, 60, 80, and 120 Hz.
        let landings = 12
        let firstPress = Int((1 / frameInterval).rounded())
        func drawn(pressingAt press: Int?) -> [[CGFloat]] {
            simulationHeadless = true
            simulationEcologyProbe = true
            isBuilt = true
            simulationHolding = false
            resetGame(startPlaying: true)
            return (0..<(firstPress + landings + 8)).map { frame in
                if frame == press { simulationHolding = true }
                update(1_000 + Double(frame) * frameInterval)
                let node = nodes[player.id]!
                return [node.position.x, node.position.y, node.zRotation]
            }
        }
        let control = drawn(pressingAt: nil)
        let delays = (0..<landings).map { offset in
            let press = firstPress + offset
            let pressed = drawn(pressingAt: press)
            let shown = (press..<pressed.count).first { pressed[$0] != control[$0] } ?? pressed.count
            return Double(shown - press) * frameInterval
        }
        return delays.reduce(0, +) / Double(delays.count)
    }

    /// The game moment each frame draws, playing frames at these display timestamps (seconds). `slowMotionAt` starts a
    /// close call's slow motion before that frame.
    func debugDrawnMoments(at timestamps: [Double], slowMotionAt: Int? = nil) -> [Double] {
        simulationHeadless = true
        simulationEcologyProbe = true
        isBuilt = true
        simulationHolding = false
        resetGame(startPlaying: true)
        return timestamps.enumerated().map { frame, timestamp in
            if frame == slowMotionAt {
                slowMoRemaining = T.closeCallSlowDuration
                slowMoFactor = T.closeCallSlowFactor
            }
            update(timestamp)
            return Double(simClock - T.simulationStep * (1 - presentationFraction))
        }
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
    /// `missesThePearl`: keeps clear of the pearl beat's pearls. Ends when it's won or lost.
    func debugPlayTutorial(limit: CGFloat = 90, greedy: Bool = false, missesAWallMeal: Bool = false,
                           from start: ArcadeTutorial.Beat? = nil, lag: CGFloat = 0, eatenOn: ArcadeTutorial.Beat? = nil,
                           letsTheLastFishGo: Bool = false, missesThePearl: Bool = false,
                           onFrame: (() -> Void)? = nil) -> (finished: Bool, beats: [(beat: ArcadeTutorial.Beat, at: CGFloat)], seconds: CGFloat) {
        tutorialCheckpoint = start ?? tutorialOpening
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
            } else if tutorialBeat == .gatherPearls, let pearl = openWaterPearls.first?.pearl {
                // To it, or as far from it as the water goes.
                let high = pearl.position.y > (waterBottom + waterTop) / 2
                target = !missesThePearl ? pearl.position.y : high ? waterBottom + player.radius : waterTop - player.radius
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
    /// An Adventure level's count at the top as drawn (nil when it isn't showing), and the fish it counts.
    var debugFishLeft: (shown: String?, count: Int) { (fishLeftLabel.isHidden ? nil : fishLeftLabel.text, fishLeft) }
    /// The pearl beat's pearls in the water, the ones taken, and the counts at the top (fish, pearls) as drawn.
    var debugTutorialPearls: (inWater: [OpenWaterPearl], taken: Int) { (openWaterPearls.map(\.pearl), tutorialPearls) }
    var debugCounts: (shown: Bool, fish: String?, pearls: String?) {
        (!openWaterCounts.isHidden && !openWaterCounts.children.isEmpty,
         (openWaterCounts.childNode(withName: "fishCount") as? SKLabelNode)?.text,
         (openWaterCounts.childNode(withName: "pearlCount") as? SKLabelNode)?.text)
    }
    /// The tutorial's line at the top, and the fish left under it.
    var debugTutorialCaption: (line: String?, fishLeft: String?) { (tutorialCaption.text, tutorialFishLeft.text) }
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

    /// How fast a current carries you `distance` into your run, at mid-water.
    func debugCurrentSpeed(atForwardDistance distance: CGFloat) -> CGFloat { currentSpeed(atForwardDistance: distance, share: 0.5) }
    /// Each current as last drawn: hidden, or where its band is on screen.
    var debugCurrentBands: [CGRect?] {
        currentPatches.map { $0.node.isHidden ? nil : CGRect(origin: $0.node.position, size: $0.band.size) }
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
    var debugResultHeading: String? { resultPanel?.headingText }
    var debugOpenWaterEarned: [PearlItem] { openWaterEarned }
    var debugResultNote: String? { resultPanel?.noteText }
    var debugResultShopPearls: Int? { resultPanel?.shopPearls }
    var debugResultShownShopPearls: Int? { resultPanel?.shownShopPearls }
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
    /// Whether the haptics are waiting for the scene's view to be on screen before they're woken.
    var debugHapticsWaitForWindow: Bool { hapticsWaitForWindow }
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

    /// Takes `count` of the fish still to eat out of the level as if eaten (swimming ones first, then ones still to swim
    /// in), and plays a step.
    func debugRemoveFish(_ count: Int) {
        var left = count
        for f in fish where !f.isPlayer && f.isAlive && left > 0 {
            f.state = .removed
            left -= 1
        }
        while left > 0, !waitingFish.isEmpty {
            waitingFish.removeFirst()
            left -= 1
        }
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
    /// `onStep` sees the scene after every step, before that step's eaten fish go (`debugWallFrame`).
    func debugEncounterCrossings(radii: [CGFloat]? = nil, eaten: Set<Int> = [], laps: CGFloat = 1,
                                 onStep: (() -> Void)? = nil) -> [EncounterCrossing] {
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
                    headOn: f.velocity.dx < 0, zoom: Double(zoom), speed: Double(abs(f.velocity.dx))))
            }
            onStep?()
            for id in eaten where crossed.contains(id) { if let gone = fishByID[id] { removeFish(gone) } }
        }
        return crossings
    }

    /// Everything that could end your run this step, where it is, for the wall report (`WallSweep`): every fish still
    /// swimming, every hook that could catch you, every bell, and how fast you can rise and fall here.
    var debugWallFrame: WallFrame {
        WallFrame(time: simClock, distance: forwardDistance, x: player.position.x, zoom: zoom, waterBottom: waterBottom,
            waterTop: waterTop, radius: player.radius, verticalScale: inKelp(player.position) ? T.kelpDrag : 1,
            fish: fish.compactMap { f in
                f.isPlayer || f.state != .swimming ? nil : WallFrame.Swimmer(id: f.id, x: f.position.x, y: f.position.y, radius: f.radius)
            },
            hooks: hookRigs.enumerated().compactMap { index, rig in
                guard isComingUp(rig, time: simClock) else { return nil }
                let at = hookPosition(rig, time: simClock)
                return WallFrame.Hook(index: index, x: at.x, y: at.y, bait: rig.hook.baitRadius)
            },
            bells: jellies.enumerated().map { WallFrame.Bell(index: $0, x: $1.position.x, y: $1.position.y) },
            worldWidth: world.width)
    }
    #endif

}

// MARK: - Open Water (`OpenWater`)

extension GameScene {
    /// Plays the Open Water from its first level (`firstLevel`, if it's planned already): nothing is saved to the
    /// campaign, and its runs report their own way (`startOpenWaterMetrics`). Set before the scene is shown.
    /// `planSeconds`: how long the first level took to plan, for the stats. `nextLevel`: the level after it, planned
    /// already, so a test's level change needn't plan (inline on a starved main thread, under CI's load, a plan can take
    /// minutes).
    func startOpenWater(seed: UInt64, firstLevel plan: MeetingPlan? = nil, nextLevel: MeetingPlan? = nil, from index: Int = 0,
                        planSeconds: Double? = nil) {
        if let planSeconds { openWaterSlowestPlan[seed] = planSeconds }
        var run = OpenWaterRun(seed: seed, index: index)
        if let plan { run.store(plan, index: index) }
        if let nextLevel { run.store(nextLevel, index: index + 1) }
        plannerLevel = run.plan(index).level
        arcadeWorld = run.leg.world
        openWater = run
        #if DEBUG
        debugPracticeRun = true
        debugOpenWaterStart = run
        #endif
    }

    #if DEBUG
    /// Where the run is, and its seed.
    var debugOpenWaterLeg: OpenWater.Leg? { openWater?.leg }
    var debugOpenWaterIndex: Int? { openWater?.index }
    var debugOpenWaterSeed: UInt64? { openWater?.seed }
    var debugOpenWaterLevelDone: Bool { openWaterLevelDone }
    func debugOpenWaterHasPlan(_ index: Int) -> Bool { openWater?.hasPlan(index) == true }
    #endif

    /// A run from its first level starts being reported (with the Open Water's events on, and never in a headless
    /// study): its numbers are kept from here and go to the stats when it ends. A run started further on isn't.
    fileprivate func startOpenWaterMetrics() {
        guard let run = openWater else { return }
        openWaterMetrics = nil
        guard run.index == 0, analytics?.collectsOpenWater == true else { return }
        #if DEBUG
        guard !simulationHeadless else { return }
        #endif
        var metrics = OpenWaterMetricAccumulator()
        metrics.planned(seconds: openWaterSlowestPlan[run.seed] ?? 0)
        openWaterMetrics = metrics
        enqueueMetricOperation { $0.startOpenWater() }
    }

    /// The reported run so far: its score is the fish it ate.
    private var openWaterRunMetrics: ArcadeOpenWaterMetrics? {
        guard let metrics = openWaterMetrics, let run = openWater else { return nil }
        return metrics.summary(at: Double(simClock), fish: mealsEaten, pearls: run.pearls, best: mealsEaten > openWaterBest,
                               dressed: analytics?.wearing.isEmpty == false)
    }

    /// The run so far, saved in case the app is closed in the middle of it.
    fileprivate func checkpointOpenWaterMetrics() {
        guard let run = openWaterRunMetrics else { return }
        enqueueMetricOperation { $0.checkpointOpenWater(run) }
    }

    /// The reported run ended: `death` (its cause is the last one recorded) or `quit`. Once only: a death is reported
    /// when the fatal meal is committed, so leaving during the swallow can't make it a quit.
    fileprivate func finishOpenWaterMetrics(_ outcome: String) {
        guard let run = openWaterRunMetrics else { return }
        openWaterMetrics = nil
        let cause = metricDeathCause
        enqueueMetricOperation { $0.finishOpenWater(outcome, cause: cause, run: run) }
    }

    #if DEBUG
    /// Makes a fish half again your size and puts it right on you, for a test of what can catch you.
    func debugPutBiggerFishOnYou() -> Bool {
        guard let other = fish.first(where: { !$0.isPlayer && $0.state == .swimming && !encounterProtected($0.id) })
        else { return false }
        other.radius = player.radius * 1.5
        other.targetRadius = other.radius
        other.position = player.position
        return true
    }
    #endif

    /// Out of the day's free runs: back out, for the unlock's screen (`leftForUnlock`), which says when more come.
    fileprivate func leaveForOpenWaterUnlock() {
        #if DEBUG
        finishRunRecording("unlock")
        #endif
        leftForUnlock = true
        onExit?()
    }

    /// A new run, the next seed on, from its first level (planned while the last run's result showed).
    fileprivate func startNextOpenWaterRun() {
        guard let run = openWater else { return }
        // A Restart in the middle of a run ends it as a quit (after a loss it's already reported).
        finishOpenWaterMetrics("quit")
        openWaterSlowestPlan[run.seed] = nil
        let seed = run.seed &+ 1
        var next = nextOpenWaterRun?.seed == seed ? nextOpenWaterRun! : OpenWaterRun(seed: seed)
        nextOpenWaterRun = nil
        plannerLevel = next.plan(0).level
        openWater = next
        enterOpenWaterWorld(next.leg.world)
    }

    /// A world's own water, light, and dark, and in Midnight Zone your lure.
    private func enterOpenWaterWorld(_ next: ArcadeWorld) {
        guard next != arcadeWorld else { return }
        arcadeWorld = next
        onWorldChange?(next)
        layoutStatic()
        guard let node = nodes[player.id] else { return }
        node.childNode(withName: Self.anglerLureName)?.removeFromParent()
        if headlamp != nil { node.addChild(Self.anglerLure(phase: 0, yours: true)) }
    }

    /// Ends a level once you've swallowed its last gate, and starts the next at once.
    fileprivate func advanceOpenWater() {
        guard phase == .playing, let run = openWater else { return }
        takeTouchedOpenWaterPearls()
        let swallowing = swallows.contains { $0.predatorID == player.id || $0.preyID == player.id }
        guard openWaterLevelDone && player.state == .swimming && !swallowing else { return }
        // The next level is planned off the main thread as this one starts. If it isn't ready yet, this one plays on
        // until it is, rather than freeze the game while it's planned here: seconds, for a Jelly Bloom level on a phone.
        if plansOpenWaterAhead && !run.hasPlan(run.index + 1) {
            openWaterMetrics?.waiting(at: Double(simClock))
            planOpenWaterLevelAhead(seed: run.seed, index: run.index + 1)
            return
        }
        finishOpenWaterLevel()
    }

    /// You've done this level: swallowed its last gate, or come round to its start in one with no gate (none should
    /// be). It ends as soon as the next is planned (`advanceOpenWater`), and till then nothing can catch you.
    private var openWaterLevelDone: Bool {
        guard let run = openWater else { return false }
        return openWaterFinale == nil ? forwardDistance >= world.width : run.finished
    }

    /// You ate the level's last gate: the level-clear chime and buzz, and straight on into the next world, with no
    /// slow motion (Kraig, 2026-10-22).
    private func finishOpenWaterLevel() {
        guard let run = openWater else { return }
        playSound(.clear)
        buzz(.win)
        #if DEBUG
        recordRunEvent("open_water_level_end", fields: ["index": run.index, "stage": run.leg.stage,
            "world": run.leg.world.rawValue, "radius": player.radius, "meals": mealsEaten])
        #endif
        openWaterMetrics?.cleared(at: Double(simClock))
        beginOpenWaterLevel()
        // On into the first world again: all the way round for the first time.
        if openWaterMetrics != nil && openWater?.index == GameTuning.openWaterWorlds.count {
            enqueueMetricOperation { $0.openWaterWentRound() }
        }
        checkpointOpenWaterMetrics()
    }

    /// The world on screen as you leave it, without your fish or the counts: a picture to fade out over the next. It
    /// hides all of the new level but you (Kraig, 2026-10-22: "the world is visible before the camera zoom"): over its
    /// highest part, the pearls (the fish layer's 10, plus 29.7), and under your fish, lifted for the change
    /// (`openWaterWashYouDepth`).
    private func pictureOfLeavingWorld() -> SKSpriteNode? {
        guard let view, let you = nodes[player.id] else { return nil }
        you.isHidden = true
        uiLayer.isHidden = true
        defer {
            you.isHidden = false
            uiLayer.isHidden = false
        }
        guard let texture = view.texture(from: self) else { return nil }
        let picture = SKSpriteNode(texture: texture, size: size)
        picture.anchorPoint = .zero
        picture.zPosition = 39.8
        return picture
    }
    /// Your fish's depth while the change plays (usually 30): its tail (2 under) clear of the last world's picture.
    private static let openWaterWashYouDepth: CGFloat = 33

    /// The change into a level, over: the last world's picture gone, your fish at its usual depth, and the camera where
    /// the level has it. (With none playing there's nothing to undo, and before the first level there's no fish yet.)
    private func endOpenWaterWash() {
        guard let wash = openWaterWash else { return }
        wash.leaving?.removeFromParent()
        openWaterWash = nil
        nodes[player.id]?.zPosition = 30
        for layer in [backgroundLayer, hazardLayer, fishLayer] {
            layer.setScale(1)
            layer.position = .zero
        }
        headlamp?.alpha = 1
    }

    /// The next level, from the start of its lap as a level starts: the last one's fish gone, its world's water and
    /// hazards, you at your starting size, the camera all the way in. It's one shot, not a cut (Kraig, 2026-10-22: "I
    /// don't like it feeling like multiple scenes"): the camera starts close enough that your fish is the size on screen
    /// it was and eases back as the new level plays, the world you left fading away as it moves.
    private func beginOpenWaterLevel() {
        guard var run = openWater else { return }
        let stage = run.leg.stage
        // As you leave: your fish's size and height on screen, and a picture of it all.
        let onScreen = player.radius * zoom
        let height = (player.position.y - waterCenter) * zoom, rising = player.velocity.dy * zoom
        endOpenWaterWash()
        let leaving = pictureOfLeavingWorld()
        for f in fish where !f.isPlayer { removeFish(f) }
        swallows.removeAll()
        for stung in stungFish { stung.node.removeFromParent(); stung.zap.removeFromParent() }
        stungFish.removeAll()
        run.advance()
        let plan = run.plan(run.index)
        openWater = run
        plannerLevel = plan.level
        openWaterFinale = OpenWater.finale(plan)
        world = WrappedWorld(width: size.width * level.worldScreens)
        // Planned meetings count from the level's start: its clock, its distance, and you at the start of its lap.
        simClock = 0
        lastDrawnMoment = nil
        forwardDistance = 0
        currentPace = 1
        bounceRemaining = 0
        bounceCooldown = 0
        encounterLeases.removeAll()
        approachEnds.removeAll()
        encounterNeighbors.removeAll()
        nextFishID = 1
        zoom = 1
        player.radius = T.baseRadius
        player.targetRadius = T.baseRadius
        player.growFrom = T.baseRadius
        player.position = CGPoint(x: 0, y: waterCenter + height)
        player.velocity = CGVector(dx: playerSpeed, dy: rising)
        lastCameraX = player.position.x
        trailMotes.removeAll()
        enterOpenWaterWorld(run.leg.world)
        hazardLayer.removeAllChildren()
        jellies.removeAll()
        spawnJellies()
        spawnKelp()
        spawnHooks()
        spawnPlanned(plan)
        spawnOpenWaterPearls()
        capturePresentation()
        buildLevelIndicator()
        if let leaving { addChild(leaving) }
        nodes[player.id]?.zPosition = Self.openWaterWashYouDepth
        openWaterWash = (realClock + frameAccumulator, max(0.01, onScreen / T.baseRadius), leaving)
        // Midnight Zone's dark comes on as the last world fades.
        headlamp?.alpha = 0
        // "Stage 2" once you're back round to the first world; the worlds speak for themselves.
        if run.leg.stage > stage { showOpenWaterBanner("Stage \(run.leg.stage)") }
        #if DEBUG
        recordRunEvent("open_water_level", fields: ["index": run.index, "stage": run.leg.stage, "world": run.leg.world.rawValue,
            "level": run.leg.level, "seed": String(run.seed), "spec": plan.spec.name, "variation": plan.variation,
            "fish": plan.fish.count])
        #endif
        planOpenWaterLevelAhead(seed: run.seed, index: run.index + 1)
    }

    private func showOpenWaterBanner(_ text: String) {
        openWaterBanner?.removeFromParent()
        let banner = label(text, fontSize: 30, heavy: true)
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.64)
        banner.zPosition = 3
        banner.alpha = 0
        uiLayer.addChild(banner)
        banner.run(.sequence([.fadeIn(withDuration: 0.25), .wait(forDuration: max(0, T.openWaterBannerSeconds - 0.5)),
                              .fadeOut(withDuration: 0.25), .removeFromParent()]))
        openWaterBanner = banner
    }

    /// The level's pearls bobbing where they sit, pearls being gulped, and the change into a new level.
    fileprivate func renderOpenWater(cameraX: CGFloat, zoom: CGFloat, fraction: CGFloat, time: CGFloat) {
        for (pearl, node) in openWaterPearls {
            let x = screenAnchorX + world.delta(from: cameraX, to: pearl.position.x) * zoom
            node.isHidden = x < -20 || x > size.width + 20
            node.position = CGPoint(x: x, y: waterCenter + (pearl.position.y - waterCenter) * zoom
                                    + sin(time * T.openWaterPearlBobRate + pearl.phase) * T.openWaterPearlBob)
        }
        if let you = nodes[player.id] {
            // Pearls being gulped slide into your mouth (about 0.8 of your radius ahead) and shrink away.
            let r = presentationPose(player, fraction: fraction).radius * zoom
            let mouth = CGPoint(x: you.position.x + 0.8 * r, y: you.position.y - 0.1 * r)
            openWaterGulps.removeAll { gulp in
                let t = ((time - gulp.start) / T.openWaterPearlGulpSeconds).clamped(0, 1), eased = t * (2 - t)
                gulp.node.position = CGPoint(x: gulp.from.x + (mouth.x - gulp.from.x) * eased,
                                             y: gulp.from.y + (mouth.y - gulp.from.y) * eased)
                gulp.node.setScale(1 - 0.85 * eased)
                if t >= 1 { gulp.node.removeFromParent() }
                return t >= 1
            }
        }
        renderOpenWaterWash(time: time)
    }

    /// The change into a level: the camera, which starts close on your fish, easing back to where the level has it,
    /// and the world you left fading as it goes. Both start at once and slow as they finish, so the new level shows
    /// only as the camera moves. The water, hazards, and fish are drawn as the level has them and then scaled about
    /// your fish, so it stays put on screen.
    private func renderOpenWaterWash(time: CGFloat) {
        guard let wash = openWaterWash else { return }
        let t = (max(0, time - wash.start) / T.openWaterWashSeconds).clamped(0, 1), eased = 1 - pow(1 - t, 3)
        guard t < 1 else {
            endOpenWaterWash()
            return
        }
        let closer = 1 + (wash.closer - 1) * (1 - eased)
        let you = nodes[player.id]?.position ?? CGPoint(x: screenAnchorX, y: waterCenter)
        for layer in [backgroundLayer, hazardLayer, fishLayer] {
            layer.setScale(closer)
            layer.position = CGPoint(x: you.x * (1 - closer), y: you.y * (1 - closer))
        }
        wash.leaving?.alpha = 1 - eased
        headlamp?.alpha = eased
    }

    /// The level's pearls (`OpenWater.pearls`), in the world's look, replacing the last level's.
    fileprivate func spawnOpenWaterPearls() {
        for entry in openWaterPearls { entry.node.removeFromParent() }
        openWaterPearls.removeAll()
        for gulp in openWaterGulps { gulp.node.removeFromParent() }
        openWaterGulps.removeAll()
        guard openWater != nil, let plan = level.meetingPlan else { return }
        let look = T.openWaterPearlLook(arcadeWorld)
        openWaterPearls = OpenWater.pearls(plan).map { pearl in
            let node = pearlNode(look)
            fishLayer.addChild(node)
            return (pearl, node)
        }
    }
    private static let openWaterPearlDepth: CGFloat = 29.7

    /// A pearl, hidden until it's drawn where it sits.
    private func pearlNode(_ look: (fill: SKColor, rim: SKColor, glow: CGFloat)) -> SKNode {
        let node = SKNode()
        // Over the kelp's front fronds (26) and, at the fish layer's 10, Midnight Zone's dark (39.5), so it glints there;
        // under your fish (30).
        node.zPosition = Self.openWaterPearlDepth
        let glow = SKSpriteNode(texture: ArcadeArt.glow, size: CGSize(width: 34, height: 34))
        glow.color = look.fill
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.alpha = look.glow
        glow.zPosition = -0.1
        let ball = SKShapeNode(circleOfRadius: T.openWaterPearlRadius)
        ball.fillColor = look.fill
        ball.strokeColor = look.rim
        ball.lineWidth = 1.5
        let shine = SKShapeNode(circleOfRadius: 2.2)
        shine.fillColor = .white
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -2.5, y: 2.5)
        shine.zPosition = 0.1
        for part in [glow, ball, shine] as [SKNode] { node.addChild(part) }
        node.isHidden = true
        return node
    }

    /// Touching a pearl takes it: it counts, and that's all (it doesn't grow you or slow you down).
    private func takeTouchedOpenWaterPearls() {
        guard player.isAlive else { return }
        let reach = player.radius + T.openWaterPearlRadius / zoom
        for index in openWaterPearls.indices.reversed() where world.distance(player.position, openWaterPearls[index].pearl.position) < reach {
            let taken = openWaterPearls.remove(at: index)
            openWater?.pearls += 1
            // The Open Water's tutorial counts its pearl, and never keeps it.
            if isTutorial { tutorialPearls += 1 } else { onPearl?() }
            // The run's first pearl makes it one of the day's free runs.
            if openWater?.pearls == 1 { onOpenWaterRunCounted?() }
            // A gulp: your mouth snaps open (and closes as after any bite), and the pearl goes into it.
            player.mouth = 1
            openWaterGulps.append((taken.node, taken.node.position, realClock))
            playSound(.eat)
            buzz(.meal)
            updateOpenWaterCounts()
            #if DEBUG
            recordRunEvent("open_water_pearl", fields: ["pearls": openWater?.pearls ?? 0, "x": taken.pearl.position.x,
                                                        "y": taken.pearl.position.y])
            #endif
        }
    }

    #if DEBUG
    /// The level's pearls still in the water.
    var debugOpenWaterPearls: [OpenWaterPearl] { openWaterPearls.map(\.pearl) }

    /// Ends the level as eating its last gate does: the next begins.
    func debugFinishOpenWaterLevel() { finishOpenWaterLevel() }

    /// Your fish on screen: its radius, and its height from the middle of the water.
    var debugYouOnScreen: (radius: CGFloat, height: CGFloat) {
        (player.radius * zoom, (player.position.y - waterCenter) * zoom)
    }

    /// How much closer the camera is starting than the level has it, while the change into a level plays.
    var debugOpenWaterWashCloser: CGFloat? { openWaterWash?.closer }

    /// Puts your fish on the level's first pearl and plays a step: the run's pearls, and your radius before and after.
    func debugTakeFirstPearl() -> (pearls: Int, before: CGFloat, after: CGFloat)? {
        guard let first = openWaterPearls.first else { return nil }
        let before = player.radius
        player.position = first.pearl.position
        advanceFrame(T.simulationStep)
        return (openWater?.pearls ?? 0, before, player.radius)
    }
    #endif

    /// The run's fish eaten and pearls, top middle: a fish and a pearl, each with its count. The Open Water's tutorial
    /// counts them too.
    private var showsOpenWaterCounts: Bool { openWater != nil || tutorialCourse == .openWater }

    fileprivate func buildOpenWaterCounts() {
        openWaterCounts.removeAllChildren()
        guard showsOpenWaterCounts else { return }
        let fishIcon = SKSpriteNode(texture: Self.openWaterFishIcon)
        fishIcon.position = CGPoint(x: -46, y: 0)
        let pearl = PearlShopArt.pearlIcon(radius: 7)
        pearl.position = CGPoint(x: 22, y: 0)
        for (name, x) in [("fishCount", -32.0), ("pearlCount", 34.0)] {
            let count = label("0", fontSize: 15, heavy: true)
            count.name = name
            count.horizontalAlignmentMode = .left
            count.position = CGPoint(x: x, y: 0)
            openWaterCounts.addChild(count)
        }
        openWaterCounts.addChild(fishIcon)
        openWaterCounts.addChild(pearl)
        openWaterCounts.alpha = 0.9
        openWaterCounts.position = CGPoint(x: size.width / 2, y: size.height - 36)
        updateOpenWaterCounts()
    }

    fileprivate func updateOpenWaterCounts() {
        (openWaterCounts.childNode(withName: "fishCount") as? SKLabelNode)?.text = "\(mealsEaten)"
        (openWaterCounts.childNode(withName: "pearlCount") as? SKLabelNode)?.text = "\(openWater?.pearls ?? tutorialPearls)"
    }

    private static let openWaterFishIcon: SKTexture = {
        let symbol = UIImage(systemName: "fish.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))!
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        return SKTexture(image: UIGraphicsImageRenderer(size: symbol.size).image { _ in symbol.draw(at: .zero) })
    }()

    /// Whether levels are planned ahead, off the main thread, as the game plans them: never as it reaches them, which
    /// would freeze it (seconds, for a Jelly Bloom level on a phone). The headless studies plan each level as they reach
    /// it instead, so they play the same however fast they run.
    private var plansOpenWaterAhead: Bool {
        #if DEBUG
        return (!simulationHeadless || debugPlansOpenWaterAhead) && !debugPlansOpenWaterInline
        #else
        return true
        #endif
    }

    /// Plans a level off the main thread, ahead of reaching it, unless it's planned or being planned already: one of
    /// this run's, or of the next run's while this one's result shows.
    fileprivate func planOpenWaterLevelAhead(seed: UInt64, index: Int) {
        guard plansOpenWaterAhead, !hasOpenWaterPlan(seed: seed, index: index) else { return }
        let key = OpenWaterPlanKey(seed: seed, index: index)
        guard openWaterPlanning.insert(key).inserted else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let started = DispatchTime.now()
            let plan = OpenWater.plan(index, seed: seed)
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
            DispatchQueue.main.async { self?.receiveOpenWaterPlan(plan, for: key, seconds: seconds) }
        }
    }

    /// The next run's first two levels, planned while this run's result shows: Retry waits on the first, and the
    /// second (a Jelly Bloom level, the slowest to plan) comes up soon after.
    fileprivate func planNextOpenWaterRunAhead() {
        guard let run = openWater else { return }
        for index in 0...1 { planOpenWaterLevelAhead(seed: run.seed &+ 1, index: index) }
    }

    private func hasOpenWaterPlan(seed: UInt64, index: Int) -> Bool {
        [openWater, nextOpenWaterRun].contains { $0?.seed == seed && $0?.hasPlan(index) == true }
    }

    /// A level planned off the main thread: kept for this run or the next (any other run's is too late), and a Retry
    /// waiting on the next run's first level goes ahead.
    private func receiveOpenWaterPlan(_ plan: MeetingPlan, for key: OpenWaterPlanKey, seconds: Double) {
        openWaterPlanning.remove(key)
        guard let run = openWater else { return }
        if key.seed == run.seed { openWaterMetrics?.planned(seconds: seconds) }
        if key.seed == run.seed || key.seed == run.seed &+ 1 {
            openWaterSlowestPlan[key.seed] = max(openWaterSlowestPlan[key.seed] ?? 0, seconds)
        }
        if key.seed == run.seed {
            openWater?.store(plan, index: key.index)
        } else if key.seed == run.seed &+ 1 {
            if nextOpenWaterRun?.seed != key.seed { nextOpenWaterRun = OpenWaterRun(seed: key.seed) }
            nextOpenWaterRun?.store(plan, index: key.index)
        }
        guard let waiting = openWaterRetryWaits, hasOpenWaterPlan(seed: run.seed &+ 1, index: 0) else { return }
        openWaterRetryWaits = nil
        if phase == waiting { replayLevel() }
    }

    #if DEBUG
    /// One level's start, as the tests check it.
    struct OpenWaterLevelStart {
        let index: Int
        let world: ArcadeWorld
        let radius: CGFloat
        let zoom: CGFloat
        let forwardDistance: CGFloat
        let clock: CGFloat
        /// Fish swimming or waiting to appear, and how many the level's plan has.
        let fish: Int
        let planned: Int
        let worldWidth: CGFloat
        let jellies: Int
        let kelp: Int
        let hooks: Int
        let dark: Bool
    }

    /// Plays the Open Water headless until level `untilLevel` (counting from 0) starts, the run ends, or `limit` game
    /// seconds have passed (every level's added up), along each level's reference route as `debugPlayReferenceRoute`
    /// does, then cleaning up like the collector bot. `safeFromFish`: nothing can eat you. Returns where it got, each
    /// level's start, the biggest you grew, and whether a level was ever won (it never should be).
    func debugPlayOpenWater(untilLevel: Int, limit: CGFloat = 400, safeFromFish: Bool = false)
        -> (index: Int, lost: Bool, won: Bool, reason: String, starts: [OpenWaterLevelStart], largest: CGFloat) {
        simulationHeadless = true
        simulationEcologyProbe = false
        simulationHolding = false
        simulationSafeFromFish = safeFromFish
        defer { simulationSafeFromFish = false }
        resetGame(startPlaying: true)
        func start() -> OpenWaterLevelStart {
            OpenWaterLevelStart(index: openWater?.index ?? -1, world: arcadeWorld, radius: player.radius, zoom: zoom,
                forwardDistance: forwardDistance, clock: simClock, fish: fish.count - 1 + waitingFish.count,
                planned: level.meetingPlan?.fish.count ?? 0, worldWidth: world.width, jellies: jellies.count,
                kelp: kelpBeds.count, hooks: hookRigs.count, dark: headlamp != nil)
        }
        var reference = Set<Int>(), route: [EncounterCrossing] = [], stops: [(time: CGFloat, y: CGFloat)] = [], next = 0
        func load() {
            guard let plan = level.meetingPlan else { return }
            reference = Set(plan.fish.filter(\.referenceMeal).map(\.id))
            route = plan.predicted.filter { reference.contains($0.fishID) }.sorted { $0.time < $1.time }
            stops = [(time: CGFloat(0), y: player.position.y)] + route.map { (time: CGFloat($0.time), y: CGFloat($0.y)) }
            next = 0
        }
        func wanted(at time: CGFloat) -> (y: CGFloat, weight: CGFloat) {
            guard let after = stops.firstIndex(where: { $0.time > time }) else { return (stops.last!.y, 1) }
            let a = stops[max(0, after - 1)], b = stops[after]
            let y = a.y + (b.y - a.y) * ((time - a.time) / max(0.01, b.time - a.time)).clamped(0, 1)
            return (y, min(time - a.time, b.time - time) < 0.06 ? 25 : 1)
        }
        load()
        var starts = [start()], largest = player.radius, elapsed: CGFloat = 0, steps = 0
        while phase == .playing, elapsed < limit, let index = openWater?.index, index < untilLevel {
            while next < route.count, CGFloat(route[next].time) < simClock - 0.2
                    || (fishByID[route[next].fishID].map { $0.state != .swimming }
                        ?? !waitingFish.contains { $0.id == route[next].fishID }) {
                next += 1
            }
            if steps % 3 == 0 {
                // What the bots see, and the bells too, so it swims over domes and round tentacles.
                let seen = botObservation
                let bells = level.jellies.map { layout in
                    jellies.filter { abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width / zoom }
                        .map { ArcadeSimulation.Bell(x: $0.position.x, y: $0.position.y, radius: layout.radius,
                                                     tentacles: layout.tentacleLength) }
                } ?? []
                var observation = ArcadeSimulation.Observation(player: seen.player, fish: seen.fish, bells: bells,
                    width: seen.width, screenWidth: seen.screenWidth, zoom: seen.zoom, bottom: seen.bottom, top: seen.top,
                    speed: seen.speed, bouncing: seen.bouncing, bounceSpeed: seen.bounceSpeed, hooks: seen.hooks)
                if next < route.count {
                    let visible = fish.filter { !$0.isPlayer && $0.state == .swimming && !reference.contains($0.id)
                        && abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width * 0.8 / zoom }
                    func swimmer(_ f: Fish) -> ArcadeSimulation.Swimmer {
                        .init(x: f.position.x, y: f.position.y, vx: f.velocity.dx, vy: f.velocity.dy, radius: f.radius)
                    }
                    let yours = player.targetRadius
                    let edible = { (f: Fish) in GameRules.playerEncounter(yours, f.radius) == .firstEatsSecond }
                    observation.fish = safeFromFish ? [] : visible.filter { !edible($0) }.map(swimmer)
                    observation.avoids = visible.filter(edible).map(swimmer)
                    observation.threatMargin = 10
                    observation.seeksFood = false
                } else {
                    if safeFromFish {
                        let yours = player.radius
                        observation.fish = observation.fish.filter { GameRules.playerEncounter(yours, $0.radius) == .firstEatsSecond }
                    }
                    observation.hookMargin = 40
                }
                let now = simClock
                simulationHolding = ArcadeSimulation.holding(observation, policy: .collector,
                                                             path: next < route.count ? { wanted(at: now + $0) } : nil)
            }
            advanceFrame(T.simulationStep)
            steps += 1
            elapsed += T.simulationStep
            largest = max(largest, player.radius)
            if let now = openWater?.index, now != starts.last?.index {
                starts.append(start())
                load()
            }
        }
        return (openWater?.index ?? -1, phase == .lost, phase == .won, phase == .lost ? lossReason : "", starts, largest)
    }

    /// The result card's line, once the run has ended.
    var debugResultDetail: String? { openWaterSummary }

    /// Restart, as the pause menu's does.
    func debugRestart() { replayLevel() }
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
            let center = screen(f.position), you = screen(player.position)
            let depth = kelpBeds.isEmpty || f.isPlayer ? 0 : kelpShade(f.position, radius: f.radius)
            return StoreCapture.Swimmer(id: f.id, center: center, radius: f.radius * zoom, prey: prey,
                                        isEaten: eaten, shrink: f.shrink, shade: depth,
                                        hidden: kelpHidden(depth: depth, screenDistance: hypot(center.x - you.x, center.y - you.y)))
        }
        return StoreCapture.SceneView(size: size, time: simClock, playing: phase == .playing, won: phase == .won,
                                      player: swimmer(player), rising: player.velocity.dy * zoom,
                                      fish: fish.filter { !$0.isPlayer && $0.state != .removed }.map(swimmer),
                                      jellies: jellies.map { screen($0.position) }, jellyRadius: (level.jellies?.radius ?? 0) * zoom,
                                      lastBounce: debugBounces.last { $0.fishID == player.id }?.time,
                                      hooks: hookRigs.filter { $0.passedAt == nil }.map { rig in
                                          // Its rod measured from its own hook, as `renderHooks` draws it.
                                          let bait = screen(hookPosition(rig, time: simClock))
                                          let rod = HookMotion.rodX(rig.hook, time: simClock) - HookMotion.position(rig.hook, time: simClock).x
                                          return StoreCapture.Hook(bait: bait, rodX: bait.x + rod * zoom)
                                      },
                                      pearls: openWaterPearls.map { screen($0.pearl.position) },
                                      fishCounted: Int(debugCounts.fish ?? "") ?? 0,
                                      pearlsCounted: Int(debugCounts.pearls ?? "") ?? 0)
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
            // Where it really is, reeled up or not.
            let now = hookPosition(rig, time: simClock), soon = hookPosition(rig, time: simClock + 0.05)
            guard abs(world.delta(from: player.position.x, to: now.x)) < size.width / zoom else { return nil }
            let bait = rig.hook.baitRadius
            return .init(x: now.x, y: now.y - 0.1 * bait, vx: world.delta(from: now.x, to: soon.x) / 0.05, vy: (soon.y - now.y) / 0.05,
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
    func debugHookPosition(_ index: Int) -> CGPoint { hookPosition(hookRigs[index], time: simClock) }
    /// When hook `index` went off the left of the screen behind you, if it has.
    func debugHookPassedAt(_ index: Int) -> CGFloat? { hookRigs[index].passedAt }
    /// Whether a hook's bait is drawn this frame.
    func debugHookShows(_ index: Int) -> Bool { !hookRigs[index].bait.isHidden }
    /// How far up the water hook `index`'s bait hangs now, as on screen: 0 the bottom, 1 the top.
    func debugHookDepthShare(_ index: Int) -> CGFloat { waterShare(debugHookPosition(index).y) }
    /// How wide each hook line on show was drawn across the screen (points).
    var debugHookLineWidths: [CGFloat] {
        hookRigs.filter { !$0.line.isHidden }.compactMap { $0.line.path?.boundingBoxOfPath.width }
    }

    /// Puts your fish on hook `index` (its bait's center, its bend under the bait, or its line well above the hook), as
    /// big as it is now, and checks the hooks. Returns whether you were caught.
    func debugTouchHook(_ index: Int, at part: HookPart) -> Bool {
        let hook = hookRigs[index].hook, at = hookPosition(hookRigs[index], time: simClock), bait = hook.baitRadius
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
        let rig = hookRigs[index]
        player.position.x = world.wrap(hookPosition(rig, time: simClock).x + world.width / 2)
        simulationEcologyProbe = true
        defer { simulationEcologyProbe = false }
        let steps = Int((seconds / T.simulationStep).rounded())
        for _ in 0..<steps {
            other.position = hookPosition(rig, time: simClock)
            simulate(T.simulationStep)
            guard other.isAlive, fishByID[other.id] != nil else { return false }
        }
        return other.isAlive && fishByID[other.id] != nil && phase == .playing && reel == nil
    }

    /// The level from the start, playing at once, as a first touch starts it.
    func debugCaptureRestart() {
        // An Open Water run plays from its first level again, its pearls and planned levels as they started: starting
        // a level over keeps where the run had got to, so each of a capture's runs would begin where the last ended.
        if var start = debugOpenWaterStart {
            plannerLevel = start.plan(start.index).level
            arcadeWorld = start.leg.world
            openWater = start
        }
        resetGame(startPlaying: false)
        startRun()
    }

    /// No pause button, level name, or card over the frame. An Open Water run keeps its fish and pearls counted at the
    /// top, where they show pearls being taken, unless `keepingCounts` is false (a screenshot's caption goes there).
    func debugHideInterface(keepingCounts: Bool = true) {
        guard openWater != nil, keepingCounts else {
            uiLayer.isHidden = true
            return
        }
        for node in uiLayer.children where node !== openWaterCounts { node.isHidden = true }
    }

    /// One display frame of `seconds`, played and drawn as `update` does, specks and sun rays included: for footage
    /// recorded a frame at a time (`StoreFootage`).
    func debugFrame(seconds: CGFloat) {
        settlePresentationLag(elapsed: seconds, steps: advanceFrame(seconds))
        present(seconds)
    }
}
#endif
