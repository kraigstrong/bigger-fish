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

/// A fish stung by tentacles or urchins: it jolts, rolls belly-up, and sinks out of sight.
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

final class GameScene: SKScene {
    private enum Phase { case ready, playing, paused, won, lost }
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
    private var foodRefillCooldown: CGFloat = 0
    private let mealIndicator = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var hasWon: Bool {
        GameRules.isWin(fish) && waitingFish.isEmpty
    }
    let arcadeWorld: ArcadeWorld
    private var levelIndex: Int {
        didSet { worldLevel = seeded ? arcadeWorld.seededLevels[levelIndex] : arcadeWorld.level(levelIndex) }
    }
    /// Plays the world's original seeded levels instead of its planned ones (the generator's tests).
    private let seeded: Bool
    /// The level being played (it advances with Next level), for the map to return to.
    var currentLevelIndex: Int { levelIndex }
    /// This slot's level, looked up once: `level` is read for every fish on every step.
    private var worldLevel: Level
    private var level: Level {
        var base = worldLevel
        #if DEBUG
        if let plannerLevel { return plannerLevel }
        // Planned levels are fixed data; debug references and overrides would throw their fish off plan.
        if base.meetingPlan != nil { return base }
        let setupIndex = simulationReferenceIndex ?? base.ecosystemSeedIndex ?? levelIndex
        if arcadeWorld == .jellyBloom, activeDebugTuning?.difficulty == nil,
           activeDebugTuning != nil, setupIndex < T.bloomReferenceLevels.count {
            base = T.bloomReferenceLevels[setupIndex]
            base.ecosystemSeedIndex = setupIndex
        }
        // The reference picker selects original levels by displayed number, independently of campaign order.
        let shallowReferenceIndex = simulationReferenceIndex ?? levelIndex
        if arcadeWorld == .shallowReef, activeDebugTuning?.difficulty == nil,
           activeDebugTuning != nil, shallowReferenceIndex < T.shallowReferenceLevels.count {
            base = T.shallowReferenceLevels[shallowReferenceIndex]
            base.ecosystemSeedIndex = shallowReferenceIndex
        }
        // Debug tuning edits seeded campaign levels; a planned level is its plan.
        if base.meetingPlan != nil { return base }
        return activeDebugTuning?.applying(to: base) ?? base
        #else
        return base
        #endif
    }
    private var bounceSpeed: CGFloat {
        #if DEBUG
        return activeDebugTuning.map { CGFloat($0.bounceSpeed) } ?? T.jellyBounceSpeed
        #else
        return T.jellyBounceSpeed
        #endif
    }
    private var pocketReleaseSeconds: CGFloat {
        #if DEBUG
        return activeDebugTuning.map { CGFloat($0.releaseSeconds) } ?? T.bloomFoodPocketReleaseSeconds
        #else
        return T.bloomFoodPocketReleaseSeconds
        #endif
    }
    private var unevenJellies: Bool {
        #if DEBUG
        return activeDebugTuning?.unevenJellies ?? level.roamingFoodChain
        #else
        return level.roamingFoodChain
        #endif
    }
    private var layoutVariation: CGFloat {
        #if DEBUG
        return activeDebugTuning.map { CGFloat($0.layoutVariation) } ?? 1
        #else
        return 1
        #endif
    }
    private var seedOffset: UInt64 {
        #if DEBUG
        return activeDebugTuning.map { UInt64($0.seedOffset) } ?? level.ecosystemSeedOffset
        #else
        return level.ecosystemSeedOffset
        #endif
    }
    private var isFinalLevel: Bool {
        #if DEBUG
        if plannerLevel != nil { return true }
        if simulationReferenceIndex != nil { return levelIndex == T.bloomReferenceLevels.count - 1 }
        #endif
        // The original seeded campaigns stop at ten; the planned Shallow Reef goes on to its bonus levels.
        return levelIndex == (seeded ? arcadeWorld.seededLevels.count : arcadeWorld.levelCount) - 1
    }
    var analytics: ArcadeAnalytics?
    var metricsHasCleared: ((Int) -> Bool)?
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
    var onJellyLesson: (() -> Void)?
    private var showsJellyLesson: Bool
    private var lossReason = "There was a bigger fish."
    private var jellies: [BloomJelly] = []
    private var urchins: [(x: CGFloat, node: SKNode)] = []
    private var foodHomes: [Int: CGPoint] = [:]
    private var sidePocketHomes: [Int: CGPoint] = [:]
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
    private var mapButton = SKShapeNode()
    private var resultPanel: ArcadeResultPanel?
    #if DEBUG
    private var simulationTuning: ArcadeTuning?
    private var simulationReferenceIndex: Int?
    private var simulationHolding: Bool?
    private var simulationStats = ArcadeSimulation.Stats()
    private var simulationEcologyProbe = false
    private var simulationLaps: CGFloat = 0
    private var simulationDelayedPasses: CGFloat = 0
    private var simulationFirstPassMealLimit: Int?
    private var simulationSkippedFishIDs: Set<Int> = []

    private func simulationCanEat(_ prey: Fish) -> Bool {
        simulationMayFeed && !(simulationLaps < 1 && simulationSkippedFishIDs.contains(prey.id))
    }

    private var simulationMayFeed: Bool {
        guard simulationTuning != nil else { return true }
        if simulationLaps < simulationDelayedPasses { return false }
        if simulationLaps < 1, let limit = simulationFirstPassMealLimit {
            let committed = swallows.filter { $0.predatorID == player.id }.count
            return mealsEaten + committed < limit
        }
        return true
    }
    private var activeDebugTuning: ArcadeTuning?
    /// A planned test level, played outside the campaign.
    private var plannerLevel: Level?
    /// On-screen contacts between two planned fish you haven't met, which bend their planned paths.
    private(set) var debugVisibleUnmetContacts = 0
    var debugPracticeRun = false
    var debugHasTuningOverride: Bool { activeDebugTuning != nil }
    func debugPauseForTuning() { if phase == .playing { pauseRun() } }
    private let previewResult = ArcadePlaytest.resultPreview
    private var didPreviewResult = false
    private var runRecorder: ArcadeRunRecorder?
    private var recordingStartedAt: CGFloat = 0
    private var recordedEncounterReleases: Set<Int> = []
    #endif
    private var audio: ArcadeAudio { .shared }
    private var settings: ArcadeSettings { .shared }

    init(world: ArcadeWorld = .shallowReef, levelIndex: Int = 0,
         showsJellyLesson: Bool = true, seeded: Bool = false) {
        arcadeWorld = world
        self.seeded = seeded
        self.levelIndex = min(max(0, levelIndex), (seeded ? world.seededLevels.count : world.levelCount) - 1)
        worldLevel = seeded ? world.seededLevels[self.levelIndex] : world.level(self.levelIndex)
        self.showsJellyLesson = showsJellyLesson
        super.init(size: T.playfieldSize)
        scaleMode = .aspectFit
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var rng = SeededGenerator(seed: T.spawnSeed)
    private var aiMovementRNGs: [Int: SeededGenerator] = [:]
    private var ecosystemSeed: UInt64 {
        if let plan = level.meetingPlan { return plan.seed }
        return level.spawnSeed(index: levelIndex, bloom: arcadeWorld.hasJellies, offset: seedOffset)
    }

    /// Domain-separated streams use stable fish IDs, without consuming spawn randomness.
    private var jellyLayoutSeed: UInt64 {
        level.encounterDifficulty != nil ? ecosystemSeed &+ 1_000
            : T.spawnSeed &+ UInt64((level.ecosystemSeedIndex ?? levelIndex) + 1_000) &+ seedOffset
    }

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
    private var resumeButton = SKShapeNode()
    private var restartButton = SKShapeNode()
    private var effectsButton = SKShapeNode()
    private var musicButton = SKShapeNode()

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
    private var approachEnds: [Int: (until: CGFloat, y: CGFloat)] = [:]
    private var kelpBeds: [(bed: PlannedKelp, back: KelpNode, front: KelpNode, height: CGFloat)] = []
    /// Fish drawn as silhouettes while in kelp, and the colors each of their shapes had before.
    private var silhouetted: Set<Int> = []
    private var silhouetteColors: [ObjectIdentifier: (fill: SKColor, stroke: SKColor)] = [:]
    /// After a sting, the result waits until the death animation has played.
    private var pendingLossResultAt: CGFloat?
    private var lastCameraX: CGFloat = 0
    private var hasLayers = false
    private var isBuilt = false

    private let closeCallHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let eatenHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let eatenNotification = UINotificationFeedbackGenerator()

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
    private var aiSpeedScale: CGFloat {
        1
    }
    private var isHolding: Bool {
        #if DEBUG
        return simulationHolding ?? !holdTouches.isEmpty
        #else
        return !holdTouches.isEmpty
        #endif
    }
    private func playSound(_ effect: ArcadeAudio.Effect) {
        #if DEBUG
        if simulationTuning != nil { return }
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
        _ = audio // Warm normal gameplay audio; headless studies never create the player pool.
        closeCallHaptic.prepare()
        eatenHaptic.prepare()
        if !isBuilt { build() }
    }

    override func willMove(from view: SKView) {
        #if DEBUG
        finishRunRecording("scene_closed")
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
        // Saved tuner overrides are for the old seeded levels; planned levels play as shipped.
        activeDebugTuning = simulationTuning ?? (plannerLevel == nil && worldLevel.meetingPlan == nil
            ? ArcadeTuningStore.sceneOverride(world: arcadeWorld, index: levelIndex) : nil)
        #endif
        for node in nodes.values { node.removeFromParent() }
        nodes.removeAll()
        for stung in stungFish { stung.node.removeFromParent(); stung.zap.removeFromParent() }
        stungFish.removeAll()
        pendingLossResultAt = nil
        fish.removeAll()
        fishByID.removeAll()
        swallows.removeAll()
        hazardLayer.removeAllChildren()
        jellies.removeAll()
        urchins.removeAll()
        foodHomes.removeAll()
        sidePocketHomes.removeAll()
        encounterLeases.removeAll()
        forwardDistance = 0
        encounterNeighbors.removeAll()
        #if DEBUG
        recordedEncounterReleases.removeAll()
        debugBounces.removeAll()
        #endif
        nextFishID = 1
        aiMovementRNGs.removeAll()
        movementVariants.removeAll()
        mealsEaten = 0
        foodRefillCooldown = 0
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
        rng = SeededGenerator(seed: ecosystemSeed)
        spawnJellies()
        spawnKelp()
        spawnEcosystem()
        lastCameraX = player.position.x
        capturePresentation()
        setPhase(startPlaying ? .playing : .ready)
        buildLevelIndicator()
        _ = render()
    }

    private func spawnEcosystem() {
        let base = T.baseRadius
        let p = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: (waterBottom + waterTop) / 2), radius: base)
        p.velocity = CGVector(dx: playerSpeed, dy: 0)
        player = p
        add(p, style: .player)

