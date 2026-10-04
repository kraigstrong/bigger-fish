import CoreGraphics
import FishKit

/// Every feel-related constant lives here so it can be tweaked quickly between device runs.
enum GameTuning {
    /// Gameplay coordinates never depend on the device's display dimensions.
    static let playfieldSize = CGSize(width: 874, height: 402)

    static func fittedPlayfieldSize(in available: CGSize) -> CGSize {
        let scale = max(0, min(available.width / playfieldSize.width,
                               available.height / playfieldSize.height))
        return CGSize(width: playfieldSize.width * scale, height: playfieldSize.height * scale)
    }

    // MARK: Simulation timing

    static let simulationStep: CGFloat = 1.0 / 60
    /// Bound catch-up after a hitch; longer stalls discard excess elapsed time.
    static let maximumFrameElapsed: CGFloat = 0.25
    static let slowMotionRecoveryRate: CGFloat = 2.5
    #if DEBUG
    /// Log display gaps or frame work longer than 2.5 normal 60 Hz frames.
    static let debugFrameHitchSeconds: CGFloat = simulationStep * 2.5
    static let debugMealHitchSeconds: CGFloat = simulationStep / 2
    #endif

    // MARK: Player movement

    static let motion = MotionTuning(
        riseAcceleration: 1100,  // pt/s² while holding
        fallAcceleration: 1200,  // pt/s² while released
        verticalDamping: 1.2,    // per second; controllable rather than ballistic
        maxRiseSpeed: 250,
        maxFallSpeed: 250,
        boundaryBounce: 0.15,    // fraction of speed reflected at the top/bottom of the water
        maxTilt: 0.35            // radians
    )
    /// Where the player sits horizontally on screen (fraction of width).
    static let playerScreenX: CGFloat = 0.30

    // MARK: Camera

    /// The camera starts zooming out once the player is this many times its starting radius.
    static let zoomStartSize: CGFloat = 1.3
    /// Higher = on-screen player size grows more slowly (0 = no zoom, 1 = player never grows on screen).
    static let zoomExponent: CGFloat = 0.65
    static let minZoom: CGFloat = 0.4
    /// How quickly the camera eases toward its target zoom (per second).
    static let zoomEase: CGFloat = 1.5

    // MARK: World

    static let worldScreens: CGFloat = 4
    static let waterTopMargin: CGFloat = 12
    static let waterBottomMargin: CGFloat = 10

    // MARK: Size and growth

    /// Points of radius for a normalized size of 1.0 (the player's starting size).
    static let baseRadius: CGFloat = 16
    /// Within this fraction, player encounters favor the player; NPC encounters bump apart.
    static let nearEqualThreshold: CGFloat = 0.01
    /// Collision distance = (rA + rB) * collisionScale. Bodies are 1.35r long and 0.95r tall.
    static let collisionScale: CGFloat = 1.05
    /// Applies to every arcade meal, including saved tuning overrides and AI meals.
    static let mealGrowthScale: CGFloat = 0.90
    static let growDuration: CGFloat = 0.35
    /// Seconds for the mouth to open when a swallow begins, and to close after it ends.
    static let mouthOpenSeconds: CGFloat = 0.06
    static let mouthCloseSeconds: CGFloat = 0.14
    static let pulseDuration: CGFloat = 0.25
    static let pulseAmount: CGFloat = 0.15

    // MARK: Swallowing

    /// (prey/predator radius ratio, seconds) — interpolated linearly, clamped at the ends.
    static let swallowDurationCurve: [(ratio: CGFloat, seconds: CGFloat)] = [
        (0.50, 0.12),
        (0.75, 0.30),
        (0.95, 0.72),
        (1.00, 0.80),
    ]
    /// Ratio at or above which a swallow counts as a close call (struggle + haptic).
    static let closeCallRatio: CGFloat = 0.80
    /// Ratio at or above which a player encounter triggers a brief slowdown.
    static let slowMoRatio: CGFloat = 0.93
    static let closeCallSlowFactor: CGFloat = 0.35
    static let closeCallSlowDuration: CGFloat = 0.5

    // MARK: Autonomous fish

    static let aiFishCanEatEachOther = true
    /// AI-on-AI eating is suppressed for this long after a run starts so the opening is readable.
    static let aiEatingGracePeriod: CGFloat = 1.5
    static let aiMaxTilt: CGFloat = 0.15
    static let aiRetargetRange: ClosedRange<CGFloat> = 2...6
    static let aiTurnIntervalRange: ClosedRange<CGFloat> = 8...20

    // MARK: Initial ecosystem

    static let spawnSeed: UInt64 = 20_260_927
    /// No fish spawn in this window (in screen widths) around the player's start.
    static let spawnClearBehind: CGFloat = 0.4
    static let spawnClearAheadSmall: CGFloat = 0.45
    /// Fish at or above `spawnDangerRatio` start further away.
    static let spawnClearAheadDanger: CGFloat = 1.3
    static let spawnDangerRatio: CGFloat = 0.9
    static let spawnPadding: CGFloat = 20

    // MARK: Win

    static let winSlowFactor: CGFloat = 0.3
    static let winSlowDuration: CGFloat = 1.2
    /// Seconds after a win/loss before a tap restarts (avoids accidental restarts from a held finger).
    static let restartDelay: CGFloat = 0.8

    // MARK: Jelly Bloom

    static let hazardHitboxScale: CGFloat = 0.8
    static let urchinRadius: CGFloat = 15
    static let jellyDomeForgiveness: CGFloat = 10
    static let jellyBounceSpeed: CGFloat = 460
    static let jellyBounceSeconds: CGFloat = 0.28
    static let jellyBounceCooldown: CGFloat = 0.24
    static let jellyAvoidancePredictionSteps = 8
    static let bloomFloorLanePadding: CGFloat = 20
    /// Alternating bell heights for authored layouts without per-level heights.
    static let bloomAuthoredJellyHeights: [CGFloat] = [0.37, 0.68]
    static let bloomJellyFallbackFloorGap: CGFloat = 12

    /// Swimmers anticipate curtains; no chasing or fleeing.
    static let bloomAvoidanceLookAhead: CGFloat = 1.2
    static let bloomAvoidancePadding: CGFloat = 16
    static let bloomAvoidanceRiseSpeed: CGFloat = 140
    static let bloomAvoidanceTurnRate: CGFloat = 8

    static let bloomFoodPocketHalfWidth: CGFloat = 76
    static let bloomFoodPocketHalfHeight: CGFloat = 24
    static let bloomFoodPocketLift: CGFloat = 40
    static let bloomFoodPocketReleaseSeconds: CGFloat = 4
    static let bloomJellyOpeningScreens: ClosedRange<CGFloat> = 0.80...1.00
    static let bloomJellyLastScreens: ClosedRange<CGFloat> = 3.40...3.60
    static let bloomJellyGapWeight: ClosedRange<CGFloat> = 0.10...1.80
    static let bloomJellySpacingPadding: CGFloat = 40
    static let bloomJellyHeightRange: ClosedRange<CGFloat> = 0.28...0.76
    static let bloomFoodPatrolScreens: CGFloat = 0.16

    // Level 2 only: a meal beyond the far shoulder, where an early bounce sends you away.
    static let bloomSidePocketJellyIndex = 1
    static let bloomSidePocketOffset: CGFloat = 112
    static let bloomSidePocketDrop: CGFloat = 16
    static let bloomSidePocketSpawnHalfWidth: CGFloat = 30
    static let bloomSidePocketPatrolHalfWidth: CGFloat = 44
    static let bloomSidePredatorOffset: CGFloat = 200

    static let bloomFoodRefillSeconds: CGFloat = 3
    static let bloomFoodRefillCount = 2
    static let bloomFoodRadiusFraction: ClosedRange<CGFloat> = 0.45...0.65