        if let plan = level.meetingPlan {
            spawnPlanned(plan)
            return
        }
        if let difficulty = level.encounterDifficulty {
            spawnEncounters(difficulty)
            return
        }

        let predatorCount = level.spawnGroups.filter { $0.radii.lowerBound >= 1 }.reduce(0) { $0 + $1.count }
        var predatorIndex = 0
        var foodIndex = 0
        for group in level.spawnGroups {
            for _ in 0..<group.count {
                let normalized = CGFloat.random(in: group.radii, using: &rng)
                let r = normalized * base
                var preferredX: CGFloat?
                var preferredY: CGFloat?
                var isSidePocket = false
                var isFood = false
                if normalized < 1 && level.bounceFoodPockets, let layout = level.jellies, !jellies.isEmpty {
                    let jellyIndex = foodIndex % jellies.count
                    let jelly = jellies[jellyIndex]
                    isFood = true
                    isSidePocket = level.sidePocketExperiment && jellyIndex == T.bloomSidePocketJellyIndex
                    preferredX = world.wrap(jelly.origin.x + (isSidePocket ? T.bloomSidePocketOffset : 0))
                    preferredY = isSidePocket ? jelly.origin.y - T.bloomSidePocketDrop
                        : jelly.origin.y + layout.radius * 0.65 + r + T.bloomFoodPocketLift
                    foodIndex += 1
                }
                if normalized >= 1 && (level.predatorSpawnSeparationScreens > 0 || level.sidePocketExperiment) {
                    // Reserve evenly spaced starts so random packing cannot drop the last predator.
                    let start = T.spawnClearAheadDanger + 0.05
                    let end = T.worldScreens - T.spawnClearBehind - 0.05
                    if level.predatorSpawnSeparationScreens > 0 {
                        preferredX = size.width * (start + (end - start) * CGFloat(predatorIndex) / CGFloat(max(1, predatorCount - 1)))
                    }
                    if level.sidePocketExperiment && predatorIndex == 0 {
                        let jelly = jellies[T.bloomSidePocketJellyIndex]
                        preferredX = world.wrap(jelly.origin.x + T.bloomSidePredatorOffset)
                        preferredY = jelly.origin.y - T.bloomSidePocketDrop
                        isSidePocket = true
                    }
                    predatorIndex += 1
                }
                guard let pos = findSpawnPoint(radius: r, dangerous: normalized >= T.spawnDangerRatio,
                                              preferredX: preferredX, preferredY: preferredY,
                                              pocketHalfWidth: isSidePocket ? T.bloomSidePocketSpawnHalfWidth : nil) else { continue }
                spawnAIFish(radius: r, at: pos)
                if isFood { foodHomes[nextFishID - 1] = pos }
                if isSidePocket { sidePocketHomes[nextFishID - 1] = pos }
            }
        }
    }

    private func spawnEncounters(_ difficulty: EncounterDifficulty) {
        if level.freeEncounterMovement { spawnFreeEncounters(difficulty); return }
        guard let layout = level.jellies else { return }
        let foodRadius = T.baseRadius * T.encounterFoodRadius
        let threatRadius = T.baseRadius * difficulty.returnRadius(food: T.encounterFoodRadius,
            efficiency: level.effectiveAbsorptionEfficiency)
        let formations = T.encounterFormationOrder(seed: ecosystemSeed)
        for (encounter, jelly) in jellies.enumerated() {
            let center = jelly.origin
            let foodY = center.y + layout.radius * 0.65 + foodRadius + difficulty.clearance
            let exit = center.x + size.width * T.encounterExitScreens
            let release = exit + CGFloat(difficulty.recoveryPasses) * world.width
            // Develop variety in 1–5; leave the later prototypes' geometry intact.
            let formation = levelIndex < 5 ? formations[encounter % formations.count] : T.encounterFormations[0]
            for slot in 0..<T.encounterFoodCount {
                let offset = formation.foodOffsets[slot]
                let home = CGPoint(x: center.x + offset.x * size.width, y: foodY + offset.y)
                spawnAIFish(radius: foodRadius, at: home)
                let id = nextFishID - 1
                foodHomes[id] = home
                encounterLeases[id] = EncounterLease(home: home, releaseDistance: release, index: encounter)
            }
            let home = CGPoint(x: center.x + size.width * formation.threatOffset,
                y: min(waterTop - threatRadius - T.encounterPatrolHeight,
                    foodY + foodRadius + threatRadius + difficulty.clearance))
            spawnAIFish(radius: threatRadius, at: home)
            encounterLeases[nextFishID - 1] = EncounterLease(home: home, releaseDistance: release, index: encounter)
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
            approachEnds[f.id] = (planned.meetingDistance + size.width * T.kelpApproachReleaseScreens, planned.spawn.y)
        }
    }

    private func spawnFreeEncounters(_ difficulty: EncounterDifficulty) {
        var expectedRadius: CGFloat = 1
        let shallow = arcadeWorld == .shallowReef
        let catchFraction = T.freeEncounterExpectedCatchFraction(difficulty.bounded, shallow: shallow)
        let budgets = T.freeEncounterWaveBudgets(seed: ecosystemSeed, difficulty: difficulty.bounded,
            preserveLevelTwo: !shallow && levelIndex == 1, shallow: shallow)
        var layoutGenerator = SeededGenerator(seed: ecosystemSeed &+ 0xBF58476D1CE4E5B9)
        let centers: [CGPoint]
        if shallow {
            var centerGenerator = SeededGenerator(seed: ecosystemSeed &+ 0xD1B54A32D192ED03)
            centers = (0..<T.encounterCount).map { index in
                let jitter = CGFloat.random(in: -T.freeEncounterHorizontalVariation...T.freeEncounterHorizontalVariation, using: &centerGenerator) * layoutVariation
                return CGPoint(x: size.width * (T.encounterFirstScreens + CGFloat(index) * T.encounterSpacingScreens + jitter), y: waterCenter)
            }
        } else {
            centers = jellies.map(\.origin)
        }
        for (encounter, center) in centers.enumerated() {
            let count = budgets[encounter].count
            let edibleCount = budgets[encounter].edible
            var edibleArea: CGFloat = 0
            for slot in 0..<count {
                let edible = slot < edibleCount
                let ratio = CGFloat.random(in: edible ? T.freeEncounterEdibleSizes : T.freeEncounterThreatSizes, using: &rng)
                let normalized = expectedRadius * ratio
                let radius = T.baseRadius * normalized
                let preferredX = center.x + size.width * (CGFloat(slot) / CGFloat(count - 1) - 0.5) * 0.5
                // Alternating high/low food, with predators occasionally on the upper right.
                let baseHeight: CGFloat = edible ? (slot.isMultiple(of: 2) ? 0.22 : 0.78) : 0.83
                let height = !shallow && levelIndex == 1 ? baseHeight
                    : (baseHeight + CGFloat.random(in: -0.16...0.16, using: &layoutGenerator)).clamped(0.15, 0.88)
                guard let home = findSpawnPoint(radius: radius, dangerous: !edible,
                    preferredX: preferredX, preferredY: waterBottom + (waterTop - waterBottom) * height,
                    pocketHalfWidth: size.width * T.freeEncounterSpawnSpreadScreens) else { continue }
                spawnAIFish(radius: radius, at: home)
                let id = nextFishID - 1
                if edible { foodHomes[id] = home; edibleArea += normalized * normalized }
                // Release each fish after its own starting location, without extra recovery laps.
                encounterLeases[id] = EncounterLease(home: home,
                    releaseDistance: home.x + size.width * T.freeEncounterReleaseScreens, index: encounter)
            }
            expectedRadius = sqrt(expectedRadius * expectedRadius + level.effectiveAbsorptionEfficiency * edibleArea * catchFraction)
        }
    }

    private func encounterProtected(_ id: Int) -> Bool {
        encounterLeases[id]?.isProtected(distance: forwardDistance) ?? false
    }

    private func spawnAIFish(radius: CGFloat, at position: CGPoint) {
        let f = Fish(id: nextFishID, isPlayer: false, position: position, radius: radius)
        nextFishID += 1
        f.heading = Bool.random(using: &rng) ? 1 : -1
        f.cruiseSpeed = CGFloat.random(in: level.aiSpeedRange, using: &rng) * aiSpeedScale
        f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
        f.facing = f.heading
        f.targetY = position.y
        f.retargetTimer = CGFloat.random(in: T.aiRetargetRange, using: &rng)
        f.turnTimer = CGFloat.random(in: T.aiTurnIntervalRange, using: &rng)
        f.phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)
        add(f, style: FishStyle.random(using: &rng))
        if level.jellies != nil {
            // Keep Level 1's seeded ecosystem stable after removing its old AI personality draw.
            _ = CGFloat.random(in: 0...1, using: &rng)
        }

    }

    private func replenishFood(_ dt: CGFloat) {
        foodRefillCooldown = max(0, foodRefillCooldown - dt)
        guard foodRefillCooldown == 0,
              GameRules.needsFood(fish, mealsEaten: mealsEaten, requiredMeals: level.requiredMeals) else { return }
        foodRefillCooldown = T.bloomFoodRefillSeconds
        for _ in 0..<T.bloomFoodRefillCount {
            let radius = min(player.radius * CGFloat.random(in: T.bloomFoodRadiusFraction, using: &rng),
                             (waterTop - waterBottom) * 0.1)
            if let position = findSpawnPoint(radius: radius, dangerous: false) {
                spawnAIFish(radius: radius, at: position)
            }
        }
    }

    private func findSpawnPoint(radius r: CGFloat, dangerous: Bool, preferredX: CGFloat? = nil, preferredY: CGFloat? = nil, pocketHalfWidth: CGFloat? = nil) -> CGPoint? {
        let clearBehind = size.width * T.spawnClearBehind
        let clearAhead = size.width * (dangerous ? T.spawnClearAheadDanger : T.spawnClearAheadSmall)
        let halfWidth = pocketHalfWidth ?? T.bloomFoodPocketHalfWidth
        // Try the authored pocket first, then widen it before using open water. A crowded
        // pocket must not silently remove food from the level's growth budget.
        for attempt in 0..<1500 {
            let expansion: CGFloat = attempt < 500 ? 1 : 2
            let usePocket = attempt < 1000
            let x = (usePocket ? preferredX : nil).map {
                world.wrap($0 + (preferredY != nil ? CGFloat.random(in: (-halfWidth * expansion)...(halfWidth * expansion), using: &rng) : 0))
            } ?? CGFloat.random(in: 0..<world.width, using: &rng)
            let minY = waterBottom + r, maxY = waterTop - r
            let pocketY = (usePocket ? preferredY : nil)?.clamped(minY + T.bloomFoodPocketHalfHeight, maxY - T.bloomFoodPocketHalfHeight)
            let lowerY = pocketY.map { max(minY, $0 - T.bloomFoodPocketHalfHeight * expansion) } ?? minY
            let upperY = pocketY.map { min(maxY, $0 + T.bloomFoodPocketHalfHeight * expansion) } ?? maxY
            let y = CGFloat.random(in: lowerY...upperY, using: &rng)
            let dx = world.delta(from: player.position.x, to: x)
            if dx > -clearBehind && dx < clearAhead { continue }
            let point = CGPoint(x: x, y: y)
            let overlaps = fish.contains {
                world.distance($0.position, point) < ($0.radius + r) * T.collisionScale + T.spawnPadding
            }
            let crowdsPredator = r >= T.baseRadius && level.predatorSpawnSeparationScreens > 0 && fish.contains {
                !$0.isPlayer && $0.radius >= T.baseRadius &&
                abs(world.delta(from: $0.position.x, to: point.x)) < size.width * level.predatorSpawnSeparationScreens
            }
            let inJelly = jellies.contains { jelly in
                guard let layout = level.jellies else { return false }
                let relative = CGPoint(x: world.delta(from: jelly.position.x, to: point.x),
                                       y: point.y - jelly.position.y)
                let paddedContact = JellyRules.contact(at: relative, previous: relative, fishRadius: r,
                    domeRadius: layout.radius + T.spawnPadding, tentacleLength: layout.tentacleLength + T.spawnPadding)
                // Inflating a curved bell shifts its surface; its bounce band isn't a superset.
                let actualContact = level.freeEncounterMovement ? JellyRules.contact(at: relative,
                    previous: relative, fishRadius: r, domeRadius: layout.radius,
                    tentacleLength: layout.tentacleLength) : .none
                return paddedContact != .none || actualContact != .none
            }
            if !overlaps && !crowdsPredator && !inJelly { return point }
        }
        return nil
    }

    private func add(_ f: Fish, style: FishStyle) {
        if !f.isPlayer { aiMovementRNGs[f.id] = movementGenerator(for: f.id) }
        fish.append(f)
        fishByID[f.id] = f
        let node = FishNode(style: style, isPlayer: f.isPlayer, tailPhase: CGFloat(f.id) * 1.7)
        node.zPosition = f.isPlayer ? 30 : 1 + CGFloat(f.id) * 0.5
        nodes[f.id] = node
        fishLayer.addChild(node)
    }

    // MARK: - Phases

    private func setPhase(_ newPhase: Phase) {
        if newPhase != .won && newPhase != .lost { accessibilityElements = nil }
        if newPhase == .ready || newPhase == .paused || phase == .ready || phase == .paused {
            frameAccumulator = 0
            simulationAccumulator = 0
            if newPhase == .ready || newPhase == .paused || phase == .paused { lastUpdate = nil }
            capturePresentation()
        }
        phase = newPhase
        pauseButton.isHidden = newPhase != .playing
        pauseMenu.isHidden = newPhase != .paused
        if newPhase == .paused {
            buildSoundToggles()
            configurePauseAccessibility()
        }
        switch newPhase {
        case .ready:
            resultPanel = nil
            messageNode.position = CGPoint(x: size.width * 0.63, y: size.height / 2)
            let lines = arcadeWorld.hasJellies
                ? (showsJellyLesson ? ["Bounce the tops.", "Never touch the bottoms.", "Be the last fish swimming."]
                                   : ["Be the last fish swimming.", "Bounce domes. Dodge tentacles."])
                : ["Hold to rise. Release to fall.", "Eat smaller fish. Avoid bigger fish."]
            showMessage(levelTitle, lines: lines)
        case .playing, .paused:
            hideMessage()
        case .won:
            showResult(passed: true)
        case .lost:
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

    private func showResult(passed: Bool) {
        holdTouches.removeAll()
        messageNode.removeAllActions()
        messageNode.removeAllChildren()
        messageNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let detail = passed
            ? (isFinalLevel ? "\(plannerName ?? arcadeWorld.title) complete!" : "\(levelTitle) complete!")
            : lossReason
        let panel = ArcadeResultPanel(size: size, passed: passed, hasNext: !isFinalLevel, detail: detail)
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
            guard phase == .won, !isFinalLevel else { return }
            levelIndex += 1
            layoutStatic()
            resetGame(startPlaying: false)
        case .playAgain, .tryAgain:
            resetGame(startPlaying: false)
        case .levels, .world:
            #if DEBUG
            finishRunRecording("level_map")
            #endif
            onExit?()
        }
    }

    private func startRun() {
        if arcadeWorld.hasJellies && showsJellyLesson {
            onJellyLesson?()
            showsJellyLesson = false
        }
        simClock = 0
        var collects = analytics?.enabled == true
        #if DEBUG
        collects = collects && simulationTuning == nil && !debugPracticeRun && !debugHasTuningOverride && ArcadePlaytest.selection == nil
        #endif
        if collects {
            metricAccumulator = ArcadeMetricAccumulator()
            fatalMetrics = nil; metricDeathCause = "none"
            let context = metricContext, count = arcadeWorld.levelCount
            let cleared = metricsHasCleared?(levelIndex) ?? false
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
        #endif
        onClear?(levelIndex, Double(simClock))
        playSound(.clear)
        setPhase(.won)
        endedAt = realClock
        slowMoFactor = T.winSlowFactor
        slowMoRemaining = T.winSlowDuration
        dimNode.run(.fadeAlpha(to: 0.35, duration: 0.6))

        let glow = SKShapeNode(circleOfRadius: player.radius * zoom * 1.8)
        glow.strokeColor = SKColor(white: 1, alpha: 0.8)
        glow.fillColor = .clear
        glow.lineWidth = 3
        glow.zPosition = 29
        glow.run(.repeatForever(.sequence([
            .group([.scale(to: 1.6, duration: 1.0), .fadeOut(withDuration: 1.0)]),
            .scale(to: 1, duration: 0),
            .fadeAlpha(to: 0.8, duration: 0),
        ])))
        fishLayer.addChild(glow)
        winGlow = glow
    }

    private func lose(resultDelay: CGFloat = 0) {
        if resultDelay > 0 { pendingLossResultAt = realClock + resultDelay }
        finishMetrics("death")
        #if DEBUG
        finishRunRecording("lost", fields: ["reason": lossReason])
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
                if resumeButton.frame.insetBy(dx: -10, dy: -10).contains(p) {
                    setPhase(.playing)
                    #if DEBUG
                    recordRunEvent("resume")
                    #endif
                } else if restartButton.frame.insetBy(dx: -10, dy: -10).contains(p) {
                    resetGame(startPlaying: false)
                } else if effectsButton.frame.insetBy(dx: -8, dy: -8).contains(p) {
                    toggleSound(effects: true)
                } else if musicButton.frame.insetBy(dx: -8, dy: -8).contains(p) {
                    toggleSound(effects: false)
                } else if mapButton.frame.insetBy(dx: -10, dy: -10).contains(p) {
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
        if let previewResult, !didPreviewResult {
            didPreviewResult = true
            setPhase(previewResult ? .won : .lost)
            endedAt = realClock
        }
        #endif
        let frameElapsed = max(lastUpdate.map { CGFloat(currentTime - $0) } ?? 0, 0)
        #if DEBUG
        let frameWorkStarted = ProcessInfo.processInfo.systemUptime
        #endif
        let realDt = min(frameElapsed, T.maximumFrameElapsed)
        lastUpdate = currentTime
        advanceFrame(realDt)

        let presentation = render()
        let cameraDelta = world.delta(from: lastCameraX, to: presentation.cameraX) * presentation.zoom
        lastCameraX = presentation.cameraX
        updateSpecks(realDt: phase == .paused ? 0 : realDt, cameraDelta: cameraDelta)
        #if DEBUG
        let workSeconds = ProcessInfo.processInfo.systemUptime - frameWorkStarted
        if phase == .playing && (frameElapsed > T.debugFrameHitchSeconds || workSeconds > Double(T.debugFrameHitchSeconds)) {
            recordRunEvent("frame_hitch", fields: ["elapsedSeconds": frameElapsed,
                "workSeconds": workSeconds, "playerMeals": mealsEaten,
                "fishCount": fish.count, "timeScale": timeScale])
        }
        #endif
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
                if phase == .lost { playSound(.lose); showResult(passed: false) }
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
        encounterNeighbors = level.encounterDifficulty == nil && level.meetingPlan == nil ? [] : fish.compactMap {
            !$0.isPlayer && $0.state == .swimming
                ? EncounterNeighbor(id: $0.id, position: $0.position, velocity: $0.velocity, radius: $0.radius) : nil
        }
        for f in fish where f.isAlive {
            if f.isPlayer { movePlayer(f, dt) } else { moveAI(f, dt) }
        }
        releaseWaitingFish()
        #if DEBUG
        for (id, lease) in encounterLeases where !lease.isProtected(distance: forwardDistance) {
            let key = level.freeEncounterMovement ? id : lease.index
            if recordedEncounterReleases.insert(key).inserted {
                recordRunEvent("encounter_release", fields: ["encounter": lease.index + 1, "fishID": id,
                    "forwardDistance": forwardDistance, "releaseDistance": lease.releaseDistance])
            }
        }
        #endif
        if phase == .playing {
            updateJellies(dt, previousFish: previous)
            if phase == .playing { updateUrchins(previousFish: previous) }
        }
        advanceSwallows(dt)
        advanceGrowth(dt)
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
            motion.maxRiseSpeed = bounceSpeed
            motion.fallAcceleration *= 0.35
        }
        if inKelp(p.position) {
            motion.riseAcceleration *= T.kelpDrag
            motion.fallAcceleration *= T.kelpDrag
            motion.maxRiseSpeed *= T.kelpDrag
            motion.maxFallSpeed *= T.kelpDrag
        }
        let (y, vy) = PlayerMotion.step(
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
        let growth = player.radius / (T.baseRadius * T.zoomStartSize)
        let target = growth > 1 ? max(T.minZoom, pow(1 / growth, T.zoomExponent)) : 1
        zoom += (target - zoom) * min(1, dt * T.zoomEase)
    }

    private func patrolHome(for id: Int) -> CGPoint? {
        if level.freeEncounterMovement {
            // A minority linger in broad areas; most roam before and after release.
            return level.meetingPlan == nil && id.isMultiple(of: 4) ? encounterLeases[id]?.home : nil
        }
        if let lease = encounterLeases[id] {
            return lease.isProtected(distance: forwardDistance) ? lease.home : nil
        }
        if level.roamingFoodChain && simClock >= pocketReleaseSeconds { return nil }
        return sidePocketHomes[id] ?? foodHomes[id]
    }

    private func moveAI(_ f: Fish, _ dt: CGFloat) {
        if let approach = approachEnds[f.id] {
            // Held to its line, so nothing it passes on the way can push it off its meeting.
            if forwardDistance < approach.until {
                f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
                f.position = CGPoint(x: world.wrap(f.position.x + f.velocity.dx * dt), y: approach.y)
                f.facing = f.heading
                return
            }
            approachEnds[f.id] = nil
            f.targetY = f.position.y
        }
        if !level.freeEncounterMovement, let lease = encounterLeases[f.id], lease.isProtected(distance: forwardDistance) {
            moveProtectedAI(f, lease: lease, dt: dt)
            return
        }
        var movementRNG = aiMovementRNGs[f.id] ?? movementGenerator(for: f.id)
        defer { aiMovementRNGs[f.id] = movementRNG }
        let home = patrolHome(for: f.id)
        let leash = home.map { home in
            (offset: world.delta(from: home.x, to: f.position.x),
             halfWidth: level.freeEncounterMovement ? size.width * T.freeEncounterLingerScreens
                : (sidePocketHomes[f.id] != nil ? T.bloomSidePocketPatrolHalfWidth : size.width * T.bloomFoodPatrolScreens))
        }
        let verticalHome = level.freeEncounterMovement ? nil : home
        let minY = max(waterBottom + f.radius, verticalHome.map { $0.y - T.bloomFoodPocketHalfHeight } ?? waterBottom)
        let maxY = max(minY, min(waterTop - f.radius, verticalHome.map { $0.y + T.bloomFoodPocketHalfHeight } ?? waterTop))
        let steered = FreeSwim.steer(f, dt: dt, clock: simClock, minY: minY, maxY: maxY,
            verticalSpeed: level.aiVerticalSpeed, leash: leash, rng: &movementRNG)
        var vx = steered.dx, vy = steered.dy

        if level.freeEncounterMovement && encounterProtected(f.id) {
            // A planned fish only steers around other planned fish you haven't met, and only where you can see it;
            // anyone else gives way to it.
            for other in encounterNeighbors where other.id != f.id
                && (level.meetingPlan == nil || encounterProtected(other.id) && plannedContactVisible(f.position.x)) {
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
        if level.freeEncounterMovement {
            let direction: CGFloat = abs(swimX) > 2 ? (swimX >= 0 ? 1 : -1) : f.heading
            f.facing += (direction - f.facing) * min(1, dt * T.freeEncounterFacingRate)
        } else {
            f.facing = (swimX / 20).clamped(-1, 1)
        }
    }

    private func moveProtectedAI(_ f: Fish, lease: EncounterLease, dt: CGFloat) {
        var generator = aiMovementRNGs[f.id] ?? movementGenerator(for: f.id)
        defer { aiMovementRNGs[f.id] = generator }
        let halfWidth = min(T.encounterPatrolWidth, size.width * 0.06)
        // Keep small fish above their bell even at the tightest difficulty target.
        let halfHeight = foodHomes[f.id] != nil
            ? min(T.encounterPatrolHeight, (level.encounterDifficulty?.clearance ?? 32) * 0.35)
            : T.encounterPatrolHeight
        let minY = max(waterBottom + f.radius, lease.home.y - halfHeight)
        let maxY = max(minY, min(waterTop - f.radius, lease.home.y + halfHeight))
        let offset = world.delta(from: lease.home.x, to: f.position.x)
        if offset > halfWidth - T.encounterTurnLead { f.heading = -1 }
        if offset < -halfWidth + T.encounterTurnLead { f.heading = 1 }
        f.retargetTimer -= dt
        if f.retargetTimer <= 0 {
            f.targetY = CGFloat.random(in: minY...maxY, using: &generator)
            f.retargetTimer = CGFloat.random(in: T.aiRetargetRange, using: &generator)
        }
        f.targetY = f.targetY.clamped(minY, maxY)
        let targetVX = f.heading * f.cruiseSpeed * T.encounterPatrolSpeedScale
            * (1 + 0.15 * sin(simClock * 0.7 + f.phase))
        let targetVY = ((f.targetY - f.position.y) * 1.5).clamped(-level.aiVerticalSpeed, level.aiVerticalSpeed)
            + sin(simClock * 1.3 + f.phase) * 4
        var vx = f.velocity.dx + (targetVX - f.velocity.dx) * min(1, dt * 4)
        var vy = f.velocity.dy + (targetVY - f.velocity.dy) * min(1, dt * 3)
        for other in encounterNeighbors where other.id != f.id {
            let relative = CGVector(dx: world.delta(from: other.position.x, to: f.position.x),
                dy: f.position.y - other.position.y)
            if let separation = EncounterSteering.separation(relative: relative,
                velocity: CGVector(dx: vx - other.velocity.dx, dy: vy - other.velocity.dy),
                reach: (f.radius + other.radius) * T.collisionScale + T.encounterSeparationPadding,
                stableDirection: f.id < other.id ? -1 : 1) {
                vx += separation.dx * min(1, dt * 4)
                vy += separation.dy * min(1, dt * 4)
            }
        }
        if let avoidance = bloomAvoidance(for: f, velocity: CGVector(dx: vx, dy: vy)) {
            let steer = min(1, dt * T.bloomAvoidanceTurnRate)
            vx += (avoidance.dx - vx) * steer
            vy += (avoidance.dy - vy) * steer
        }
        var nextOffset = offset + vx * dt
        if nextOffset > halfWidth { nextOffset = halfWidth; vx = -abs(vx); f.heading = -1 }
        if nextOffset < -halfWidth { nextOffset = -halfWidth; vx = abs(vx); f.heading = 1 }
        var y = f.position.y + vy * dt
        if y < minY { y = minY; vy = abs(vy) * 0.3 }
        if y > maxY { y = maxY; vy = -abs(vy) * 0.3 }
        f.velocity = CGVector(dx: vx, dy: vy)
        f.position = CGPoint(x: world.wrap(lease.home.x + nextOffset), y: y)
        // Slow swimming remains broadside; only an actual turn briefly narrows the fish.
        let direction: CGFloat = abs(vx) > 2 ? (vx >= 0 ? 1 : -1) : f.heading
        f.facing += (direction - f.facing) * min(1, dt * T.encounterFacingRate)
    }

    // MARK: - Kelp Forest

    private func spawnKelp() {
        silhouetted.removeAll()
        silhouetteColors.removeAll()
        for bed in kelpBeds { bed.back.removeFromParent(); bed.front.removeFromParent() }
        kelpBeds = (level.meetingPlan?.kelp ?? []).enumerated().map { index, bed in
            // A column is drawn to just above the top of the screen; a bed to its top at full size.
            let height = (bed.reachesSurface ? size.height + T.kelpCanopy : bed.top) - T.kelpRootY
            let back = KelpNode(width: bed.halfWidth * 2, height: height, seed: UInt64(index), front: false)
            let front = KelpNode(width: bed.halfWidth * 2, height: height, seed: UInt64(index) &+ 101, front: true)
            // Back fronds behind every fish; front fronds in front of the others, so those inside show
            // through as silhouettes, but behind you.
            back.zPosition = 0.5
            front.zPosition = 29
            fishLayer.addChild(back)
            fishLayer.addChild(front)
            return (bed, back, front, height)
        }
    }

    /// In kelp, a fish is one solid dark shape, eye and all, so you judge it by its outline alone.
    private func setSilhouette(_ node: SKNode, _ on: Bool) {
        for child in node.children {
            if let shape = child as? SKShapeNode {
                let key = ObjectIdentifier(shape)
                if on {
                    silhouetteColors[key] = (shape.fillColor, shape.strokeColor)
                    if shape.fillColor.cgColor.alpha > 0 { shape.fillColor = T.kelpSilhouette }
                    if shape.strokeColor.cgColor.alpha > 0 { shape.strokeColor = T.kelpSilhouette }
                } else if let original = silhouetteColors.removeValue(forKey: key) {
                    shape.fillColor = original.fill
                    shape.strokeColor = original.stroke
                }
            }
            setSilhouette(child, on)
        }
    }

    private func inKelp(_ position: CGPoint) -> Bool {
        kelpBeds.contains { abs(world.delta(from: $0.bed.x, to: position.x)) <= $0.bed.halfWidth && position.y < $0.bed.top }
    }

    /// Beds grow from below the bottom of the screen up to their top, wherever the camera has it.
    private func renderKelp(cameraX: CGFloat, zoom: CGFloat, time: CGFloat) {
        for (bed, back, front, height) in kelpBeds {
            let x = size.width * T.playerScreenX + world.delta(from: cameraX, to: bed.x) * zoom
            let half = bed.halfWidth * zoom + 40
            let hidden = x + half < 0 || x - half > size.width
            back.isHidden = hidden
            front.isHidden = hidden
            if hidden { continue }
            let top = bed.reachesSurface ? size.height + T.kelpCanopy : waterCenter + (bed.top - waterCenter) * zoom
            for node in [back, front] {
                node.position = CGPoint(x: x, y: T.kelpRootY)
                node.xScale = zoom
                node.yScale = max(0.05, (top - T.kelpRootY) / max(1, height))
                node.sway(time: time)
            }
        }
    }

    // MARK: - Jelly Bloom (arcade-only; no shared engine changes)

    private func spawnJellies() {
        guard let layout = level.jellies else { return }
        if let planned = level.meetingPlan?.jellies {
            // Planned jellies drift exactly where the planner put them, in its order.
            for jelly in planned {
                let node = JellyfishNode(radius: layout.radius, tentacleLength: layout.tentacleLength, phase: jelly.phase,
                                         night: layout.night)
                hazardLayer.addChild(node)
                let start = JellyDrift.position(origin: jelly.origin, phase: jelly.phase, time: 0, screenWidth: size.width, world: world)
                jellies.append(BloomJelly(node: node, origin: jelly.origin, position: start, phase: jelly.phase))
            }
            return
        }
        var scattered = unevenJellies ? JellyPlacement.origins(layout: layout, screenWidth: size.width,
            waterBottom: waterBottom, waterTop: waterTop, seed: jellyLayoutSeed, variation: layoutVariation) : []
        if level.encounterDifficulty != nil {
            var generator = SeededGenerator(seed: jellyLayoutSeed)
            let preserve = level.freeEncounterMovement && levelIndex == 1
            let heights = preserve ? T.freeEncounterHeights : T.freeEncounterHeights.shuffled(using: &generator)
            scattered = (0..<layout.count).map { i in
                let horizontal = level.freeEncounterMovement && !preserve ? T.freeEncounterHorizontalVariation : T.encounterJitterScreens
                let jitter = unevenJellies ? CGFloat.random(in: -horizontal...horizontal, using: &generator) * layoutVariation : 0
                let variation = preserve ? CGFloat(0.035) : T.freeEncounterHeightVariation
                let height = level.freeEncounterMovement
                    ? heights[i] + CGFloat.random(in: -variation...variation, using: &generator) * layoutVariation
                    : CGFloat.random(in: T.encounterBellHeight, using: &generator)
                return CGPoint(x: size.width * (T.encounterFirstScreens + CGFloat(i) * T.encounterSpacingScreens + jitter),
                    y: max(waterBottom + layout.tentacleLength + GameRules.bloomFloorLaneClearance(fishRadius: T.baseRadius),
                        waterBottom + (waterTop - waterBottom) * height))
            }
        }
        for i in 0..<layout.count {
            // A safe opening, then alternating bell heights create a route through the field.
            let x = size.width * 0.85 + CGFloat(i) * (world.width - size.width) / CGFloat(layout.count)
            let heights = layout.heights.isEmpty ? T.bloomAuthoredJellyHeights : layout.heights
            let fraction = heights[i % heights.count]
            let floorGap = (layout.maintainsFloorLane || levelIndex == 0) ? GameRules.bloomFloorLaneClearance(fishRadius: T.baseRadius) : T.bloomJellyFallbackFloorGap
            let y = max(waterBottom + layout.tentacleLength + floorGap,
                        waterBottom + (waterTop - waterBottom) * fraction)
            let origin = scattered.isEmpty ? CGPoint(x: world.wrap(x), y: y) : scattered[i]
            let phase = CGFloat(i) * 1.7
            let node = JellyfishNode(radius: layout.radius, tentacleLength: layout.tentacleLength, phase: phase,
                                     night: layout.night)
            hazardLayer.addChild(node)
            // A drifting bell starts where its drift has it at the first step, so it never jumps.
            let start = layout.drifts ? JellyDrift.position(origin: origin, phase: phase, time: 0,
                                                            screenWidth: size.width, world: world) : origin
            jellies.append(BloomJelly(node: node, origin: origin, position: start, phase: phase))
        }
        for i in 0..<layout.urchinBeds {
            let center = size.width * 1.1 + CGFloat(i) * (world.width - size.width * 1.4) / CGFloat(max(1, layout.urchinBeds - 1))
            for offset in -2...2 {
                let node = ArcadeArt.urchin(radius: T.urchinRadius)
                hazardLayer.addChild(node)
                urchins.append((x: world.wrap(center + CGFloat(offset) * T.urchinRadius * 1.6), node: node))
            }
        }
    }

    private func updateUrchins(previousFish: [Int: CGPoint]) {
        for urchin in urchins {
            let center = CGPoint(x: urchin.x, y: waterBottom + T.urchinRadius * 0.55)
            for f in fish.filter({ $0.isAlive }) {
                #if DEBUG
                if simulationEcologyProbe && f.isPlayer { continue }
                #endif
                let p = CGPoint(x: world.delta(from: center.x, to: f.position.x), y: f.position.y - center.y)
                let old = previousFish[f.id] ?? f.position
                let previous = CGPoint(x: p.x - world.delta(from: old.x, to: f.position.x),
                                       y: old.y - center.y)
                let delta = CGVector(dx: p.x - previous.x, dy: p.y - previous.y)
                let length = delta.dx * delta.dx + delta.dy * delta.dy
                let t = length > 0 ? (-(previous.x * delta.dx + previous.y * delta.dy) / length).clamped(0, 1) : 0
                let closest = CGPoint(x: previous.x + delta.dx * t, y: previous.y + delta.dy * t)
                if hypot(closest.x, closest.y) < (T.urchinRadius + f.radius) * T.hazardHitboxScale {
                    removeByTentacles(f, reason: "Caught on the urchins.")
                    if f.isPlayer { return }
                }
            }
        }
    }

    private func updateJellies(_ dt: CGFloat, previousFish: [Int: CGPoint]) {
        guard let layout = level.jellies else { return }
        for i in jellies.indices {
            let previousJelly = jellies[i].position
            jellies[i].position = layout.drifts
                ? JellyDrift.position(origin: jellies[i].origin, phase: jellies[i].phase, time: simClock,
                                      screenWidth: size.width, world: world)
                : CGPoint(x: world.wrap(jellies[i].origin.x + sin(simClock * 0.45 + jellies[i].phase) * layout.sway),
                          y: jellies[i].origin.y + sin(simClock * 0.65 + jellies[i].phase) * layout.sway)
            if (layout.maintainsFloorLane || levelIndex == 0) && level.meetingPlan == nil {
                // Preserve a lower passage as the fish grows and the camera eases outward.
                jellies[i].position.y = max(jellies[i].position.y,
                    waterBottom + layout.tentacleLength + GameRules.bloomFloorLaneClearance(fishRadius: player.radius))
            }
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
                        layout: layout, speed: bounceSpeed / zoom, dt: dt, ceiling: ceiling)
                    jelly.node.bounce()
                    #if DEBUG
                    debugBounces.append((f.id, i, simClock, size.width * T.playerScreenX
                        + world.delta(from: player.position.x, to: f.position.x) * zoom))
                    if simulationTuning != nil && f.isPlayer { simulationStats.bounces += 1 }
                    recordRunEvent("bounce", fields: ["fishID": f.id, "jellyID": i, "remainingFrame": remaining,
                                                     "x": f.position.x, "y": f.position.y, "vy": f.velocity.dy])
                    #endif
                    if f.isPlayer {
                        metricAccumulator?.bounce()
                        bounceRemaining = T.jellyBounceSeconds
                        bounceCooldown = T.jellyBounceCooldown
                        f.pulse = T.pulseDuration
                        closeCallHaptic.impactOccurred(intensity: 0.55)
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

    private func removeByTentacles(_ victim: Fish, reason: String = "Caught in the tentacles.") {
        if victim.isPlayer && metricAccumulator != nil {
            observeMetrics()
            metricDeathCause = reason == "Caught in the tentacles." ? "tentacles" : "urchin"
            fatalMetrics = metricAccumulator?.summary
        }
        #if DEBUG
        if simulationTuning != nil && !victim.isPlayer { simulationStats.aiHazardDeaths += 1 }
        recordRunEvent("hazard_death", fields: ["fishID": victim.id, "reason": reason,
                                               "x": victim.position.x, "y": victim.position.y, "radius": victim.radius])
        #endif
        // If a predator hits a curtain mid-swallow, its prey escapes rather than getting stuck.
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
            eatenNotification.notificationOccurred(.error)
            playSound(.sting)
            lose(resultDelay: T.stingResultDelay)
        } else {
            fish.removeAll { $0.id == victim.id }
            fishByID[victim.id] = nil
            aiMovementRNGs[victim.id] = nil
            encounterLeases[victim.id] = nil
            foodHomes[victim.id] = nil
            sidePocketHomes[victim.id] = nil
            nodes[victim.id] = nil
        }
    }

    private func renderJellies(cameraX: CGFloat, zoom: CGFloat, fraction: CGFloat, time: CGFloat) {
        for urchin in urchins {
            let x = size.width * T.playerScreenX + world.delta(from: cameraX, to: urchin.x) * zoom
            urchin.node.isHidden = x < -30 || x > size.width + 30
            urchin.node.position = CGPoint(x: x, y: screenWaterBottom + T.urchinRadius * 0.55 * zoom)
            urchin.node.setScale(zoom)
        }
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

    /// Bloom swimmers avoid tentacles while food fish stay near their bounce pockets.
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

                #if DEBUG
                if a.isPlayer && !simulationCanEat(b) && GameRules.playerEncounter(a.radius, b.radius) == .firstEatsSecond { continue }
                if b.isPlayer && !simulationCanEat(a) && GameRules.playerEncounter(b.radius, a.radius) == .firstEatsSecond { continue }
                #endif
                switch GameRules.encounter(a.radius, b.radius, firstIsPlayer: a.isPlayer, secondIsPlayer: b.isPlayer) {
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
        if prey.isPlayer && metricAccumulator != nil {
            observeMetrics()
            metricDeathCause = "predator"
            metricAccumulator?.fatal(ratio: Double(predator.radius / prey.radius))
            fatalMetrics = metricAccumulator?.summary
            finishMetrics("death") // The fatal interaction is committed; do not reclassify its animation as a quit.
        }
        #if DEBUG
        if simulationTuning != nil && predator.isPlayer {
            simulationStats.mealStartLaps.append(Double(simulationLaps))
            simulationStats.mealStartFishIDs.append(prey.id)
        }
        #endif
        #if DEBUG
        recordRunEvent("swallow_start", fields: ["predatorID": predator.id, "preyID": prey.id,
                                                "predatorRadius": predator.radius, "preyRadius": prey.radius])
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
        if prey.isPlayer {
            eatenHaptic.impactOccurred(intensity: 1)
            eatenNotification.notificationOccurred(.error)
        }
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

        prey.state = .removed
        nodes[prey.id]?.removeFromParent()
        nodes[prey.id] = nil
        fish.removeAll { $0.id == prey.id }
        fishByID[prey.id] = nil
        aiMovementRNGs[prey.id] = nil
        encounterLeases[prey.id] = nil
        foodHomes[prey.id] = nil
        sidePocketHomes[prey.id] = nil

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
        if simulationTuning != nil {
            if predator.isPlayer {
                simulationStats.playerMeals += 1
                simulationStats.mealLaps.append(Double(simulationLaps))
                simulationStats.mealRatios.append(Double(s.ratio))
                simulationStats.mealFishIDs.append(prey.id)
                if s.ratio >= T.closeCallRatio { simulationStats.closeMeals += 1 }
                if fish.contains(where: { !$0.isPlayer && $0.id != prey.id && $0.state == .swimming &&
                    GameRules.playerEncounter(predator.radius, $0.radius) == .secondEatsFirst &&
                    world.distance(predator.position, $0.position) - predator.radius - $0.radius < size.width * 0.20 / zoom }) {
                    simulationStats.contestedMeals += 1
                }
            } else if !prey.isPlayer { simulationStats.aiMeals += 1 }
        }
        recordRunEvent("eat", fields: ["predatorID": predator.id, "preyID": prey.id,
                                      "preyRadius": prey.radius, "radiusAfter": predator.targetRadius])
        #endif

        if !prey.isPlayer { metricAccumulator?.meal(player: predator.isPlayer, ratio: Double(s.ratio)) }
        observeMetrics()
        if predator.isPlayer {
            mealsEaten += 1
            updateMealIndicator()
            playSound(.eat)
        }
        if predator.isPlayer && s.ratio >= T.closeCallRatio {
            closeCallHaptic.impactOccurred()
        }
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
        for f in fish {
            guard let node = nodes[f.id], !stungFish.contains(where: { $0.id == f.id }) else { continue }
            let pose = presentationPose(f, fraction: fraction)
            let screenX = anchorX + world.delta(from: cameraX, to: pose.position.x) * zoom
            let margin = pose.radius * zoom * 3
            node.isHidden = screenX < -margin || screenX > size.width + margin
            if node.isHidden { continue }
            node.position = CGPoint(x: screenX, y: waterCenter + (pose.position.y - waterCenter) * zoom)
            if !kelpBeds.isEmpty && !f.isPlayer && T.kelpFishLook == .silhouette {
                let hidden = inKelp(pose.position)
                if hidden != silhouetted.contains(f.id) {
                    if hidden { silhouetted.insert(f.id) } else { silhouetted.remove(f.id) }
                    setSilhouette(node, hidden)
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
                : pose.velocity.dy / level.aiVerticalSpeed * T.aiMaxTilt
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

        let gradient = SKSpriteNode(texture: arcadeWorld.hasJellies
                                    ? ArcadeArt.bloomWater(night: level.jellies?.night == true)
                                    : arcadeWorld == .kelpForest ? ArcadeArt.kelpWater() : WaterTextures.gradient())
        gradient.anchorPoint = .zero
        gradient.size = size
        backgroundLayer.addChild(gradient)

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
        // "Shallow Reef 2 3" would read as one number; spell out its level.
        let heading = "\(arcadeWorld.title) \(levelIndex + 1)"
        let text = label(plannerName ?? heading, fontSize: 13, heavy: true)
        text.horizontalAlignmentMode = .left
        text.alpha = 0.9
        levelIndicator.addChild(text)
        // Retained for a later endless-mode HUD; campaign uses last-fish-alive wins.
        if level.requiredMeals > 0 {
            mealIndicator.fontSize = 13
            mealIndicator.fontColor = .white
            mealIndicator.horizontalAlignmentMode = .left
            mealIndicator.position = CGPoint(x: 0, y: -23)
            levelIndicator.addChild(mealIndicator)
            updateMealIndicator()
        }
        levelIndicator.position = CGPoint(x: 64, y: size.height - 36)
    }

    private func updateMealIndicator() {
        guard level.requiredMeals > 0 else { return }
        let text = "EAT \(min(mealsEaten, level.requiredMeals))/\(level.requiredMeals)" +
            (mealsEaten >= level.requiredMeals ? " · CLEAR THE REEF" : "")
        if mealIndicator.text != text { mealIndicator.text = text }
    }

    private func buildPauseButton() {
        pauseButton.removeAllChildren()
        let circle = SKShapeNode(circleOfRadius: 20)
        circle.fillColor = SKColor(white: 0, alpha: 0.25)
        circle.strokeColor = SKColor(white: 1, alpha: 0.5)
        circle.lineWidth = 1.5
        pauseButton.addChild(circle)
        for x in [-5.0, 5.0] {
            let bar = SKShapeNode(rect: CGRect(x: x - 2.5, y: -8, width: 5, height: 16), cornerRadius: 1.5)
            bar.fillColor = SKColor(white: 1, alpha: 0.85)
            bar.strokeColor = .clear
            pauseButton.addChild(bar)
        }
        pauseButton.position = CGPoint(x: size.width - 64, y: size.height - 36)
    }

    private func buildPauseMenu() {
        pauseMenu.removeAllChildren()
        let shade = SKSpriteNode(color: SKColor(white: 0, alpha: 0.4), size: size)
        shade.anchorPoint = .zero
        pauseMenu.addChild(shade)

        let title = label("Paused", fontSize: 36, heavy: true)
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 90)
        pauseMenu.addChild(title)

        resumeButton = menuButton("Resume", at: CGPoint(x: size.width / 2, y: size.height / 2 + 5))
        restartButton = menuButton("Restart", at: CGPoint(x: size.width / 2, y: size.height / 2 - 60))
        pauseMenu.addChild(resumeButton)
        pauseMenu.addChild(restartButton)
        addMapButton(to: pauseMenu, y: size.height / 2 - 120, x: size.width / 2)
        buildSoundToggles()
    }

    /// Sound effects and music switches beside the pause menu's actions.
    private func buildSoundToggles() {
        effectsButton.removeFromParent()
        musicButton.removeFromParent()
        let x = size.width / 2 + 230
        effectsButton = toggleButton("Effects", isOn: settings.soundEffectsOn, at: CGPoint(x: x, y: size.height / 2 + 5))
        musicButton = toggleButton("Music", isOn: settings.musicOn, at: CGPoint(x: x, y: size.height / 2 - 60))
        pauseMenu.addChild(effectsButton)
        pauseMenu.addChild(musicButton)
    }

    private func toggleSound(effects: Bool) {
        if effects { settings.soundEffectsOn.toggle() } else { settings.musicOn.toggle() }
        buildSoundToggles()
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
            element(restartButton, "Restart") { $0.resetGame(startPlaying: false) },
            element(mapButton, "Level map") { scene in
                #if DEBUG
                scene.finishRunRecording("level_map")
                #endif
                scene.onExit?()
            },
            element(effectsButton, "Sound effects", value: settings.soundEffectsOn ? "On" : "Off") { $0.toggleSound(effects: true) },
            element(musicButton, "Music", value: settings.musicOn ? "On" : "Off") { $0.toggleSound(effects: false) },
        ]
    }

    private func toggleButton(_ title: String, isOn: Bool, at position: CGPoint) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: 150, height: 44), cornerRadius: 22)
        button.fillColor = isOn ? SKColor(white: 1, alpha: 0.92) : SKColor(white: 1, alpha: 0.08)
        button.strokeColor = isOn ? .clear : SKColor(white: 1, alpha: 0.6)
        button.lineWidth = 2
        button.position = position
        let text = label("\(title): \(isOn ? "On" : "Off")", fontSize: 18, heavy: true)
        text.fontColor = isOn ? SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1) : .white
        button.addChild(text)
        return button
    }

    private func addMapButton(to parent: SKNode, y: CGFloat, x: CGFloat = 0) {
        mapButton.removeFromParent()
        mapButton = menuButton("Level map", at: CGPoint(x: x, y: y))
        mapButton.setScale(0.8)
        parent.addChild(mapButton)
    }

    private func menuButton(_ text: String, at position: CGPoint) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: 170, height: 48), cornerRadius: 24)
        button.fillColor = SKColor(white: 1, alpha: 0.92)
        button.strokeColor = .clear
        button.position = position
        let text = label(text, fontSize: 20, heavy: true)
        text.fontColor = SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1)
        button.addChild(text)
        return button
    }

    private func showMessage(_ title: String, lines: [String], delay: TimeInterval = 0) {
        messageNode.removeAllActions()
        messageNode.removeAllChildren()

        let titleLabel = label(title, fontSize: 40, heavy: true)
        let lineLabels = lines.map { label($0, fontSize: 19, heavy: false) }
        let start = label("Tap anywhere to begin", fontSize: 22, heavy: true)
        start.name = "beginPrompt"
        let maxTextWidth = max(240, (size.width - messageNode.position.x - 28) * 2 - 70)
        for text in [titleLabel, start] + lineLabels where text.frame.width > maxTextWidth {
            text.fontSize *= maxTextWidth / text.frame.width
        }
        let lineSpacing: CGFloat = 30
        let height = 150 + CGFloat(lines.count) * lineSpacing
        let width = max(titleLabel.frame.width, start.frame.width, lineLabels.map(\.frame.width).max() ?? 0) + 70

        let panel = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        panel.fillColor = SKColor(white: 0, alpha: 0.3)
        panel.strokeColor = .clear
        panel.name = "readyCard"
        messageNode.addChild(panel)

        var y = height / 2 - 45
        titleLabel.position = CGPoint(x: 0, y: y)
        messageNode.addChild(titleLabel)
        y -= 45
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
    // JSONL uses world coordinates; screen projection is defined by the snapshot's camera.
    private func recordRunEvent(_ name: String, fields: [String: Any] = [:]) {
        runRecorder?.event(name, time: Double(realClock - recordingStartedAt), simulationTime: Double(simClock), fields: fields)
        if ["bounce", "swallow_start", "hazard_death"].contains(name) { recordRunSnapshot(force: true) }
    }

    private func startRunRecording() {
        recordingStartedAt = realClock
        runRecorder = ArcadeRunRecorder.makeDefault()
        recordRunEvent("start", fields: ["schema": 1, "world": arcadeWorld.rawValue, "level": levelIndex + 1,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "configuration": ["spawnSeed": String(ecosystemSeed),
                "aiMovementRandomVersion": 1,
                "protectedContactVersion": 1,
                "simulationStepSeconds": T.simulationStep, "maximumFrameElapsedSeconds": T.maximumFrameElapsed,
                "encounterFormationVersion": level.freeEncounterMovement ? (arcadeWorld == .jellyBloom && levelIndex == 1 ? 2 : 3) : (level.encounterDifficulty != nil && levelIndex < 5 ? 1 : 0),
                "encounterDifficulty": level.encounterDifficulty?.bounded ?? -1,
                "encounterForwardDistance": forwardDistance,
                "openingCatchBudget": level.freeEncounterMovement ? -1 : (level.encounterDifficulty?.catchBudget ?? -1),
                "expectedEdibleCatchFraction": level.freeEncounterMovement ? Double(T.freeEncounterExpectedCatchFraction(level.encounterDifficulty?.bounded ?? 0, shallow: arcadeWorld == .shallowReef)) : -1,
                "startingWaveBudgets": level.freeEncounterMovement ? T.freeEncounterWaveBudgets(seed: ecosystemSeed, difficulty: level.encounterDifficulty?.bounded ?? 0, preserveLevelTwo: arcadeWorld == .jellyBloom && levelIndex == 1, shallow: arcadeWorld == .shallowReef).map { ["count": $0.count, "edible": $0.edible] } : [],
                "extraRecoveryPasses": level.freeEncounterMovement ? 0 : (level.encounterDifficulty?.recoveryPasses ?? -1),
                "aiSurvivesTentacles": true,
                "aiCanEat": level.aiCanEat, "playerWinsTies": true, "absorptionEfficiency": level.effectiveAbsorptionEfficiency,
                "mealGrowthScale": T.mealGrowthScale,
                "roamingFoodChain": level.roamingFoodChain,
                "foodPocketReleaseSeconds": level.roamingFoodChain ? pocketReleaseSeconds : 0,
                "jellyLayoutSeed": String(jellyLayoutSeed),
                "freeEncounterMovement": level.freeEncounterMovement,
                "unevenJellies": unevenJellies, "layoutVariation": layoutVariation,
                "debugTuningOverride": activeDebugTuning != nil, "practiceRun": debugPracticeRun,
                "configuredFishCount": level.spawnGroups.reduce(0) { $0 + $1.count },
                "jellyCount": level.jellies?.count ?? 0,
                "screenCrossSeconds": level.screenCrossSeconds, "sidePocketExperiment": level.sidePocketExperiment,
                "bounceSpeed": bounceSpeed, "jellyRadius": level.jellies?.radius ?? 0,
                "tentacleLength": level.jellies?.tentacleLength ?? 0,
                "jellySway": level.jellies?.sway ?? 0, "jellyHeights": level.jellies?.heights ?? [],
                "aiSpeedScale": aiSpeedScale, "aiSpeedMin": level.aiSpeedRange.lowerBound * aiSpeedScale, "aiSpeedMax": level.aiSpeedRange.upperBound * aiSpeedScale,
                "aiVerticalSpeed": level.aiVerticalSpeed, "foodPocketLift": T.bloomFoodPocketLift,
                "foodPatrolScreens": T.bloomFoodPatrolScreens,
                "sidePocketOffset": T.bloomSidePocketOffset, "sidePocketDrop": T.bloomSidePocketDrop,
                "spawnGroups": level.spawnGroups.map { ["count": $0.count, "min": $0.radii.lowerBound, "max": $0.radii.upperBound] },
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
        return ["name": plan.spec.name, "variation": plan.variation, "issues": plan.issues, "fish": fish]
    }

    private func recordRunSnapshot(force: Bool = false) {
        guard let runRecorder, force || runRecorder.wantsSnapshot(time: Double(realClock - recordingStartedAt)) else { return }
        let fishStates: [[String: Any]] = fish.map { f in
            ["id": f.id, "player": f.isPlayer, "state": String(describing: f.state),
             "x": f.position.x, "y": f.position.y, "vx": f.velocity.dx, "vy": f.velocity.dy,
             "radius": f.radius, "targetRadius": f.targetRadius]
        }
        let jellyStates: [[String: Any]] = jellies.enumerated().map { ["id": $0.offset, "x": $0.element.position.x, "y": $0.element.position.y] }
        runRecorder.snapshot(time: Double(realClock - recordingStartedAt), simulationTime: Double(simClock), fields: [
            "phase": String(describing: phase), "holding": isHolding, "zoom": zoom, "timeScale": timeScale,
            "worldWidth": world.width, "screenWidth": size.width, "screenHeight": size.height,
            "cameraX": player.position.x, "forwardDistance": forwardDistance, "playerScreenX": T.playerScreenX, "waterCenter": waterCenter,
            "waterBottom": waterBottom, "waterTop": waterTop, "fish": fishStates, "jellies": jellyStates], force: force)
    }

    private func finishRunRecording(_ outcome: String, fields: [String: Any] = [:]) {
        guard let runRecorder else { return }
        recordRunSnapshot(force: true)
        var summary = fields
        summary["playerMeals"] = mealsEaten
        summary["playerRadius"] = player?.radius ?? 0
        summary["fishRemaining"] = fish.filter { !$0.isPlayer && $0.state != .removed }.count
        runRecorder.finish(outcome: outcome, time: Double(realClock - recordingStartedAt), simulationTime: Double(simClock), fields: summary)
        self.runRecorder = nil
    }

    /// Advances the real scene without presentation, audio, recording, or touches.
    func debugSimulate(candidate: String, tuning: ArcadeTuning, policy: ArcadeSimulation.Policy,
                       seed: Int, limit: CGFloat = 75, delayedPasses: CGFloat = 0, ecologyProbe: Bool = false, firstPassMealLimit: Int? = nil, skippedFirstPassFishIDs: [Int] = [], decisionInterval: CGFloat? = nil, predictionSeconds: CGFloat = 0.6, foodPriority: CGFloat? = nil, dangerWeight: CGFloat? = nil) -> ArcadeSimulation.Result {
        simulationEcologyProbe = ecologyProbe
        simulationStats = ArcadeSimulation.Stats()
        simulationLaps = 0
        simulationDelayedPasses = delayedPasses
        simulationFirstPassMealLimit = firstPassMealLimit
        simulationSkippedFishIDs = Set(skippedFirstPassFishIDs)
        simulationTuning = tuning.sanitized
        simulationTuning!.seedOffset = min(999, max(0, tuning.seedOffset + seed))
        simulationHolding = false
        resetGame(startPlaying: true)
        let spawned = fish.count - 1
        let initiallyViable = ArcadeSimulation.hasGrowthPath(player: player.radius,
            radii: fish.filter { !$0.isPlayer }.map(\.radius), efficiency: level.effectiveAbsorptionEfficiency)
        var nextDecision: CGFloat = 0, nextSample: CGFloat = 0
        var previouslyViable = initiallyViable
        while phase == .playing && simClock < limit {
            if !ecologyProbe && simClock >= nextDecision {
                let visible = fish.filter { !$0.isPlayer && $0.state == .swimming &&
                    abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width * 0.80 / zoom }
                func swimmer(_ f: Fish) -> ArcadeSimulation.Swimmer {
                    .init(canEat: simulationCanEat(f), x: f.position.x, y: f.position.y, vx: f.velocity.dx, vy: f.velocity.dy, radius: f.radius)
                }
                let bells = jellies.filter { abs(world.delta(from: player.position.x, to: $0.position.x)) < size.width / zoom }
                    .map { ArcadeSimulation.Bell(x: $0.position.x, y: $0.position.y,
                        radius: level.jellies!.radius, tentacles: level.jellies!.tentacleLength) }
                simulationHolding = ArcadeSimulation.holding(.init(player: swimmer(player), fish: visible.map(swimmer),
                    bells: bells, width: world.width, screenWidth: size.width, zoom: zoom,
                    bottom: waterBottom, top: waterTop, speed: playerSpeed, bouncing: bounceRemaining > 0,
                    bounceSpeed: bounceSpeed), policy: policy, feeding: simulationMayFeed && !ecologyProbe, predictionSeconds: predictionSeconds, foodPriority: foodPriority, dangerWeight: dangerWeight)
                nextDecision = simClock + max(T.simulationStep, decisionInterval ?? (policy == .collector ? 0.16 : (policy == .cautious ? 0.10 : 0.08)))
            }
            let oldX = player.position.x
            advanceFrame(T.simulationStep)
            simulationLaps += max(0, world.delta(from: oldX, to: player.position.x)) / world.width
            if simClock >= nextSample && phase == .playing {
                let others = fish.filter { !$0.isPlayer && $0.state == .swimming }
                let threats = others.filter { GameRules.playerEncounter(player.radius, $0.radius) == .secondEatsFirst }
                if !threats.isEmpty {
                    simulationStats.threatSeconds += 0.2
                    simulationStats.lastThreat = Double(simClock)
                    let gap = threats.map { world.distance(player.position, $0.position) - player.radius - $0.radius }.min()!
                    simulationStats.minimumThreatClearance = min(simulationStats.minimumThreatClearance, Double(gap))
                    if gap < size.width * 0.15 / zoom { simulationStats.nearbyThreatSeconds += 0.2 }
                }
                if fish.allSatisfy({ $0.state == .swimming }) && !others.isEmpty {
                    let viable = ArcadeSimulation.hasGrowthPath(player: max(player.radius, player.targetRadius),
                        radii: others.map { max($0.radius, $0.targetRadius) }, efficiency: level.effectiveAbsorptionEfficiency)
                    if !viable {
                        simulationStats.stalledSeconds += 0.2
                        if simulationStats.firstStallLap == nil { simulationStats.firstStallLap = Double(simulationLaps) }
                        if previouslyViable { simulationStats.lastStallLap = Double(simulationLaps) }
                    } else if !previouslyViable { simulationStats.recoveredPaths += 1 }
                    previouslyViable = viable
                }
                nextSample = simClock + 0.2
            }
        }
        return .init(candidate: candidate, level: levelIndex + 1, policy: policy, decisionIntervalSeconds: decisionInterval.map(Double.init), predictionSeconds: Double(predictionSeconds), foodPriority: foodPriority.map(Double.init), dangerWeight: dangerWeight.map(Double.init), seed: simulationTuning!.seedOffset, width: Double(size.width), skippedFirstPassFishIDs: skippedFirstPassFishIDs, firstPassMealLimit: firstPassMealLimit, delayedPasses: Double(delayedPasses), ecologyProbe: ecologyProbe,
            laps: Double(simulationLaps), outcome: phase == .won ? "won" : (phase == .lost ? "lost" : "timeout"),
            reason: phase == .lost ? lossReason : "", seconds: Double(simClock),
            remaining: fish.filter { !$0.isPlayer }.count, playerRadius: Double(player.radius),
            spawned: spawned, configured: level.spawnGroups.reduce(0) { $0 + $1.count }, initialGrowthPath: initiallyViable,
            stats: simulationStats, tuning: simulationTuning!)
    }

    /// Compare AI without player contacts. Isolated mode disables every collision,
    /// hazard, and camera update, so skipping another swimmer has no physical effect.
    func debugAuditRepeatability(frames: [CGFloat], isolatedAI: Bool = true,
                                 omittedIDs: Set<Int> = [], fixedZoom: CGFloat = 1,
                                 playerRadius: CGFloat = T.baseRadius, fixedStep: Bool = false,
                                 slowMotion: Bool = false, scriptedInput: Bool = false,
                                 removeOmittedFish: Bool = false) -> ArcadeSimulation.Audit {
        simulationTuning = ArcadeTuning(level: worldLevel)
        simulationEcologyProbe = true
        simulationHolding = false
        resetGame(startPlaying: true)
        zoom = fixedZoom
        player.radius = playerRadius
        player.targetRadius = playerRadius
        if removeOmittedFish {
            for id in omittedIDs {
                fish.removeAll { $0.id == id }
                fishByID[id] = nil
                nodes[id]?.removeFromParent()
                nodes[id] = nil
                aiMovementRNGs[id] = nil
                foodHomes[id] = nil
                sidePocketHomes[id] = nil
            }
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
        simulationTuning = ArcadeTuning(level: worldLevel)
        simulationEcologyProbe = true
        simulationHolding = false
        resetGame(startPlaying: true)
        advanceFrame(T.simulationStep)
        let position = player.position
        let radius = player.radius
        let clock = simClock
        var controlRNG = rng
        let randomControl = controlRNG.next()
        _ = render()
        let firstY = nodes[player.id]!.position.y
        frameAccumulator = T.simulationStep / 2
        _ = render()
        let secondY = nodes[player.id]!.position.y
        var afterRenderRNG = rng
        guard abs(firstY - secondY) > 1e-6, player.position == position,
              player.radius == radius, simClock == clock, afterRenderRNG.next() == randomControl else { return false }
        setPhase(.paused)
        _ = render()
        let pausedY = waterCenter + (position.y - waterCenter) * zoom
        guard abs(nodes[player.id]!.position.y - pausedY) < 1e-4 else { return false }
        resetGame(startPlaying: true)
        _ = render()
        return previousPresentation.count == fish.count && abs(nodes[player.id]!.position.y - player.position.y) < 1e-4
    }

    func debugCheckFixedTimingLifecycle() -> Bool {
        simulationTuning = ArcadeTuning(level: worldLevel)
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
    /// Every bell landing this run: who, on which jelly, when, and where on screen.
    private(set) var debugBounces: [(fishID: Int, jelly: Int, time: CGFloat, screenX: CGFloat)] = []
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
    var debugConfiguredSpawnSeed: UInt64 { ecosystemSeed }
    var debugResultTitles: [String] { resultPanel?.controls.map { $0.action.title } ?? [] }
    func debugTapResult(_ action: ArcadeResultAction?) {
        guard let panel = resultPanel else { return }
        let frame = panel.controls.first { $0.action == action }?.frame
        panel.handleTap(at: frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 0, y: 80))
    }
    var debugPredatorStartGaps: [CGFloat] {
        let predators = fish.filter { !$0.isPlayer && $0.radius >= T.baseRadius }
        return predators.indices.flatMap { a in
            predators.indices.filter { $0 > a }.map { b in
                abs(world.delta(from: predators[a].position.x, to: predators[b].position.x)) / size.width
            }
        }
    }
    func debugFloorLane(radius: CGFloat) -> CGFloat {
        player.radius = radius
        player.targetRadius = radius
        updateJellies(0, previousFish: [:])
        return jellies.map { $0.position.y - level.jellies!.tentacleLength - waterBottom }.min() ?? 0
    }
    func debugApproachJelly() -> Bool {
        guard let jelly = jellies.first else { return false }
        for f in fish.filter({ !$0.isPlayer }) { removeByTentacles(f) }
        jellies = [jelly]
        urchins.removeAll()
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
        let predator = fish.first { !$0.isPlayer && foodHomes[$0.id] == nil }!
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
    func debugAICompetition() -> (respectedGrace: Bool, becameThreat: Bool) {
        for f in fish.filter({ !$0.isPlayer }) { removeByTentacles(f) }
        let position = CGPoint(x: world.width / 2, y: waterCenter)
        let predator = Fish(id: nextFishID, isPlayer: false, position: position, radius: T.baseRadius * 0.9)
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
    var debugSidePocketPlacement: (food: [CGPoint], predators: [CGPoint], safe: Bool) {
        guard level.sidePocketExperiment, let layout = level.jellies else { return ([], [], true) }
        let jelly = jellies[T.bloomSidePocketJellyIndex]
        var food: [CGPoint] = [], predators: [CGPoint] = []
        var safe = true
        for (id, position) in sidePocketHomes {
            let relative = CGPoint(x: world.delta(from: jelly.position.x, to: position.x),
                                   y: position.y - jelly.position.y)
            if foodHomes[id] != nil { food.append(relative) } else { predators.append(relative) }
            if let f = fishByID[id] {
                safe = safe && JellyRules.contact(at: relative, previous: relative, fishRadius: f.radius,
                                                  domeRadius: layout.radius, tentacleLength: layout.tentacleLength) == .none
            }
        }
        return (food, predators, safe)
    }
    func debugUseReferenceLevel() {
        let index = min(levelIndex, T.bloomReferenceLevels.count - 1)
        simulationReferenceIndex = index
        simulationTuning = ArcadeTuning(level: T.bloomReferenceLevels[index])
    }
    func debugEncounterSpawnSafety() -> Bool {
        simulationTuning = ArcadeTuning(level: worldLevel)
        simulationEcologyProbe = true
        resetGame(startPlaying: true)
        let swimmers = fish.filter { !$0.isPlayer }
        guard swimmers.count == level.spawnGroups.reduce(0, { $0 + $1.count }) else { return false }
        if !level.freeEncounterMovement && foodHomes.count != T.encounterCount * T.encounterFoodCount { return false }
        for (offset, swimmer) in swimmers.enumerated() {
            if !level.freeEncounterMovement && foodHomes[swimmer.id] != nil && swimmer.radius != T.baseRadius * T.encounterFoodRadius { return false }
            for other in swimmers.dropFirst(offset + 1) {
                if hypot(world.delta(from: swimmer.position.x, to: other.position.x), swimmer.position.y - other.position.y)
                    <= (swimmer.radius + other.radius) * T.collisionScale { return false }
            }
            for jelly in jellies {
                let position = CGPoint(x: world.delta(from: jelly.position.x, to: swimmer.position.x),
                    y: swimmer.position.y - jelly.position.y)
                if JellyRules.contact(at: position, previous: position, fishRadius: swimmer.radius,
                    domeRadius: level.jellies!.radius, tentacleLength: level.jellies!.tentacleLength) != .none { return false }
            }
        }
        return true
    }
    func debugFreeEncounterMotionCheck() -> (travel: CGFloat, fastFish: Int, intact: Bool, heightSpread: CGFloat, individualReleases: Int) {
        simulationTuning = ArcadeTuning(level: worldLevel)
        simulationEcologyProbe = true
        resetGame(startPlaying: true)
        let original = fish.filter { !$0.isPlayer }
        let positions = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0.position) })
        let radii = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0.radius) })
        let releases = Set(encounterLeases.values.map(\.releaseDistance)).count
        // Isolate unrestricted movement and the no-eating guard from passage-based release.
        for (id, lease) in encounterLeases {
            encounterLeases[id] = EncounterLease(home: lease.home, releaseDistance: .greatestFiniteMagnitude, index: lease.index)
        }
        for _ in 0..<180 { advanceFrame(T.simulationStep) }
        let travel = original.map { abs(world.delta(from: positions[$0.id]!.x, to: $0.position.x)) }.max() ?? 0
        let heights = jellies.map { $0.origin.y }
        return (travel, original.filter { $0.cruiseSpeed > 100 }.count,
            original.allSatisfy { $0.isAlive && $0.radius == radii[$0.id] },
            (heights.max() ?? 0) - (heights.min() ?? 0), releases)
    }

    func debugAIMovementAllowsBellLanding() -> Bool {
        guard let jelly = jellies.first, let layout = level.jellies,
              let swimmer = fish.first(where: { !$0.isPlayer && $0.isAlive }) else { return false }
        jellies = [jelly]
        fish = [player, swimmer]
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

    func debugAIFallOntoDome() -> Bool {
        guard let jelly = jellies.first, let layout = level.jellies,
              let swimmer = fish.first(where: { !$0.isPlayer && $0.isAlive }) else { return false }
        swimmer.position = CGPoint(x: jelly.position.x,
            y: jelly.position.y + layout.radius * 0.65 + swimmer.radius * T.hazardHitboxScale - 1)
        swimmer.velocity.dy = -180
        var previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
        previous[swimmer.id]!.y += 30
        updateJellies(T.simulationStep, previousFish: previous)
        return swimmer.isAlive && swimmer.velocity.dy > T.motion.maxRiseSpeed
    }

    func debugProtectedPatrolCheck() -> (minimumTravel: CGFloat, maximumThinFraction: Double, intact: Bool) {
        simulationTuning = ArcadeTuning(level: worldLevel)
        simulationEcologyProbe = true
        simulationHolding = false
        resetGame(startPlaying: true)
        let initial = fish.filter { !$0.isPlayer }
        let radii = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.radius) })
        var minX = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.position.x) })
        var maxX = minX
        var thin: [Int: Int] = [:]
        for _ in 0..<180 {
            advanceFrame(T.simulationStep)
            for f in fish where !f.isPlayer {
                minX[f.id] = min(minX[f.id]!, f.position.x)
                maxX[f.id] = max(maxX[f.id]!, f.position.x)
                if abs(f.facing) < 0.4 { thin[f.id, default: 0] += 1 }
            }
        }
        return (initial.map { maxX[$0.id]! - minX[$0.id]! }.min() ?? 0,
            Double(thin.values.max() ?? 0) / 180,
            fish.count == initial.count + 1 && initial.allSatisfy { $0.radius == radii[$0.id] && $0.state == .swimming })
    }
    func debugProtectedFishYieldCheck() -> Bool {
        guard let smaller = fish.first(where: { !$0.isPlayer }),
              let larger = fish.first(where: { !$0.isPlayer && $0.radius > smaller.radius }) else { return false }
        fish = [player, smaller, larger]
        smaller.position = CGPoint(x: size.width, y: waterTop - larger.radius)
        larger.position = CGPoint(x: size.width + 1, y: smaller.position.y)
        // An approaching swimmer yields when the other is already moving away.
        smaller.heading = 1
        smaller.velocity.dx = smaller.cruiseSpeed
        larger.heading = 1
        larger.velocity.dx = larger.cruiseSpeed
        encounterLeases[smaller.id] = EncounterLease(home: smaller.position, releaseDistance: 100)
        encounterLeases[larger.id] = EncounterLease(home: larger.position, releaseDistance: 0)
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
        guard let id = encounterLeases.keys.sorted().first, let lease = encounterLeases[id],
              let prey = fishByID[id], let predator = fish.first(where: { !$0.isPlayer && $0.id != id && $0.radius > prey.radius }) else { return false }
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

    func debugFoodLeavesPocket() -> Bool {
        guard let id = foodHomes.keys.sorted().first else { return false }
        simClock = T.bloomFoodPocketReleaseSeconds - 0.01
        let initiallyBounded = patrolHome(for: id) != nil
        simClock = T.bloomFoodPocketReleaseSeconds
        return initiallyBounded && patrolHome(for: id) == nil
    }
    var debugFoodPocketCount: Int { foodHomes.count }
    var debugFishCount: Int { fish.count }
    var debugUrchinCount: Int { urchins.count }
    var debugAllPredatorsInitiallyLarger: Bool {
        fish.filter { !$0.isPlayer && foodHomes[$0.id] == nil }.allSatisfy { $0.radius > player.radius }
    }
    var debugMealHUDVisible: Bool { mealIndicator.parent != nil && !mealIndicator.isHidden }
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
        simulationTuning = ArcadeTuning(level: worldLevel)
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
            for id in eaten where crossed.contains(id) && fishByID[id] != nil {
                fishByID[id]?.state = .removed
                fish.removeAll { $0.id == id }
                fishByID[id] = nil
                aiMovementRNGs[id] = nil
                encounterLeases[id] = nil
                nodes[id]?.removeFromParent()
                nodes[id] = nil
            }
        }
        return crossings
    }
    #endif

}