    /// World 1 remains intact. Bloom's curve varies the food-race window, not chase AI.
    /// Profiles were selected by real-scene simulations; see docs/jelly-bloom-balance.md.
    static let bloomReferenceLevels: [Level] = [
        Level(spawnGroups: [(9, 0.30...0.65), (5, 0.65...0.85)],
              aiSpeedRange: 30...80, aiVerticalSpeed: 35, screenCrossSeconds: 3.1,
              absorptionEfficiency: 0.90,
              jellies: JellyLayout(count: 4, radius: 40, tentacleLength: 70, sway: 6)),
        bloomRaceLevel(foodCount: 7, giants: 1, speed: 30...80, vertical: 35,
                       efficiency: 0.88, jellyCount: 5, jellyRadius: 44, tentacles: 70,
                       sidePocket: true, compactSpeedScale: 0.65),
        bloomRaceLevel(foodCount: 3, giants: 2, speed: 45...110, vertical: 55,
                       efficiency: 0.78, jellyCount: 6, jellyRadius: 46, tentacles: 75,
                       seedOffset: 1, compactSpeedScale: 0.65),
        bloomRaceLevel(foodCount: 3, giants: 2, speed: 65...155, vertical: 80,
                       efficiency: 0.78, jellyCount: 6, jellyRadius: 46, tentacles: 75,
                       night: true, compactSpeedScale: 0.50),
        bloomRaceLevel(foodCount: 7, giants: 2, speed: 65...155, vertical: 80,
                       efficiency: 0.82, jellyCount: 7, jellyRadius: 48, tentacles: 75,
                       seedOffset: 1, compactSpeedScale: 0.763, mediumSpeedMultiplier: 0.85),
    ]

    /// Original authoring targets; campaign order follows human playtesting.
    static let bloomSetupSeedOffsets: [UInt64] = [1, 0, 4, 4, 6, 1, 444, 12, 26, 38]
    /// Original setup identities keep their seeds and difficulty when campaign slots move.
    static let bloomCampaignOrder = [0, 1, 5, 3, 4, 6, 2, 7, 8, 9]
    static let bloomLevels: [Level] = bloomCampaignOrder.map { bloomLevelSetups[$0] }
    static let bloomLevelSetups: [Level] = (0..<10).map { index in
        let difficulty = EncounterDifficulty(value: Double(index) / 9)
        let speed: ClosedRange<CGFloat> = index == 1 ? 40...175
            : (35 + CGFloat(difficulty.bounded) * 35)...(150 + CGFloat(difficulty.bounded) * 50)
        return Level(spawnGroups: [(16, 0.65...3)],
            aiSpeedRange: speed, aiVerticalSpeed: index == 1 ? 85 : 65 + CGFloat(difficulty.bounded) * 35,
            screenCrossSeconds: 3.1, absorptionEfficiency: freeEncounterAbsorption,
            jellies: JellyLayout(count: 4, radius: 40, tentacleLength: 70, sway: 6,
                night: index >= 7, maintainsFloorLane: true),
            roamingFoodChain: true, ecosystemSeedOffset: bloomSetupSeedOffsets[index],
            encounterDifficulty: difficulty, freeEncounterMovement: true, ecosystemSeedIndex: index)
    }

    // Encounter groups are authoring budgets, never movement cages. Level 2 retains its accepted layout.
    static let freeEncounterAbsorption: CGFloat = 0.55
    static let freeEncounterCatchFraction: ClosedRange<CGFloat> = 0.55...0.90
    static let freeEncounterCounts = [4, 3, 5, 4]
    static let freeEncounterEdibleCounts = [3, 2, 3, 3]
    static let freeEncounterEdibleSizes: ClosedRange<CGFloat> = 0.65...1.0
    static let freeEncounterThreatSizes: ClosedRange<CGFloat> = 1.15...1.35
    static let freeEncounterHeights: [CGFloat] = [0.32, 0.67, 0.40, 0.56]
    static let freeEncounterReleaseScreens: CGFloat = 0.18
    static let freeEncounterLingerScreens: CGFloat = 0.30
    static let freeEncounterSpawnSpreadScreens: CGFloat = 0.28
    static let freeEncounterFacingRate: CGFloat = 14
    static let freeEncounterEdibleShare: ClosedRange<CGFloat> = 0.62...0.85
    static let freeEncounterHeightVariation: CGFloat = 0.07
    static let freeEncounterHorizontalVariation: CGFloat = 0.16

    static func freeEncounterExpectedCatchFraction(_ difficulty: Double) -> CGFloat {
        let value = CGFloat(min(1, max(0, difficulty)))
        let anchor: CGFloat = 1.0 / 9
        let accepted: CGFloat = freeEncounterCatchFraction.lowerBound
            + anchor * (freeEncounterCatchFraction.upperBound - freeEncounterCatchFraction.lowerBound)
        return value <= anchor ? 0.45 + (accepted - 0.45) * value / anchor
            : accepted + (freeEncounterCatchFraction.upperBound - accepted) * (value - anchor) / (1 - anchor)
    }

    static func freeEncounterWaveBudgets(seed: UInt64, difficulty: Double, preserveLevelTwo: Bool) -> [(count: Int, edible: Int)] {
        if preserveLevelTwo {
            return zip(freeEncounterCounts, freeEncounterEdibleCounts).map { (count: $0.0, edible: $0.1) }
        }
        var generator = SeededGenerator(seed: seed &+ 0x94D049BB133111EB)
        let counts = freeEncounterCounts.shuffled(using: &generator)
        let share = freeEncounterEdibleShare.upperBound - CGFloat(min(1, max(0, difficulty)))
            * (freeEncounterEdibleShare.upperBound - freeEncounterEdibleShare.lowerBound)
        return counts.map { count in
            let varied = share + CGFloat.random(in: -0.06...0.06, using: &generator)
            return (count: count, edible: min(count - 1, max(2, Int((CGFloat(count) * varied).rounded()))))
        }
    }


    static let encounterCatchBudget: ClosedRange<Double> = 3.5...10.5
    static let encounterClearance: ClosedRange<CGFloat> = 10...32
    static let encounterFoodSpacingScreens: CGFloat = 0.15
    static let encounterThreatOffsetScreens: CGFloat = 0.18
    static let encounterFormations: [EncounterFormation] = [
        EncounterFormation(name: "opening", foodOffsets: [
            CGPoint(x: -encounterFoodSpacingScreens, y: 0), .zero, CGPoint(x: encounterFoodSpacingScreens, y: 0)], threatOffset: encounterThreatOffsetScreens),
        EncounterFormation(name: "descending", foodOffsets: [
            CGPoint(x: -0.17, y: 24), CGPoint(x: -0.015, y: 12), CGPoint(x: 0.17, y: 0)], threatOffset: 0.20),
        EncounterFormation(name: "ascending", foodOffsets: [
            CGPoint(x: -0.17, y: 0), CGPoint(x: 0.015, y: 12), CGPoint(x: 0.17, y: 24)], threatOffset: -0.20),
        EncounterFormation(name: "crest", foodOffsets: [
            CGPoint(x: -0.19, y: 0), CGPoint(x: 0, y: 24), CGPoint(x: 0.19, y: 0)], threatOffset: 0.25),
    ]

    static func encounterFormationOrder(seed: UInt64) -> [EncounterFormation] {
        var generator = SeededGenerator(seed: seed &+ 0xD1B54A32D192ED03)
        return [encounterFormations[0]] + encounterFormations.dropFirst().shuffled(using: &generator)
    }
    static let encounterBellHeight: ClosedRange<CGFloat> = 0.30...0.43
    static let encounterFoodRadius: CGFloat = 0.85
    static let encounterAbsorption: CGFloat = 0.82
    static let encounterCount = 4
    static let encounterFoodCount = 3
    static let encounterPatrolWidth: CGFloat = 42
    static let encounterPatrolHeight: CGFloat = 12
    static let encounterPatrolSpeedScale: CGFloat = 0.75
    static let encounterTurnLead: CGFloat = 16
    static let encounterFacingRate: CGFloat = 14
    static let encounterSeparationPadding: CGFloat = 12
    static let encounterSeparationLookAhead: CGFloat = 0.6
    static let encounterSeparationSpeed: CGFloat = 65
    static let protectedFishContactPadding: CGFloat = 1
    static let protectedFishTurnHoldSeconds: CGFloat = 2
    static let encounterExitScreens: CGFloat = 0.45
    static let encounterFirstScreens: CGFloat = 0.75
    static let encounterSpacingScreens: CGFloat = 0.78
    static let encounterJitterScreens: CGFloat = 0.04

    private static func bloomRaceLevel(foodCount: Int, giants: Int, speed: ClosedRange<CGFloat>,
                                       vertical: CGFloat, efficiency: CGFloat, jellyCount: Int,
                                       jellyRadius: CGFloat, tentacles: CGFloat, sidePocket: Bool = false,
                                       night: Bool = false, seedOffset: UInt64 = 0, compactSpeedScale: CGFloat = 1,
                                       mediumSpeedMultiplier: CGFloat = 1) -> Level {
        Level(spawnGroups: [(foodCount, 0.42...0.62), (5, 0.66...0.90), (5, 0.92...1.08),
                            (4, 1.20...1.60), (giants, 2.00...2.60)],
              aiSpeedRange: speed, aiVerticalSpeed: vertical, screenCrossSeconds: 3.1,
              absorptionEfficiency: efficiency,
              jellies: JellyLayout(count: jellyCount, radius: jellyRadius, tentacleLength: tentacles,
                                  sway: 6, night: night, maintainsFloorLane: true),
              bounceFoodPockets: true, sidePocketExperiment: sidePocket, roamingFoodChain: true,
              ecosystemSeedOffset: seedOffset, compactAISpeedScale: compactSpeedScale,
              mediumAISpeedMultiplier: mediumSpeedMultiplier)
    }

    // MARK: Levels

    /// Each level ramps several levers at once: fewer easy meals, more near-equal and larger fish,
    /// faster fish, a faster player, and less growth per meal.
    static let levels: [Level] = [
        Level(
            spawnGroups: [(6, 0.30...0.55), (5, 0.55...0.80), (3, 0.90...1.15), (2, 1.35...1.70), (1, 2.10...2.50)],
            aiSpeedRange: 35...95, aiVerticalSpeed: 45, screenCrossSeconds: 2.75, absorptionEfficiency: 0.90
        ),
        Level(
            spawnGroups: [(5, 0.35...0.58), (5, 0.58...0.82), (4, 0.88...1.12), (3, 1.30...1.70), (1, 2.10...2.50)],
            aiSpeedRange: 45...115, aiVerticalSpeed: 55, screenCrossSeconds: 2.6, absorptionEfficiency: 0.86
        ),
        Level(
            spawnGroups: [(4, 0.40...0.60), (5, 0.62...0.86), (5, 0.90...1.10), (3, 1.25...1.60), (2, 1.90...2.40)],
            aiSpeedRange: 55...135, aiVerticalSpeed: 68, screenCrossSeconds: 2.45, absorptionEfficiency: 0.82
        ),
        Level(
            spawnGroups: [(3, 0.42...0.62), (5, 0.66...0.90), (5, 0.92...1.08), (4, 1.20...1.60), (2, 2.00...2.60)],
            aiSpeedRange: 65...155, aiVerticalSpeed: 80, screenCrossSeconds: 2.3, absorptionEfficiency: 0.78
        ),
        Level(
            spawnGroups: [(3, 0.45...0.65), (4, 0.70...0.92), (6, 0.94...1.06), (4, 1.15...1.50), (3, 1.90...2.80)],
            aiSpeedRange: 80...175, aiVerticalSpeed: 95, screenCrossSeconds: 2.15, absorptionEfficiency: 0.75
        ),
    ]
}

struct Level {
    /// Normalized radii (player starts at 1.0).
    let spawnGroups: [(count: Int, radii: ClosedRange<CGFloat>)]
    let aiSpeedRange: ClosedRange<CGFloat>
    let aiVerticalSpeed: CGFloat
    /// Seconds for the player to cross one screen width.
    let screenCrossSeconds: CGFloat
    let absorptionEfficiency: CGFloat
    var effectiveAbsorptionEfficiency: CGFloat { absorptionEfficiency * GameTuning.mealGrowthScale }
    var jellies: JellyLayout? = nil
    var aiCanEat: Bool = true
    var requiredMeals: Int = 0
    var predatorSpawnSeparationScreens: CGFloat = 0
    var bounceFoodPockets: Bool = false
    var sidePocketExperiment: Bool = false
    var roamingFoodChain: Bool = false
    /// Fixed per-level seed selection keeps retries consistent. Debug studies perturb this seed.
    var ecosystemSeedOffset: UInt64 = 0
    var compactAISpeedScale: CGFloat = 1
    var mediumAISpeedMultiplier: CGFloat = 1
    var encounterDifficulty: EncounterDifficulty? = nil
    var freeEncounterMovement: Bool = false
    /// Seed identity is independent of the displayed campaign number.
    var ecosystemSeedIndex: Int? = nil
    func spawnSeed(index: Int, bloom: Bool, offset: UInt64? = nil) -> UInt64 {
        GameTuning.spawnSeed &+ UInt64((ecosystemSeedIndex ?? index) + (bloom ? 100 : 0))
            &+ (offset ?? ecosystemSeedOffset)
    }
}
