import CoreGraphics
import Foundation
import FishKit
import SpriteKit

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
    /// Where display frames fall between simulation steps when a run starts or resumes: halfway. At 60 Hz frames come
    /// a step apart, so they stay halfway, clear of the step boundaries: timing jitter never leaves a frame with no
    /// step or two.
    static let frameRemainderStart: CGFloat = simulationStep / 2
    /// Frames draw a blend of the last two steps, a step behind the newest: the smooth way to show a fixed step on a
    /// faster display. Once this many frames in a row have each simulated a step of their own at full speed (a 60 Hz
    /// display), there's nothing to blend between frames, so they draw the newest step instead, and a touch shows on
    /// the frame it lands rather than a step later.
    static let newestStepAfterFrames = 8
    /// How fast drawing moves between the two, in seconds of lag per second: a step's change takes four steps (67 ms),
    /// so motion never jumps.
    static let presentationLagEase: CGFloat = 0.25
    /// In slow motion a frame now and then lands further past the newest step than a step; drawing that far behind
    /// lets go this slowly, so slow motion keeps an even pace.
    static let presentationLagSettle: CGFloat = 0.02
    #if DEBUG
    /// Log a meal whose work takes longer than half a 60 Hz frame. Slow frames themselves are `HitchLog`'s.
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

    /// The loading screen stays up at least this long, so a fast launch doesn't flash it.
    static let launchMinimumSeconds: Double = 0.8
    /// The loading bar: a short dash sweeping back and forth along a thin track (points and seconds).
    static let launchBarTrack: CGFloat = 120
    static let launchBarFillShare: CGFloat = 0.22
    static let launchBarThickness: CGFloat = 4
    static let launchBarSweepSeconds: Double = 0.55

    // MARK: Haptics (`GameScene.buzz`)

    /// Strengths (0–1): an ordinary meal's light tap, and a jellyfish bounce's bump. Close calls, stings, and being
    /// eaten use their generator's full strength.
    static let mealHapticIntensity: CGFloat = 0.5
    static let bounceHapticIntensity: CGFloat = 0.55
    /// Conquering a world: the success buzz, then this long after, a thump this strong.
    static let conquerThumpDelay: CGFloat = 0.25
    static let conquerThumpIntensity: CGFloat = 1

    // MARK: Sound

    static let effectVolume: Float = 0.7
    /// The level-clear chime is fuller than the other effects, so it plays a little quieter.
    static let clearSoundVolume: Float = 0.55
    /// A jellyfish bounce reuses the gulp, sped up (and pitched up) by this much.
    static let bounceSoundRate: Float = 1.35
    /// Music sits under the effects; both tracks are normalized to -18 LUFS before this.
    static let musicVolume: Float = 0.45
    /// Crossfade between the menu and game tracks.
    static let musicFadeSeconds: Double = 1.0

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
    /// Worlds where a fish roaming free rises and dives as fast on screen however far the camera has zoomed out, so
    /// roaming fish use all the water it shows. Elsewhere their speed is the same in the world, so as the camera zooms out
    /// they slow on screen and stay near where they met you (Shallow Reef and Jelly Bloom also plan free swims to their
    /// meetings at that speed, so it can't change there).
    static let zoomedRoamingWorlds: Set<ArcadeWorld> = [.sunsetCove]

    // MARK: Initial ecosystem

    static let spawnSeed: UInt64 = 20_260_927
    /// No fish spawn in this window (in screen widths) around the player's start.
    static let spawnClearBehind: CGFloat = 0.4
    static let spawnClearAheadSmall: CGFloat = 0.45
    /// Fish at or above `spawnDangerRatio` start further away.
    static let spawnClearAheadDanger: CGFloat = 1.3
    static let spawnDangerRatio: CGFloat = 0.9

    // MARK: Win

    static let winSlowFactor: CGFloat = 0.3
    static let winSlowDuration: CGFloat = 1.2
    /// Seconds a world-conquering win plays (its sound and glow) before going straight to the conquered screen.
    static let conqueredExitDelay: CGFloat = 1.6
    /// Seconds after a win/loss before a tap restarts (avoids accidental restarts from a held finger).
    static let restartDelay: CGFloat = 0.8

    // MARK: Jelly Bloom

    static let hazardHitboxScale: CGFloat = 0.8
    static let jellyDomeForgiveness: CGFloat = 10
    static let jellyBounceSpeed: CGFloat = 460
    static let jellyBounceSeconds: CGFloat = 0.28
    static let jellyBounceCooldown: CGFloat = 0.24
    /// A jellyfish swims in strokes: a quick squeeze (this share of the stroke), then a slow release.
    static let jellyStrokeSeconds: CGFloat = 1.7
    static let jellySqueezeShare: CGFloat = 0.28
    /// How long a jellyfish's tentacles flash after stinging.
    static let jellyStingFlashSeconds: CGFloat = 0.6
    /// A stung fish jolts, rolls belly-up, and sinks out of sight; the result panel waits for it.
    static let stingJoltSeconds: CGFloat = 0.45
    static let stingRollSeconds: CGFloat = 0.35
    static let stingFadeStart: CGFloat = 0.9
    static let stingSeconds: CGFloat = 1.5
    static let stingResultDelay: CGFloat = 1.1
    static let jellyAvoidancePredictionSteps = 8

    /// Swimmers anticipate curtains; no chasing or fleeing.
    static let bloomAvoidanceLookAhead: CGFloat = 1.2
    static let bloomAvoidancePadding: CGFloat = 16
    static let bloomAvoidanceRiseSpeed: CGFloat = 140
    static let bloomAvoidanceTurnRate: CGFloat = 8

    /// Jelly Bloom 2: each bell wanders this far side to side (screen widths each way) and bobs this many
    /// points, over these periods.
    static let jellyDriftScreens: CGFloat = 0.1
    static let jellyDriftSeconds: CGFloat = 12
    static let jellyBobPoints: CGFloat = 22
    static let jellyBobSeconds: CGFloat = 7

    // MARK: Planned fish

    /// Planned levels: a meal adds this share of its area to the eater (before `mealGrowthScale`). Each planned fish
    /// is protected until you're this many screens past its meeting, and turns to face the way it swims at this rate.
    static let freeEncounterAbsorption: CGFloat = 0.55
    static let freeEncounterReleaseScreens: CGFloat = 0.18
    static let freeEncounterFacingRate: CGFloat = 14

    /// Planned fish you haven't met steer apart (`EncounterSteering`) within this padding, looking this many seconds
    /// ahead, at up to this speed; touching anyway, they part by this many points and the one turned away holds
    /// its new heading this long.
    static let encounterSeparationPadding: CGFloat = 12
    static let encounterSeparationLookAhead: CGFloat = 0.6
    static let encounterSeparationSpeed: CGFloat = 65
    static let protectedFishContactPadding: CGFloat = 1
    static let protectedFishTurnHoldSeconds: CGFloat = 2

    // MARK: Asking for a review (`ArcadeReview`)

    /// At most this many requests ever, this far apart (90 days), as Math Reef does.
    static let reviewRequestLimit = 2
    static let reviewRetryInterval: TimeInterval = 90 * 24 * 60 * 60
    /// How long after landing on the map the request waits, so it doesn't pop up mid-transition.
    static let reviewRequestDelay: TimeInterval = 1.0

    // MARK: Free to try (`ArcadeUnlock`)

    /// Levels free without the unlock in each world after Shallow Reef (all ten of whose are free): a taste of what the
    /// unlock opens. 0 locks those worlds whole.
    static let freeLevelsPerWorld = 2

    // MARK: Meeting planner

    // Meeting layout shared by every planned level; each MeetingSpec sets its own spacing and sizes.
    /// The first meeting comes this many screen widths into the run.
    static let plannerFirstMeetingScreens: CGFloat = 0.6
    /// The last meeting comes this many screens before the lap ends.
    static let plannerLastMeetingMargin: CGFloat = 0.3
    /// A near-equal swallow takes up to 0.8 s; the next meeting waits a beat longer.
    static let plannerGateRecoverySeconds: CGFloat = 1.0
    /// A danger meal's threat crosses this many screen widths of time before or after it.
    static let plannerDangerOffsetScreens: CGFloat = 0.07
    /// Seconds between a fork's two lanes crossing: too close to take both.
    static let plannerForkOffsetSeconds: CGFloat = 0.12
    /// Room, in meeting gaps, to reach either lane before a fork and to come back after it.
    static let plannerForkLead: CGFloat = 1.3
    /// Heights as a share of the water a fish can reach: single meals, fork lanes, and the meals either side of a fork.
    static let plannerHeightLimits: ClosedRange<CGFloat> = 0.08...0.92
    static let plannerHighLane: ClosedRange<CGFloat> = 0.78...0.92
    static let plannerLowLane: ClosedRange<CGFloat> = 0.08...0.22
    static let plannerMidWater: ClosedRange<CGFloat> = 0.42...0.58
    /// Screen points of combined body overlap counted on top of swimming reach between meals.
    static let plannerMealHeightTolerance: CGFloat = 20
    /// The first meal (zero-based) a threat may cross beside.
    static let plannerEarliestDangerMeal = 3
    /// A gate's wall fish cross this long before and after it: apart enough that eating the gate comes
    /// first, close enough that there's no time to swim around.
    static let plannerWallOffsetSeconds: CGFloat = 0.1
    /// Screen points between a gate and its wall fish: under a fish's width, so nobody slips between,
    /// and clear of the separation reach planned fish keep from each other on screen.
    static let plannerWallGap: CGFloat = 30
    /// Fish you overtake swim within this share of the slow end of the speed range: near your speed they
    /// creep toward you for seconds, as if fleeing.
    static let plannerSameDirectionSpeedShare = 0.3

    // Jelly Bloom 2's planned jellies.
    /// A bounce meal crosses this long after the pocket meal you bounce from.
    static let plannerBounceSeconds: CGFloat = 0.5
    /// A pocket you bounce on is at most this share of your size, so it's swallowed before the climb.
    static let plannerBouncePocketSize: CGFloat = 0.76
    /// Screen points of water between a pocket meal's body and the dome under it (plus a fifth of its radius).
    static let plannerPocketGap: CGFloat = 8
    /// Scattered open-water jellies (`JellySpec.scattered`) are tried this often along the lap, clear of any
    /// straight swim between two meals at most this far apart in time.
    static let plannerScatterStep: CGFloat = 0.1
    static let plannerScatterSwimSeconds: CGFloat = 1.2
    /// Screen points kept clear between any dome and the surface, beyond its bob: room for a fish to pass over.
    static let plannerDomeHeadroom: CGFloat = 40
    /// Screen points a pocket meal keeps below the top of the water, room to bounce.
    static let plannerPocketHeadroom: CGFloat = 50
    /// Screen points a bounce meal sits beyond swimming reach and within the bounce's.
    static let plannerBounceMargin: CGFloat = 12
    /// The demo meal crosses this high (share of the water); its bounce sends it up there.
    static let plannerDemoHeight: ClosedRange<CGFloat> = 0.72...0.86
    static let plannerDemoHeightTolerance: CGFloat = 60
    /// The demo fish lands on its jelly while the jelly is this far across the screen, at least this long
    /// after the start and before you meet it.
    static let plannerDemoScreen: ClosedRange<CGFloat> = 0.5...0.85
    static let plannerDemoLeadSeconds: CGFloat = 0.6
    /// The solver only replays a swim around the jellies when it's within this many screen points of its height.
    static let plannerJellyReplayMargin: CGFloat = 30
    /// Times the solver restarts a fish where its swim, steered around bells on screen, actually meets you.
    static let plannerSteeredRespawns = 3
    /// Jellies leave room for a player this much bigger than the reference route's.
    static let plannerJellyPlayerAllowance: CGFloat = 1.2

    /// Planned fish you haven't met only separate within this many points of the screen.
    static let plannedContactScreenMargin: CGFloat = 100
    /// The planner keeps unmet fish apart over a wider window, so route timing drift can't bring a contact on screen.
    static let plannerContactScreenMargin: CGFloat = 180

    /// Reef Lab: a ten-level planned Shallow Reef to A/B test against the campaign, slot for slot. Levels 2,
    /// 6, and 10 are the playtested Easy, Medium, and Hard (their names seed their layouts, so keep them;
    /// each has one fewer open-water threat than it asks for, as played);
    /// the levels between step their settings from one to the next. Speeds follow Shallow Reef's authoring
    /// curve. Forks offer a high and a low lane at once, the long lane buying margin beside danger; open-water
    /// threats return on lap two near the size you should have reached.
    static let reefLabSpecs: [MeetingSpec] = [
        // An introduction: forgiving gates and a couple of big fish to avoid, with plenty of room.
        MeetingSpec(name: "Reef Lab 1",
            segments: [.init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 1, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 2)],
            extraThreats: 1, lapTwoSize: 0.9...0.96, headOnShare: 0.5, heightSwing: 0.1...0.35, foodSize: 0.7...0.84,
            gateMargin: 0.9, dangerGap: 80, threatClearance: 120, spacing: 0.27, aiSpeed: 45...120, aiVertical: 60,
            crossSeconds: 2.9),
        MeetingSpec(name: "Easy",
            segments: [.init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 2)],
            extraThreats: 2, lapTwoSize: 0.72...0.82, headOnShare: 0.55, heightSwing: 0.1...0.45, foodSize: 0.68...0.84,
            gateMargin: 0.8, dangerGap: 70, threatClearance: 110, spacing: 0.25, aiSpeed: 48...129, aiVertical: 64,
            crossSeconds: 2.86),
        MeetingSpec(name: "Reef Lab 3",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2)],
            extraThreats: 2, lapTwoSize: 0.76...0.85, headOnShare: 0.55, heightSwing: 0.2...0.55, foodSize: 0.68...0.84,
            gateMargin: 0.7, dangerGap: 62, threatClearance: 95, spacing: 0.24, aiSpeed: 51...138, aiVertical: 69,
            crossSeconds: 2.81),
        MeetingSpec(name: "Reef Lab 4",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 5, extraThreats: 2, lapTwoSize: 0.8...0.88, headOnShare: 0.58, heightSwing: 0.25...0.6,
            foodSize: 0.67...0.83, gateMargin: 0.6, dangerGap: 55, threatClearance: 85, spacing: 0.23,
            aiSpeed: 53...147, aiVertical: 73, crossSeconds: 2.77),
        MeetingSpec(name: "Reef Lab 5",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 2)], needed: 2, dangerFoods: 1)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.82...0.9, headOnShare: 0.6, heightSwing: 0.3...0.7,
            foodSize: 0.66...0.82, gateMargin: 0.55, dangerGap: 50, threatClearance: 78, spacing: 0.22,
            aiSpeed: 56...156, aiVertical: 76, crossSeconds: 2.72),
        MeetingSpec(name: "Medium",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 2)], needed: 2, dangerFoods: 1)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.85...0.93, headOnShare: 0.6, heightSwing: 0.35...0.75,
            foodSize: 0.66...0.82, gateMargin: 0.45, dangerGap: 45, threatClearance: 70, spacing: 0.22,
            aiSpeed: 59...164, aiVertical: 78, crossSeconds: 2.68),
        MeetingSpec(name: "Reef Lab 7",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 1)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.88...0.94, headOnShare: 0.62, heightSwing: 0.4...0.78,
            foodSize: 0.7...0.85, gateMargin: 0.35, dangerGap: 36, threatClearance: 56, spacing: 0.24,
            aiSpeed: 62...173, aiVertical: 87, crossSeconds: 2.63),
        // Hard's shape without its walls: near-size meals and little margin. Playtested: "about perfect".
        MeetingSpec(name: "Reef Lab 8",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 2)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.9...0.96, headOnShare: 0.66, heightSwing: 0.45...0.82,
            foodSize: 0.73...0.87, gateMargin: 0.2, dangerGap: 26, threatClearance: 40, spacing: 0.25,
            aiSpeed: 64...182, aiVertical: 91, crossSeconds: 2.59, timesTheEdge: true),
        // Walls arrive: a gate can't be dodged and saved for lap two. Playtested: "about perfect".
        MeetingSpec(name: "Reef Lab 9",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 2)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.92...0.97, headOnShare: 0.68, heightSwing: 0.5...0.85,
            foodSize: 0.74...0.88, gateMargin: 0.12, dangerGap: 20, threatClearance: 34, spacing: 0.27,
            aiSpeed: 67...191, aiVertical: 96, crossSeconds: 2.54, walledGates: true, timesTheEdge: true),
        // Every gate can be reached by the short lanes with nothing to spare; the long lanes, beside tight
        // danger, buy margin. Meals are close to your size, so every catch is a close call; gates are barely
        // edible and walled; lap-two fish are barely edible.
        MeetingSpec(name: "Hard",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 2)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.94...0.99, headOnShare: 0.7, heightSwing: 0.5...0.85,
            foodSize: 0.76...0.9, gateMargin: 0.05, dangerGap: 16, threatClearance: 28, spacing: 0.26,
            aiSpeed: 75...210, aiVertical: 105, crossSeconds: 2.4, walledGates: true, timesTheEdge: true),

        // Bonus levels 11–15: levels 8–10's difficulty, each with a feel of its own.
        // Crossroads: two forks before every gate, so there are many ways through; one late fork is three meals
        // high or one low. Unwalled, like level 8.
        MeetingSpec(name: "Crossroads",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 2, short: 1)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 3, short: 1), .init(long: 1, short: 1)], needed: 3, dangerFoods: 2)],
            worldScreens: 6, extraThreats: 3, lapTwoSize: 0.9...0.96, headOnShare: 0.66, heightSwing: 0.45...0.82,
            foodSize: 0.73...0.87, gateMargin: 0.2, dangerGap: 26, threatClearance: 40, spacing: 0.25,
            aiSpeed: 64...182, aiVertical: 91, crossSeconds: 2.59, timesTheEdge: true),
        // Frenzy: quick meals and four walled gates. It opens with a burst: eat three of the first four or the
        // first gate eats you.
        MeetingSpec(name: "Frenzy",
            segments: [.init(singles: 3, forks: [.init(long: 1, short: 1)], needed: 3),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 6, extraThreats: 3, lapTwoSize: 0.93...0.98, headOnShare: 0.68, heightSwing: 0.5...0.85,
            foodSize: 0.66...0.8, gateMargin: 0.15, dangerGap: 24, threatClearance: 38, spacing: 0.21,
            aiSpeed: 64...186, aiVertical: 93, crossSeconds: 2.57, walledGates: true, timesTheEdge: true),
        // Gauntlet: big fish everywhere in open water, threading between meals, and they all come back on
        // lap two a little smaller than you. (Bigger ones crowded each other off schedule.)
        MeetingSpec(name: "Gauntlet",
            segments: [.init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 6.5, extraThreats: 6, lapTwoSize: 0.86...0.93, headOnShare: 0.66, heightSwing: 0.45...0.82,
            foodSize: 0.73...0.87, gateMargin: 0.18, dangerGap: 24, threatClearance: 30, spacing: 0.26,
            aiSpeed: 66...188, aiVertical: 94, crossSeconds: 2.56, timesTheEdge: true),
        // Heavyweights: few meals, each nearly your size, so every bite is a close call; one or two meals
        // open each walled gate.
        MeetingSpec(name: "Heavyweights",
            segments: [.init(singles: 1, forks: [.init(long: 1, short: 1)], needed: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 0, forks: [.init(long: 1, short: 1)], needed: 1, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 5.5, extraThreats: 3, lapTwoSize: 0.93...0.98, headOnShare: 0.68, heightSwing: 0.45...0.82,
            foodSize: 0.85...0.93, gateMargin: 0.1, dangerGap: 22, threatClearance: 34, spacing: 0.3,
            aiSpeed: 66...190, aiVertical: 95, crossSeconds: 2.55, walledGates: true, timesTheEdge: true),
        // Needle: tight windows. Most meals cross a beat from a big fish with little room between, and every
        // gate is walled.
        MeetingSpec(name: "Needle",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 3),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 3)],
            worldScreens: 5, extraThreats: 2, lapTwoSize: 0.93...0.98, headOnShare: 0.68, heightSwing: 0.5...0.85,
            foodSize: 0.74...0.88, gateMargin: 0.1, dangerGap: 12, threatClearance: 30, spacing: 0.26,
            aiSpeed: 70...200, aiVertical: 100, crossSeconds: 2.48, walledGates: true, timesTheEdge: true),
    ]

    /// Playtested levels whose shipped plans are frozen: regenerating ReefLabPlans.json keeps them exactly
    /// as played, so later planner changes can't reshuffle them. Remove a name to re-plan that level.
    /// The bonus levels (11 on) joined once they'd been played. Gauntlet is its plan as first played with
    /// fish 9, the first giant, started 380 points closer: it crosses just after the first gate, over the
    /// swim to the next meal, instead of closing the high lane while a big fish guards the low one.
    /// Heavyweights is its plan with fish 20, a giant, started 420 points farther: it crosses while you
    /// swallow the second walled gate instead of between that gate and the fork before it, where it shut
    /// both lanes out. That gate (fish 22) is 38.8 points rather than 42: a player one meal short who took
    /// the low lane met it still growing from the lane's meal and lost. At 38.8 the lane's meal makes it
    /// edible from the first frame after its swallow; without that meal it still isn't.
    static let reefLabFrozen: Set<String> = Set(reefLabSpecs.map(\.name))

    /// Jelly Bloom 2: Shallow Reef 2's ten fish curves, with drifting jellyfish brought in a mechanic at a time.
    /// Levels 1–2: bells to bounce on if you like, with lots of room (level 1 shows a fish bouncing). From 3,
    /// meals with tentacles hanging just above them. From 5, meals only a bounce reaches in time, then
    /// forks split by a jelly: bounce off its dome into the high lane or dive under its tentacles.
    /// Levels 9–10: tentacles wall the gates from above. Names seed the layouts; never rename one.
    static let jellyLabSpecs: [MeetingSpec] = [
        MeetingSpec(name: "Jelly Lab 1",
            segments: [.init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 1, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 2)],
            extraThreats: 1, lapTwoSize: 0.9...0.96, headOnShare: 0.5, heightSwing: 0.1...0.35, foodSize: 0.7...0.84,
            gateMargin: 0.9, dangerGap: 80, threatClearance: 120, spacing: 0.27, aiSpeed: 45...120, aiVertical: 60,
            crossSeconds: 2.9, jellies: JellySpec(demoBounce: true, pockets: 1, open: 1)),
        MeetingSpec(name: "Jelly Lab 2",
            segments: [.init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 2)],
            extraThreats: 2, lapTwoSize: 0.72...0.82, headOnShare: 0.55, heightSwing: 0.1...0.45, foodSize: 0.68...0.84,
            gateMargin: 0.8, dangerGap: 70, threatClearance: 110, spacing: 0.25, aiSpeed: 48...129, aiVertical: 64,
            crossSeconds: 2.86, jellies: JellySpec(pockets: 2, open: 2)),
        MeetingSpec(name: "Jelly Lab 3",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2)],
            extraThreats: 2, lapTwoSize: 0.76...0.85, headOnShare: 0.55, heightSwing: 0.2...0.55, foodSize: 0.68...0.84,
            gateMargin: 0.7, dangerGap: 62, threatClearance: 95, spacing: 0.24, aiSpeed: 51...138, aiVertical: 69,
            crossSeconds: 2.81, jellies: JellySpec(pockets: 1, stingMeals: 1, open: 1)),
        MeetingSpec(name: "Jelly Lab 4",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 5, extraThreats: 2, lapTwoSize: 0.8...0.88, headOnShare: 0.58, heightSwing: 0.25...0.6,
            foodSize: 0.67...0.83, gateMargin: 0.6, dangerGap: 55, threatClearance: 85, spacing: 0.23,
            aiSpeed: 53...147, aiVertical: 73, crossSeconds: 2.77, jellies: JellySpec(pockets: 1, stingMeals: 2, open: 1)),
        MeetingSpec(name: "Jelly Lab 5",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1, bounceMeals: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 2)], needed: 2, dangerFoods: 1)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.82...0.9, headOnShare: 0.6, heightSwing: 0.3...0.7,
            foodSize: 0.66...0.82, gateMargin: 0.55, dangerGap: 50, threatClearance: 78, spacing: 0.22,
            aiSpeed: 56...156, aiVertical: 76, crossSeconds: 2.72, jellies: JellySpec(pockets: 1, stingMeals: 1, open: 1)),
        MeetingSpec(name: "Jelly Lab 6",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1, bounce: true)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 2)], needed: 2, dangerFoods: 1, bounceMeals: 1)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.85...0.93, headOnShare: 0.6, heightSwing: 0.35...0.75,
            foodSize: 0.66...0.82, gateMargin: 0.45, dangerGap: 45, threatClearance: 70, spacing: 0.22,
            aiSpeed: 59...164, aiVertical: 78, crossSeconds: 2.68, jellies: JellySpec(stingMeals: 2, open: 1)),
        MeetingSpec(name: "Jelly Lab 7",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1, bounce: true)], needed: 3, dangerFoods: 2, bounceMeals: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 1)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.88...0.94, headOnShare: 0.62, heightSwing: 0.4...0.78,
            foodSize: 0.7...0.85, gateMargin: 0.35, dangerGap: 36, threatClearance: 56, spacing: 0.24,
            aiSpeed: 62...173, aiVertical: 87, crossSeconds: 2.63, jellies: JellySpec(stingMeals: 2, open: 1)),
        MeetingSpec(name: "Jelly Lab 8",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1, bounce: true)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 2, short: 1, bounce: true), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 2)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.9...0.96, headOnShare: 0.66, heightSwing: 0.45...0.82,
            foodSize: 0.73...0.87, gateMargin: 0.2, dangerGap: 26, threatClearance: 40, spacing: 0.25,
            aiSpeed: 64...182, aiVertical: 91, crossSeconds: 2.59, timesTheEdge: true,
            jellies: JellySpec(night: true, stingMeals: 2, open: 1)),
        MeetingSpec(name: "Jelly Lab 9",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1, bounce: true)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 2)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.92...0.97, headOnShare: 0.68, heightSwing: 0.5...0.85,
            foodSize: 0.74...0.88, gateMargin: 0.12, dangerGap: 20, threatClearance: 34, spacing: 0.27,
            aiSpeed: 67...191, aiVertical: 96, crossSeconds: 2.54, walledGates: true, timesTheEdge: true,
            jellies: JellySpec(night: true, stingMeals: 1, tentacleWalls: true)),
        MeetingSpec(name: "Jelly Lab 10",
            segments: [.init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1, bounce: true)], needed: 3, dangerFoods: 2),
                       .init(singles: 1, forks: [.init(long: 2, short: 1, bounce: true), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 2)],
            worldScreens: 5, extraThreats: 3, lapTwoSize: 0.94...0.99, headOnShare: 0.7, heightSwing: 0.5...0.85,
            foodSize: 0.76...0.9, gateMargin: 0.05, dangerGap: 16, threatClearance: 28, spacing: 0.26,
            aiSpeed: 75...210, aiVertical: 105, crossSeconds: 2.4, walledGates: true, timesTheEdge: true,
            jellies: JellySpec(night: true, stingMeals: 1, tentacleWalls: true)),

        // Bonus levels 11–15: levels 8–10's difficulty, each with a feel of its own, several from Shallow Reef's
        // bonus levels with jellies added.
        // Bell Field: a field of bells, about twice as thick as other levels: jellies scattered through open water
        // as well as meals on domes and under tentacles, a fork split by a bell, a bounce-only meal, and fewer
        // big fish. Unwalled, like level 8, with tighter gates than the first version.
        MeetingSpec(name: "Bell Field",
            segments: [.init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1, bounce: true)], needed: 3, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1, bounceMeals: 1)],
            worldScreens: 7.5, extraThreats: 2, lapTwoSize: 0.9...0.96, headOnShare: 0.66, heightSwing: 0.45...0.82,
            foodSize: 0.73...0.87, gateMargin: 0.15, dangerGap: 26, threatClearance: 40, spacing: 0.25,
            aiSpeed: 64...182, aiVertical: 91, crossSeconds: 2.59, timesTheEdge: true,
            jellies: JellySpec(pockets: 1, stingMeals: 3, open: 9, openClearance: 36, scattered: true)),
        // Jelly Frenzy: Shallow Reef's Frenzy (quick meals, four walled gates, a burst opening) with meals on domes
        // and jellies scattered through open water. Gates are tighter than the first version, beaten on try two.
        // Ships as variation 2 of these settings (its intro was a favorite), with the three open-water jellies
        // after the third gate removed by hand: grown huge for the cleanup, you couldn't steer around them.
        MeetingSpec(name: "Jelly Frenzy",
            segments: [.init(singles: 3, forks: [.init(long: 1, short: 1)], needed: 3),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 6.5, extraThreats: 3, lapTwoSize: 0.93...0.98, headOnShare: 0.68, heightSwing: 0.5...0.85,
            foodSize: 0.66...0.8, gateMargin: 0.11, dangerGap: 24, threatClearance: 38, spacing: 0.21,
            aiSpeed: 64...186, aiVertical: 93, crossSeconds: 2.57, walledGates: true, timesTheEdge: true,
            jellies: JellySpec(pockets: 2, stingMeals: 1, open: 7, openClearance: 36, scattered: true)),
        // Jelly Gauntlet: Shallow Reef's Gauntlet with four big fish, a little smaller, threading between bells.
        MeetingSpec(name: "Jelly Gauntlet",
            segments: [.init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 6.5, extraThreats: 4, lapTwoSize: 0.82...0.9, headOnShare: 0.66, heightSwing: 0.45...0.82,
            foodSize: 0.73...0.87, gateMargin: 0.18, dangerGap: 24, threatClearance: 30, spacing: 0.26,
            aiSpeed: 66...188, aiVertical: 94, crossSeconds: 2.56, timesTheEdge: true,
            jellies: JellySpec(pockets: 1, stingMeals: 1)),
        // Night Heavyweights: Shallow Reef's Heavyweights (few meals, each nearly your size) with meals on domes,
        // tentacles walling the gates, and a meal only a bounce reaches. Gates are tighter and danger crosses
        // closer than the first version, which was beaten on the first try. Its big fish 14 starts 250 points
        // farther ahead than planned so it doesn't run into fish 12 and 13 on screen.
        MeetingSpec(name: "Night Heavyweights",
            segments: [.init(singles: 1, forks: [.init(long: 1, short: 1)], needed: 1),
                       .init(singles: 0, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1, bounceMeals: 1),
                       .init(singles: 0, forks: [.init(long: 1, short: 1)], needed: 1, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1)],
            worldScreens: 6.5, extraThreats: 1, lapTwoSize: 0.93...0.98, headOnShare: 0.68, heightSwing: 0.45...0.82,
            foodSize: 0.85...0.93, gateMargin: 0.08, dangerGap: 18, threatClearance: 34, spacing: 0.3,
            aiSpeed: 66...190, aiVertical: 95, crossSeconds: 2.55, walledGates: true, timesTheEdge: true,
            jellies: JellySpec(night: true, pockets: 2, stingMeals: 1, tentacleWalls: true)),
        // Curtain: tight windows under tentacles. Most meals cross just under hanging tentacles, and tentacles
        // wall the gates.
        MeetingSpec(name: "Curtain",
            segments: [.init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                       .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1),
                       .init(singles: 1, forks: [.init(long: 2, short: 1), .init(long: 1, short: 1)], needed: 3,
                             dangerFoods: 1)],
            worldScreens: 5.5, extraThreats: 2, lapTwoSize: 0.93...0.98, headOnShare: 0.68, heightSwing: 0.5...0.85,
            foodSize: 0.74...0.88, gateMargin: 0.1, dangerGap: 12, threatClearance: 30, spacing: 0.26,
            aiSpeed: 70...200, aiVertical: 100, crossSeconds: 2.48, walledGates: true, timesTheEdge: true,
            jellies: JellySpec(night: true, stingMeals: 4, stingGap: 20, tentacleWalls: true)),
    ]

    /// Playtested Jelly Bloom 2 levels whose shipped plans are kept exactly as played (see `reefLabFrozen`).
    /// Level 10 is the plan first played there, with one big fish (21) started 30 points lower and 500 ahead
    /// so it no longer hovers over the bell that splits its late fork, and fish 20 started 150 earlier so it has
    /// passed that bell before the fork reaches it. The bonus levels (11 on) were played as first planned; each
    /// leaves this set while it's reworked and rejoins once it's played again.
    static let jellyLabFrozen: Set<String> = Set(jellyLabSpecs.map(\.name))

    // MARK: Kelp Forest

    /// Kelp Forest's levels: fish appear just off screen right before you meet them (`MeetingPlanner.kelpPlan`),
    /// so these plan in milliseconds at launch rather than shipping as data. They follow Shallow Reef's ten
    /// levels, already tuned for difficulty, with kelp columns closing in as they go.
    /// Levels 11-15 are its Deep End, following the other worlds' (Crossroads, Frenzy, Gauntlet, Heavyweights,
    /// Needle) with kelp denser than level 10's.
    static let kelpSpecs: [MeetingSpec] = (0..<15).map { index in
        var spec = reefLabSpecs[index]
        spec.name = "Kelp Forest \(index + 1)"
        spec.kelp = kelpRamp[index]
        return spec
    }
    /// Levels 1, 5, and 10 were played and liked (first wins on tries 1, 4, and 17); the levels between step
    /// evenly from one to the next.
    static let kelpRamp: [KelpSpec] = {
        let anchors = [(level: 0, kelp: KelpSpec(columns: 0.35, gap: 1.1)), (level: 4, kelp: KelpSpec(columns: 0.55, gap: 0.6)),
                       (level: 9, kelp: KelpSpec(columns: 0.75, gap: 0.35))]
        let main = (0..<10).map { index in
            if let anchor = anchors.first(where: { $0.level == index }) { return anchor.kelp }
            let (a, b) = index < anchors[1].level ? (anchors[0], anchors[1]) : (anchors[1], anchors[2])
            let t = Double(index - a.level) / Double(b.level - a.level)
            return KelpSpec(columns: a.kelp.columns + (b.kelp.columns - a.kelp.columns) * t,
                            gap: a.kelp.gap + (b.kelp.gap - a.kelp.gap) * t)
        }
        // The Deep End: about 65% to 77% kelp.
        return main + [KelpSpec(columns: 0.7, gap: 0.38), KelpSpec(columns: 0.75, gap: 0.32), KelpSpec(columns: 0.8, gap: 0.3),
                       KelpSpec(columns: 0.75, gap: 0.3), KelpSpec(columns: 0.85, gap: 0.25)]
    }()
    /// Kelp Forest's levels as the game plays them: from `KelpPlans.json` for the frozen ones, otherwise planned
    /// in code at launch. See "Level design: iterate in code, freeze before publishing" in AGENTS.md.
    static let kelpLevels: [Level] = {
        let saved = savedPlans("KelpPlans")
        return kelpSpecs.enumerated().map { index, spec in
            savedLevel(spec, index: index, saved: saved, usesSaved: kelpFrozen.contains(spec.name), planner: .kelp)
        }
    }()
    /// Played and approved, so shipped exactly as saved in `KelpPlans.json`: a planner change can't alter them.
    /// Take a level out of this set (with Kraig's OK) to tune it in code again, then regenerate the file.
    static let kelpFrozen: Set<String> = Set(kelpSpecs.map(\.name))

    #if DEBUG
    /// A Kelp Forest level planned in code: its re-roll if it has one, otherwise the first layout (the Deep End
    /// searching for one with no planner complaints and no wall of giants), with its hand tweaks applied.
    static func kelpPlan(_ index: Int) -> MeetingPlan {
        let spec = kelpSpecs[index]
        if let variation = kelpRerolls[spec.name] { return MeetingPlanner.kelpPlan(spec, variation: variation) }
        guard ArcadeWorld.isDeepEnd(index) else { return MeetingPlanner.kelpPlan(spec) }
        return (0..<16).lazy.map { MeetingPlanner.kelpPlan(spec, variation: $0) }.first { $0.issues.isEmpty && !$0.hasGiantWall }
            ?? MeetingPlanner.kelpPlan(spec)
    }
    #endif
    /// A wall of giants: threats this big alongside you at the same time, leaving no gap this tall (screen
    /// points: room for you at the size you'd be) anywhere in the water.
    static let giantRadius: CGFloat = 60
    static let giantWallGap: CGFloat = 80
    /// Levels re-rolled to another layout of the same settings. Kelp Forest 9's first had two giants just under
    /// the biggest you can grow in the opening; whichever ate first was out of reach for good.
    /// The Deep End is pinned to the layouts Kraig played (the first each with no planner complaints and no wall of
    /// giants), so launch doesn't search for them; 15 is also the layout whose opening he likes.
    static let kelpRerolls: [String: Int] = ["Kelp Forest 9": 3, "Kelp Forest 11": 0, "Kelp Forest 12": 1,
                                             "Kelp Forest 13": 3, "Kelp Forest 14": 0, "Kelp Forest 15": 0]
    /// Fish made a different size by hand. Kelp Forest 15's gate 21 needed six meals with no slack; Kraig found
    /// a way through with five (1, 3, 7, 11, 14: radius 31.8) and wants that to eat it. Four stay too few (28.2).
    static let kelpFishRadius: [String: [Int: CGFloat]] = ["Kelp Forest 15": [21: 31]]
    /// Big fish that swim at you instead of the way you're going, in levels where two you'd overtake slowly
    /// walled you in. Same meetings: a fish swimming at you just passes in a moment. Kelp Forest 8: fish 13
    /// hung over the low lane while you caught up with fish 16 along the floor.
    static let kelpSwimsAtYou: [String: Set<Int>] = ["Kelp Forest 8": [13, 16]]
    /// Screen points beyond the edge of the screen where a Kelp Forest fish appears.
    static let kelpAppearMargin: CGFloat = 30
    /// It follows its approach until you're this many screens past its meeting, then roams like any fish.
    static let kelpApproachReleaseScreens: CGFloat = 0.15
    /// Approaches (screen points): how far a meal glides into its meeting height from above or below, and
    /// how far it weaves either way, settling as it reaches you. Big fish move this share as much.
    static let kelpGlideHeight: ClosedRange<CGFloat> = 60...140
    static let kelpWeaveHeight: ClosedRange<CGFloat> = 24...44
    static let kelpWeaves: ClosedRange<CGFloat> = 0.7...1.5
    static let kelpBigFishApproachShare: CGFloat = 0.45
    /// A turning fish swims away from you at this share of your starting speed, then turns toward you this
    /// many seconds before the meeting.
    static let kelpTurnAwaySpeed: ClosedRange<CGFloat> = 0.45...0.7
    static let kelpTurnBefore: ClosedRange<CGFloat> = 0.55...0.9
    /// Columns start this many screens into the lap, so you start in open water, and stop as far before its end.
    static let kelpFirstColumnScreens: CGFloat = 0.8
    /// Kelp grows from this far below the bottom of the screen, so it's rooted in the seabed.
    static let kelpRootY: CGFloat = -14
    /// Columns reach this far above the top of the screen.
    static let kelpCanopy: CGFloat = 30
    /// Inside kelp you rise and fall at this share of your usual speed.
    static let kelpDrag: CGFloat = 0.65
    /// Other fish inside kelp darken to this one color, behind the fronds. Each part keeps its own transparency.
    static let kelpSilhouette = SKColor(red: 0.03, green: 0.09, blue: 0.07, alpha: 1)

    // MARK: Midnight Zone

    /// Midnight Zone's ten levels, planned like Kelp Forest's (fish appear just off screen right before you meet
    /// them) with no kelp, following Shallow Reef's levels. Levels 1, 5, and 9 were the trials Kraig played and
    /// liked (Shallow Reef 1, 5, and 10). Between them the levels step through Shallow Reef's in order, skipping
    /// Medium (6), which is close to 5; level 10 is Shallow Reef's hardest again, with a layout of its own.
    /// Levels 11-15 are its Deep End, following the other worlds' (Crossroads, Frenzy, Gauntlet, Heavyweights,
    /// Needle).
    static let midnightSpecs: [MeetingSpec] = [0, 1, 2, 3, 4, 6, 7, 8, 9, 9, 10, 11, 12, 13, 14].enumerated().map { index, source in
        var spec = reefLabSpecs[source]
        spec.name = "Midnight Zone \(index + 1)"
        return spec
    }
    /// The trials were planned as Midnight Zone 1, 2, and 3; levels 5 and 9 keep those layouts.
    static let midnightSeedNames: [String: String] = ["Midnight Zone 5": "Midnight Zone 2", "Midnight Zone 9": "Midnight Zone 3"]
    /// Midnight Zone's levels as the game plays them: from `MidnightPlans.json` for the frozen ones, otherwise
    /// planned in code (`midnightPlan`).
    static let midnightLevels: [Level] = {
        let saved = savedPlans("MidnightPlans")
        return midnightSpecs.enumerated().map { index, spec in
            savedLevel(spec, index: index, saved: saved, usesSaved: midnightFrozen.contains(spec.name), planner: .midnight)
        }
    }()
    /// Levels re-rolled to another layout of the same settings. Midnight Zone 8's first walled gate needed six
    /// meals with none to spare, the only way there a climb-dive-climb-dive through mid-water meals between big
    /// fish; Kraig, playing the high lanes, arrived one gate short every time.
    static let midnightRerolls: [String: Int] = ["Midnight Zone 8": 1]
    /// Fish made a different size by hand. Midnight Zone 13's walled gate 27 (54.3) was a hair bigger than
    /// Kraig's usual ten meals (52.6); the only meal that tied it sat between a giant and a big fish that eats it,
    /// and the route around threaded two giants, so he died there or just after in 22 tries.
    static let midnightFishRadius: [String: [Int: CGFloat]] = ["Midnight Zone 13": [27: 52]]
    /// Fish moved to meet you this many seconds earlier, the rest of the level unchanged. Midnight Zone 14's
    /// big fish 13 swims your way, so you overtake it slowly and it hung in the climb from meal 12 to gate 15;
    /// Kraig reached the gate once in about eight tries. 0.4 s puts it level with meal 12, gone before the climb.
    static let midnightFishEarlier: [String: [Int: CGFloat]] = ["Midnight Zone 14": [13: 0.4]]

    // MARK: Riptide Reef (prototype, Xcode builds only)

    /// Riptide Reef's trial levels: Shallow Reef's levels 1 and 5, and a recipe of its own in Frenzy's style
    /// (`riptideRush`), planned like Midnight Zone's (fish appear just off screen right before you meet them), with
    /// currents running the full height of the water over stretches of the lap, among the level's fish
    /// (`riptideCurrents`), and there every lap. The plan reckons with the currents, so each level keeps
    /// Shallow Reef's rhythm in seconds, every meal as reachable as there; in a current you just cover more water. Its
    /// lap is longer to make room for that.
    static let riptideSpecs: [MeetingSpec] = [reefLabSpecs[0], reefLabSpecs[4], riptideRush].enumerated().map { index, source in
        var spec = source
        spec.name = "Riptide Reef \(index + 1)"
        let speeds = riptideCurrents[index]
        spec.currents = CurrentSpec(speeds: speeds.map(Double.init), seconds: Double(riptideCurrentSeconds),
                                    calmStart: Double(riptideCalmStart), calmBetween: Double(riptideCalmBetween))
        // The extra water the currents cover, at the zoom a lap is usually played at.
        spec.worldScreens += Double(speeds.reduce(0) { $0 + ($1 - 1) } * riptideCurrentSeconds) / spec.crossSeconds / 0.75
        return spec
    }
    /// The hard trial's recipe. Kraig found Shallow Reef 10 with currents "wasn't that hard", and Frenzy (Shallow Reef 12)
    /// borrowed whole played as a copy of it: "I want it to feel like 12, but not be a copy." So Frenzy's feel, quick
    /// meals and four walled gates with a burst to open, in its own run of lanes: the opening burst from a two-meal lane
    /// rather than three lone meals, a short fork before the second gate, and a last gate that takes three meals, not
    /// two. A planner takes a recipe very literally (borrowed whole, the meetings fall at the same moments and nearly
    /// the same heights), so a new feel needs a new recipe.
    static let riptideRush = MeetingSpec(name: "Riptide Rush",
        segments: [.init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3),
                   .init(singles: 2, forks: [.init(long: 1, short: 1)], needed: 2, dangerFoods: 1),
                   .init(singles: 1, forks: [.init(long: 2, short: 1)], needed: 2, dangerFoods: 1),
                   .init(singles: 2, forks: [.init(long: 2, short: 1)], needed: 3, dangerFoods: 1)],
        worldScreens: 6, extraThreats: 3, lapTwoSize: 0.93...0.98, headOnShare: 0.72, heightSwing: 0.45...0.85,
        foodSize: 0.66...0.8, gateMargin: 0.15, dangerGap: 24, threatClearance: 38, spacing: 0.21,
        aiSpeed: 64...186, aiVertical: 93, crossSeconds: 2.57, walledGates: true, timesTheEdge: true)
    /// Each trial's currents, in order along the lap, times your pace, every one carrying you forward. Easy three,
    /// medium four, hard three: more in the early levels, with their easier fish, since the currents are the fun.
    /// Kraig (2026-10-11), after narrow channels "just aren't doing it": "full height, and just slip into a fast
    /// current"; (2026-10-12) "speeding up through a section is really fun. Slowing down is not", and "we need more
    /// riptides in the earlier levels... the number of currents should be higher. That's the fun part."
    static let riptideCurrents: [[CGFloat]] = [Array(repeating: riptideWithYou, count: 3),
                                               Array(repeating: riptideWithYou, count: 4),
                                               Array(repeating: riptideWithYou, count: 3)]
    static let riptideWithYou: CGFloat = 1.45
    /// How long a current lasts at most (seconds of play), the calm water at the start of the lap, and the least calm
    /// water between two currents. Between the calm start and your last meeting (8 to 10 seconds in), each current
    /// has an even slot. A level whose currents don't fit says so.
    static let riptideCurrentSeconds: CGFloat = 2
    static let riptideCalmStart: CGFloat = 1.5
    static let riptideCalmBetween: CGFloat = 0.6
    /// Levels re-rolled to another layout of the same settings: one line to try another. Riptide Reef 3's first had a
    /// wall Kraig couldn't get through ("the furthest runs all died in the same spot"): a big fish placed beside one
    /// meal sat on the way to the next walled gate, leaving 7% of the water open at the tightest moment, in a current;
    /// Frenzy's tightest is 10.5%. Layout 4's is 15%, as tight as Gauntlet's and Needle's.
    static let riptideRerolls: [String: Int] = ["Riptide Reef 3": 4]
    #if DEBUG
    /// Each level is its re-roll, or the first layout with no planner issues.
    static let riptideLevels: [Level] = riptideSpecs.indices.map { index in
        let spec = riptideSpecs[index]
        let plan = riptideRerolls[spec.name].map { MeetingPlanner.kelpPlan(spec, variation: $0) }
            ?? (0..<16).lazy.map { MeetingPlanner.kelpPlan(spec, variation: $0) }.first { $0.issues.isEmpty }
            ?? MeetingPlanner.kelpPlan(spec)
        var level = plan.level
        level.ecosystemSeedIndex = index
        return level
    }
    static var riptideLevelCount: Int { riptideSpecs.count }
    #else
    /// A prototype isn't part of the shipped game.
    static let riptideLevels: [Level] = []
    static var riptideLevelCount: Int { 0 }
    #endif
    static let currentEase: CGFloat = 4
    /// Fish this small or smaller (radius; you start at 16) are swept along by a current once they've met you; bigger
    /// ones swim straight through.
    static let currentSweepsRadius: CGFloat = 24
    /// The streaks that show a current flowing: how many per current and their speed across the screen (points/s).
    static let currentStreaks = 16
    static let currentStreakSpeed: CGFloat = 140
    /// The camera lags a current so the speed reads as yours: your fish slides this share of the screen's width
    /// ahead per unit of extra pace (1.45 → about a sixth of the screen). Going back it barely moves, so fish
    /// still appear off screen (`kelpAppearMargin`).
    static let currentSurgeAhead: CGFloat = 0.35
    static let currentSurgeBack: CGFloat = 0.08
    /// Bubbles off your fish in a current: a wake off your tail in a fast one, water rushing past from your face
    /// in a slow one. Most bubbles per second at a full current, and their speed across the screen.
    static let currentBubbles: CGFloat = 70
    static let currentBubbleSpeed: CGFloat = 220
    /// Played and approved, so shipped exactly as saved in `MidnightPlans.json`: a planner change can't alter them.
    /// All fifteen (Kraig, 2026-10-09: "lock in the midnight levels", then "I played 14 and 15 and approve").
    static let midnightFrozen: Set<String> = Set(midnightSpecs.map(\.name))
    #if DEBUG
    /// A Midnight Zone level planned in code: its re-roll if it has one, otherwise the first layout with no planner
    /// issues and no wall of giants.
    static func midnightPlan(_ index: Int) -> MeetingPlan {
        let spec = midnightSpecs[index], seedName = midnightSeedNames[spec.name]
        if let variation = midnightRerolls[spec.name] { return MeetingPlanner.kelpPlan(spec, variation: variation, seedName: seedName) }
        return (0..<16).lazy.map { MeetingPlanner.kelpPlan(spec, variation: $0, seedName: seedName) }
            .first { $0.issues.isEmpty && !$0.hasGiantWall } ?? MeetingPlanner.kelpPlan(spec, seedName: seedName)
    }
    #endif
    /// The dark multiplies everything outside your headlamp by this color: dim, not pitch black. Kraig's plays:
    /// a bit darker than 0.12, 0.15, 0.26, then with the lures, even darker than 0.07, 0.09, 0.17.
    static let midnightDark = SKColor(red: 0.035, green: 0.045, blue: 0.09, alpha: 1)
    /// Every other fish carries an anglerfish lure: one small light, the same for every fish, glowing over the dark,
    /// so you see where each fish is but not how big it is until your beam lands on it. False for plain dark.
    static let anglerLures = true
    static let lureColor = SKColor(red: 0.62, green: 1, blue: 0.86, alpha: 1)
    /// The lure's bright core and its soft halo (radii in screen points, the same for every fish).
    static let lureCore: CGFloat = 3
    static let lureHalo: CGFloat = 12
    /// The headlamp's beam: half its width (radians), and how far it reaches as a share of the screen's width.
    static let headlampHalfAngle: CGFloat = 0.3
    static let headlampReach: CGFloat = 0.8
    /// The beam tilts with you, up to this far (radians) at full rising or falling speed, so diving or climbing
    /// fast leaves the far right of the screen dark.
    static let headlampMaxTilt: CGFloat = 0.6
    /// A soft glow around your head, as a share of the beam's reach, so a fish right beside you is never invisible.
    static let headlampGlow: CGFloat = 0.14

    // MARK: Sunset Cove (world 4)

    /// Sunset Cove's fifteen levels, ten and the Deep End: Shallow Reef's, borrowed by index as Kelp Forest borrows them,
    /// planned like Midnight Zone's (fish appear just off screen right before you meet them), with baited hooks hung
    /// from boats around the meetings (`sunsetHooks`). Planned in code at launch while they're being played; not frozen.
    static let sunsetSpecs: [MeetingSpec] = (0..<15).map { index in
        var spec = reefLabSpecs[index]
        spec.name = "Sunset Cove \(index + 1)"
        spec.hooks = sunsetHooks[index]
        return spec
    }
    /// The three trials (Shallow Reef's 2, 5, and 9) were planned as Sunset Cove 1, 2, and 3, and Kraig's daughters loved
    /// them; levels 2, 5, and 9 keep those fish layouts (their hooks follow `sunsetHooks`).
    static let sunsetSeedNames: [String: String] = ["Sunset Cove 2": "Sunset Cove 1", "Sunset Cove 5": "Sunset Cove 2",
                                                    "Sunset Cove 9": "Sunset Cove 3"]
    /// Each level's hooks. Every level hangs some near your way from the start, each level brings in one new thing,
    /// and the Deep End hangs more hooks nearer your way with the bait closer to your size. Kraig (2026-10-12): "levels
    /// 8-10 were great. But I think I made it through 1-7 without getting hooked a single time. I think we're playing
    /// it a little too safe on those": levels 1 to 3 hung every hook well off your way (70 to 50 points clear), and 4
    /// to 7 most of them. Now 1 to 7 hang two to four near the meal lanes, with 45 points clear at first, down to 28
    /// by 7, as at 8. `nearLanes` hooks hang as
    /// near the meal lanes as is fair, so you time them or pick a lane; `besideMeals` bait hangs beside a real meal its
    /// size, where a meal has a fair spot beside it (the Deep End hangs one to three); the gate is two hooks near the
    /// end, one above your way and one below. `clearance` is the water (screen
    /// points) every hook keeps from your way from meal to meal.
    static let sunsetHooks: [HookSpec] = [
        // 1: three still hooks, two near your way: the bait is plain to see, and close enough to tempt you.
        HookSpec(still: 3, nearLanes: 2, baitSize: 0.55, clearance: 45),
        // 2, the easy trial: four.
        HookSpec(still: 4, nearLanes: 3, baitSize: 0.58, clearance: 40),
        // 3: hooks reeled slowly up and down.
        HookSpec(still: 2, bobbing: 2, nearLanes: 3, baitSize: 0.6, clearance: 36),
        // 4: more of them, nearer.
        HookSpec(still: 2, bobbing: 3, nearLanes: 4, baitSize: 0.62, clearance: 33),
        // 5, the medium trial.
        HookSpec(still: 2, bobbing: 3, nearLanes: 4, baitSize: 0.62, clearance: 30),
        // 6: a boat trolling its hook toward you.
        HookSpec(still: 2, bobbing: 2, trolling: 1, nearLanes: 4, baitSize: 0.64, clearance: 29),
        // 7: bait beside a real meal.
        HookSpec(still: 1, bobbing: 2, trolling: 2, besideMeals: 1, nearLanes: 4, baitSize: 0.66, clearance: 28),
        // 8: the gate.
        HookSpec(still: 2, bobbing: 2, gate: true, nearLanes: 3, baitSize: 0.66, clearance: 28),
        // 9, the hard trial: all of it.
        HookSpec(still: 1, bobbing: 2, trolling: 2, gate: true, besideMeals: 2, nearLanes: 3, baitSize: 0.7, clearance: 24),
        // 10: all of it, a little more.
        HookSpec(still: 2, bobbing: 2, trolling: 2, gate: true, besideMeals: 2, nearLanes: 4, baitSize: 0.72, clearance: 22),
        // The Deep End.
        HookSpec(still: 2, bobbing: 3, trolling: 2, gate: true, besideMeals: 2, nearLanes: 4, baitSize: 0.72, clearance: 22),
        HookSpec(still: 1, bobbing: 3, trolling: 3, gate: true, besideMeals: 3, nearLanes: 4, baitSize: 0.74, clearance: 20),
        HookSpec(still: 2, bobbing: 2, trolling: 3, gate: true, besideMeals: 3, nearLanes: 5, baitSize: 0.74, clearance: 20),
        // 14 and 15 are short (about ten seconds), so fewer hooks fit: tighter and bigger instead.
        HookSpec(still: 2, bobbing: 2, trolling: 2, gate: true, besideMeals: 3, nearLanes: 5, baitSize: 0.76, clearance: 18),
        HookSpec(still: 1, bobbing: 2, trolling: 3, gate: true, besideMeals: 3, nearLanes: 5, baitSize: 0.78, clearance: 18),
    ]
    /// Levels re-rolled to another layout of the same settings, fish and hooks both (`MeetingPlanner.kelpPlan`'s
    /// variation): one line to try another. Sunset Cove 10 is pinned to the layout Kraig loves ("might be my favorite
    /// level yet... it's near perfection"), so its fish tweaks below can't pick another.
    static let sunsetRerolls: [String: Int] = ["Sunset Cove 10": 9]
    /// Fish made a different size by hand. In Sunset Cove 10 the two giants ate the medium fish meant for your lap
    /// two in every one of Kraig's 52 runs (10 ate 6 and 11, 16 ate 15), finishing at 76.9 and 75.8, just over the
    /// 74.5 a run that eats everything reaches; his one run through ate a spare fish. They start smaller, so after
    /// those meals they're the sizes the level was designed for (70.3, 69): giants all through lap one, edible at the
    /// end.
    static let sunsetFishRadius: [String: [Int: CGFloat]] = ["Sunset Cove 10": [10: 63, 16: 61.5]]
    /// Trolling hooks retimed by hand, numbered in the order you pass them, to be at the top of their sweep as you pass
    /// (`HookLayout.sweptHigh`). In Sunset Cove 15 (Kraig, 2026-10-12: "might be impossible") the giant over you and
    /// the big fish coming at you under it leave only the floor, and the fourth hook's bait was at the bottom of its sweep
    /// just then, filling it: his 30-odd runs all ended there. The hooks are hung clear of the level's reference route,
    /// which goes up for the top fish, but the giant swimming along with you shuts that water first.
    static let sunsetHooksSweptHigh: [String: Set<Int>] = ["Sunset Cove 15": [4]]
    /// Played and approved, so they play exactly as saved in `SunsetPlans.json`: a planner change can't alter them.
    /// Sunset Cove 10 (Kraig, 2026-10-12, after its giants were sized to finish edible: "perfect. let's freeze level
    /// 10"), 11 ("11 is incredible"), 12 to 14 ("levels 10-14 on sunset cove are great"), and 15, once its last big fish
    /// had open water under it ("sunset 15 can be frozen. it's great"). Take a level out of this set (with Kraig's OK) to
    /// tune it in code again, then regenerate the file.
    static let sunsetFrozen: Set<String> = ["Sunset Cove 10", "Sunset Cove 11", "Sunset Cove 12", "Sunset Cove 13", "Sunset Cove 14",
                                            "Sunset Cove 15"]
    /// Sunset Cove's levels as the game plays them: from `SunsetPlans.json` for the frozen ones, otherwise planned in
    /// code (`sunsetPlan`) in Xcode builds. Release builds play the saved file for every level, so regenerate it after
    /// any change, and freeze every level before publishing.
    static let sunsetLevels: [Level] = {
        let saved = savedPlans("SunsetPlans")
        return sunsetSpecs.enumerated().map { index, spec in
            savedLevel(spec, index: index, saved: saved, usesSaved: sunsetFrozen.contains(spec.name), planner: .sunset)
        }
    }()
    static var sunsetLevelCount: Int { sunsetSpecs.count }
    #if DEBUG
    /// A Sunset Cove level planned in code: its re-roll if it has one, otherwise the first layout with every hook hung,
    /// no other planner issues, and no wall of giants.
    static func sunsetPlan(_ index: Int) -> MeetingPlan {
        let spec = sunsetSpecs[index], seedName = sunsetSeedNames[spec.name]
        if let variation = sunsetRerolls[spec.name] { return MeetingPlanner.kelpPlan(spec, variation: variation, seedName: seedName) }
        return (0..<16).lazy.map { MeetingPlanner.kelpPlan(spec, variation: $0, seedName: seedName) }
            .first { $0.issues.isEmpty && !$0.hasGiantWall } ?? MeetingPlanner.kelpPlan(spec, seedName: seedName)
    }
    #endif
    /// No hook is passed before this many screens into the lap, so each one swims in from the right with its boat.
    static let sunsetFirstHookScreens: CGFloat = 1.1
    /// Seconds between passing one hook and the next (the gate's two count as one). Hooks spread out along the lap,
    /// each in its own stretch where there's room; this pulls one that strays back toward its stretch.
    static let sunsetHookSpacing: CGFloat = 0.85
    static let sunsetStretchPull: CGFloat = 200
    /// The gate's lower hook is passed this long after its upper one, so their lines hang apart; the gate comes once
    /// this share of the reference route's meals is behind you. Its hooks keep clear of your way `sunsetGateWindow`
    /// seconds either side of passing them (tighter than other hooks' `sunsetPassWindow`: it's a gate).
    static let sunsetGateStagger: CGFloat = 0.12
    static let sunsetGateFrom: CGFloat = 0.55
    static let sunsetGateWindow: CGFloat = 0.1
    /// Fairness: every hook keeps this far (screen points beyond both bodies) from every reference meal's meeting,
    /// either along the way or above or below it, when you meet that meal...
    static let sunsetMealClearance: (distance: CGFloat, height: CGFloat) = (distance: 90, height: 30)
    /// ...and stays clear of your way this many seconds before and after you pass it, for a player a little off the plan.
    /// Your way is wherever you could be between one reference meal and the next, swimming up or down as fast as you can.
    static let sunsetPassWindow: CGFloat = 0.25
    /// An open hook hangs at least this far from your way where it can (screen points); past that, nearer mid-water wins.
    static let sunsetOpenGap: CGFloat = 90
    /// Bait beside a meal hangs this far from it (screen points between the bodies).
    static let sunsetBesideGap: CGFloat = 30
    /// The smallest bait (radius, world points), so it's always plain to see.
    static let sunsetSmallestBait: CGFloat = 9
    /// Bobbing hooks: reeled this many screen points up and back down, over this many seconds.
    static let sunsetBobRange: CGFloat = 70
    static let sunsetBobSeconds: CGFloat = 3.6
    /// Trolling hooks: the boat motors toward you at this many screen points a second; its hook trails this far behind
    /// it and sweeps up and down this far either way, over this many seconds.
    static let sunsetTrollSpeed: CGFloat = 45
    static let sunsetTrollTrail: CGFloat = 60
    static let sunsetTrollSweep: CGFloat = 40
    static let sunsetTrollSweepSeconds: CGFloat = 6
    /// Once you've passed a hook, its boat reels the line up so the bait hangs just under the surface for the rest of
    /// the level: every boat stays and still fishes up top, but the water below is yours for the clean-up, when you're
    /// big. The hooks are planned around your first pass, so later laps only met them by chance (Kraig, Sunset Cove 13:
    /// "the late game with all the hooks is really hard. You can't really dive in and out because you're so big and the
    /// hooks are so close"). The reel-up starts this many seconds after the hook, boat and all, has gone off the left of
    /// your screen (by how far you've come, not the planned route's timing), takes this long, and leaves the bait's
    /// middle this many screen points under the surface.
    static let sunsetReelUpAfter: CGFloat = 0.3
    static let sunsetReelUpSeconds: CGFloat = 2
    static let sunsetReeledDepth: CGFloat = 35
    /// What catches you, as shares of the bait's radius: the bait's body, and the hook's bend under it. Your body counts
    /// at `hazardHitboxScale`, as it does against tentacles. The line never does.
    static let sunsetBaitHitScale: CGFloat = 0.9
    static let sunsetHookHitShare: CGFloat = 0.3
    /// Room a hook keeps from the floor, and from its boat's hull (world points at zoom 1).
    static let sunsetFloorRoom: CGFloat = 12
    static let sunsetSurfaceRoom: CGFloat = 8
    /// Caught, you're reeled up the line and out of the water over this many seconds; the result comes this long after
    /// you're caught.
    static let sunsetReelSeconds: CGFloat = 0.8
    static let sunsetReelResultDelay: CGFloat = 1.15
    /// How far the bait wriggles on its hook (radians either way).
    static let sunsetBaitWiggle: CGFloat = 0.16
    /// The boats, at zoom 1 (screen points): hull length and how deep it sits.
    static let sunsetBoatLength: CGFloat = 104
    static let sunsetBoatDraft: CGFloat = 20
    static let sunsetBoatColor = SKColor(red: 0.21, green: 0.06, blue: 0.2, alpha: 0.96)
    static let sunsetLineColor = SKColor(red: 1, green: 0.95, blue: 0.9, alpha: 0.8)
    /// The low sun glowing at the surface (share of the screen's width), and how far its rays drift as you swim
    /// (share of your own speed on screen).
    static let sunsetSunX: CGFloat = 0.72
    static let sunsetRayParallax: CGFloat = 0.08

    /// Jelly Bloom 2's levels, planned on the Mac and shipped as data (`JellyLabPlans.json`), like Reef Lab's.
    static let jellyLabLevels: [Level] = plannedLevels(jellyLabSpecs, file: "JellyLabPlans")

    /// Planned levels from a bundled plan file, which holds every level's current plan (whichever variation was
    /// shipped for a spec; a level replanned as another layout ships that one). In Xcode builds a spec newer than
    /// the file is planned on first use instead.
    private static func plannedLevels(_ specs: [MeetingSpec], file: String) -> [Level] {
        let saved = savedPlans(file)
        return specs.enumerated().map { index, spec in
            savedLevel(spec, index: index, saved: saved, usesSaved: true, planner: .meetings)
        }
    }

    /// A world's saved plans: `<file>.json` in the app. A file that's missing or won't load is a broken build, so
    /// this stops right there, loudly, rather than quietly planning every level again into layouts nobody played.
    static func savedPlans(_ file: String) -> [MeetingPlan] {
        guard let url = Bundle.main.url(forResource: file, withExtension: "json") else { fatalError("\(file).json isn't in the app") }
        do {
            return try JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: url))
        } catch {
            fatalError("\(file).json didn't load: \(error)")
        }
    }

    /// How Xcode builds plan a level in code: Reef Lab and Jelly Bloom 2 straight from the planner, Kelp Forest,
    /// Midnight Zone, and Sunset Cove with their re-rolls and hand tweaks (`kelpPlan`, `midnightPlan`, `sunsetPlan`).
    private enum Planner { case meetings, kelp, midnight, sunset }

    /// The level `spec` plays, `index` in its world. The shipped game plays its saved plan and never plans on the
    /// device: the planner is in Xcode builds only, so a level with no saved plan stops a Release build at launch
    /// (freeze every level before publishing, AGENTS.md). Xcode builds plan it in code instead when it isn't saved,
    /// or when `usesSaved` is false (a level being tuned in code).
    private static func savedLevel(_ spec: MeetingSpec, index: Int, saved: [MeetingPlan], usesSaved: Bool,
                                   planner: Planner) -> Level {
        let savedPlan = saved.first { $0.spec == spec }
        #if DEBUG
        let plan = (usesSaved ? savedPlan : nil) ?? {
            switch planner {
            case .meetings: MeetingPlanner.plan(spec)
            case .kelp: kelpPlan(index)
            case .midnight: midnightPlan(index)
            case .sunset: sunsetPlan(index)
            }
        }()
        #else
        guard let plan = savedPlan else { fatalError("\(spec.name) has no saved plan: freeze every level before publishing") }
        #endif
        var level = plan.level
        level.ecosystemSeedIndex = index
        return level
    }

    /// Reef Lab's levels, planned on the Mac and shipped as data so no device plans them while you play.
    /// Regenerate with the `reef-lab-plans.request` marker (MeetingPlannerTests) after changing the specs or
    /// the planner; a test fails while the file is out of date. A spec that's newer than the file is planned
    /// on first use instead.
    static let reefLabLevels: [Level] = plannedLevels(reefLabSpecs, file: "ReefLabPlans")
    /// Shallow Reef's levels in play order: which Reef Lab level plays in each slot. Testers' 0.1 numbers (win
    /// rate, median tries to a first clear) had levels 3 and 4 harder than 5 and 6, and level 8 a wall (1%, 21+
    /// tries) harder than Hard at 10, so Kraig reordered them (2026-10-09): 5 and 6 play third and fourth, 3 and
    /// 4 fifth and sixth, Hard eighth, and level 8 is the finale. Saves key levels by slot, so every clear
    /// stays; each layout keeps its own setup number in the stats (`ecosystemSeedIndex`). Kelp Forest and
    /// Midnight Zone follow `reefLabSpecs` by index and don't change.
    static let shallowReefOrder = [0, 1, 4, 5, 2, 3, 6, 9, 8, 7, 10, 11, 12, 13, 14]
    static let shallowReefLevels: [Level] = shallowReefOrder.map { reefLabLevels[$0] }

    // MARK: First-launch tutorial (`ArcadeTutorial`)

    /// Its fish (radius; you start at `baseRadius`, 16). The first meal takes you to 18.4; the fish you miss (14)
    /// eats two little ones (12) and reaches 20.7, clearly bigger than you; the last meal is sized so you end
    /// `tutorialCatchMargin` times its size (a meal of 14.2, taking you to 22.4).
    static let tutorialFirstMeal: CGFloat = 10
    static let tutorialBigFish: CGFloat = 40
    static let tutorialMissedFish: CGFloat = 14
    static let tutorialMissedFishMeal: CGFloat = 12
    static let tutorialCatchMargin: CGFloat = 1.08
    /// How fast the whole tutorial plays: its fish swim their paths, and you swim forward, at this share of the
    /// timings below (rising and falling are as fast as ever). Lower is slower.
    static let tutorialPace: CGFloat = 0.75
    /// A slow, roomy level whose fish can eat each other, with no fish of its own: the beats bring theirs.
    static let tutorialLevel = Level(aiSpeedRange: 40...90, aiVerticalSpeed: 50,
                                     screenCrossSeconds: 3.2 / tutorialPace, absorptionEfficiency: 0.9)
    /// At a pace of 1: seconds a fish swimming straight at you takes to reach you, the glowing meals and the big fish.
    static let tutorialMealCrossing: CGFloat = 1.7
    static let tutorialBigFishCrossing: CGFloat = 2.0
    /// The race, at a pace of 1, in screens a second as they look on screen (you swim a screen every 3.2 s, so anything
    /// slower than 1 / 3.2 would look to swim backwards). The missed fish sets off `tutorialMissedFishSets` seconds in,
    /// its two little meals ahead of it and slower, and it catches them this many screens ahead of you: both well
    /// to the right, so it's done eating and growing, and you see it at its new size, before it swims off past you.
    /// Then it comes round again from ahead of you `tutorialWrapDelay` seconds into the next beat (and after each time
    /// it gets past you).
    static let tutorialMissedFishSpeed: CGFloat = 0.5
    static let tutorialMissedMealSpeed: CGFloat = 0.36
    static let tutorialMissedFishSets: CGFloat = 0.9
    static let tutorialMissedCatches: [CGFloat] = [0.5, 0.26]
    static let tutorialWrapDelay: CGFloat = 1.2
    /// The wall, the last beat, plays like a level: two meals and then the wall swim freely ahead of you, and the wall
    /// eats you if you reach it before you've eaten both. Its three fish are `tutorialWallSize` times you, and the two
    /// meals make you `tutorialWallMargin` times them (one isn't enough).
    static let tutorialWallSize: CGFloat = 1.17
    static let tutorialWallMargin: CGFloat = 1.06
    /// Each meal, in the order you meet it: where it starts (screens ahead of you, share of the water), how far up or
    /// down from there it wanders (share of the water), which way it swims (-1 at you, 1 away, so you chase it), and how
    /// fast (points a second, a little faster and slower as it goes). Both are well off screen when the beat starts.
    static let tutorialWallMeals: [TutorialSwim] = [
        TutorialSwim(ahead: 0.9, home: 0.66, wander: 0.1, heading: -1, speed: 28),
        TutorialSwim(ahead: 1.5, home: 0.33, wander: 0.1, heading: 1, speed: 32),
    ]
    /// How fast a meal wanders up and down (points a second): gently, so it's easy to line up with.
    static let tutorialMealWander: CGFloat = 26
    /// The wall starts this many screens ahead of you and swims at you at a steady `tutorialWallSwim` points a second, its
    /// three fish side by side (staggered, you could slip past one and then duck the next), each bobbing
    /// `tutorialWallBob` points as it comes. It comes into view while you're still after the second meal, and you
    /// reach it about two seconds after eating it.
    static let tutorialWallAhead: CGFloat = 2.48
    static let tutorialWallSwim: CGFloat = 18
    static let tutorialWallBob: CGFloat = 4
    /// Through the wall, its other two fish (smaller than you now) turn and bolt ahead at `tutorialFleeDash` times your
    /// speed, one for each of `tutorialFleeDashes` seconds, so they're strung out ahead of you, then tire to
    /// `tutorialFleeSpeed` points a second (slower than you) for you to catch them one at a time. One that gets past you
    /// comes round again from ahead.
    static let tutorialFleeDash: CGFloat = 1.6
    static let tutorialFleeDashes: [CGFloat] = [1.1, 1.9]
    static let tutorialFleeSpeed: CGFloat = 45
    /// How far apart the wall's top and bottom fish are, as a share of the water (two thirds would space all three
    /// evenly). Any wider and, with them bobbing, you could slip between them.
    static let tutorialWallSpread: CGFloat = 0.64
    /// The camera stays at its starting zoom through the tutorial (rather than easing out as you grow), so three fish
    /// can wall off the water and everything reads large.
    static let tutorialZoom: CGFloat = 1
    /// The size of each beat's line at the top of the screen.
    static let tutorialCaptionSize: CGFloat = 30
    /// The first two beats: holding has to lift you this share of the water above your lowest (a short hold does it;
    /// you don't need to reach the top, and a few short taps add up), and letting go has to drop you this share from your
    /// highest. The finger shows again if you haven't after `tutorialHintSeconds`. It presses here (shares of the
    /// screen), open water well away from your fish.
    static let tutorialRiseShare: CGFloat = 0.15
    static let tutorialFallShare: CGFloat = 0.22
    static let tutorialHintSeconds: CGFloat = 3.5
    static let tutorialFingerSpot = CGPoint(x: 0.68, y: 0.42)
    /// The race: the missed fish and its meals swim in this lane (share of the water), just under the line at the top
    /// so you can read it and watch; you glide down to `tutorialHeldShare` and hold there while it eats.
    static let tutorialRaceLane: CGFloat = 0.72
    static let tutorialHeldShare: CGFloat = 0.28
    static let tutorialHeldGlide: CGFloat = 220
    /// After the last catch: when its closing line fades in, and when it leaves for the map (seconds, real time).
    static let tutorialFinaleDelay: CGFloat = 0.5
    static let tutorialFinaleSeconds: CGFloat = 2.8

    // MARK: Credits (`CreditsScene`)

    /// A calm swim: you cross a screen every `creditsCrossSeconds` (a level's is about 3.2), and the camera eases out as you
    /// grow, as in a level. Its water is `creditsWorldScreens` wide, so names ahead and behind never meet round the wrap
    /// however far it zooms out. The map's calm track, Tidal Groove, plays on from Settings.
    static let creditsCrossSeconds: CGFloat = 6
    static let creditsWorldScreens: CGFloat = 8
    static let creditsMusic: ArcadeAudio.Music = .menu
    /// Each name is a fish this share of your size when it comes in, every one the same, and eating one adds this share of
    /// its area to you: about 8% bigger a name, so you grow a little each time.
    static let creditsNameSize: CGFloat = 0.62
    static let creditsGrowth: CGFloat = 0.45
    /// Names come in this many screens ahead of you (just off screen), the next once you've swum `creditsSpacing` screens
    /// since the last came in: one at a time, about six seconds apart, the next soon after you meet the last. At most
    /// `creditsInWater` are in the water at once. One more than `creditsMissedBehind` screens behind you was missed: it
    /// comes round again, next in line (no other comes in while it's behind you).
    static let creditsEnterAhead: CGFloat = 0.85
    static let creditsSpacing: CGFloat = 1.05
    static let creditsInWater = 3
    static let creditsMissedBehind: CGFloat = 0.5
    /// How names swim, like the tutorial's free swimmers: on at a speed from `creditsSwimSpeed` (points a second, a little
    /// faster and slower as they go), most of them at you (`creditsAtYouShare`), wandering up and down `creditsWander` of
    /// the water from a height at up to `creditsWanderSpeed`, and turning round every so often (`creditsTurnSeconds`).
    /// They keep above `creditsLowest` of the water, and low enough that their tag fits under the top of the screen.
    /// With Reduce Motion they don't turn, and wander half as far and as fast.
    static let creditsSwimSpeed: ClosedRange<CGFloat> = 22...34
    static let creditsAtYouShare: Double = 0.65
    static let creditsWander: CGFloat = 0.1
    static let creditsWanderSpeed: CGFloat = 24
    static let creditsTurnSeconds: ClosedRange<CGFloat> = 1.5...5
    static let creditsLowest: CGFloat = 0.1
    /// The tag over each name, in points on screen at any zoom: the name, the role line over it, and the gap between the
    /// tag's point and the fish. It stays this far below the top of the screen.
    static let creditsNameFont: CGFloat = 21
    static let creditsRoleFont: CGFloat = 11
    static let creditsTagGap: CGFloat = 3
    static let creditsTagTopMargin: CGFloat = 8
    /// Eaten, a name's tag pops (bursts, or with Reduce Motion fades) over `creditsPopSeconds`, and then "Thanks, Chad H!"
    /// floats up from it this many points as it fades, over this many seconds (in place, with Reduce Motion).
    static let creditsPopSeconds: CGFloat = 0.12
    static let creditsThanksFont: CGFloat = 22
    static let creditsThanksRise: CGFloat = 44
    static let creditsThanksSeconds: CGFloat = 1.7
    /// The end card, this long after the last name.
    static let creditsCardDelay: CGFloat = 1.0
    /// Where each name comes in, which way it swims, and how it looks: the same every time.
    static let creditsSeed: UInt64 = 104
}

struct Level {
    let aiSpeedRange: ClosedRange<CGFloat>
    let aiVerticalSpeed: CGFloat
    /// Seconds for the player to cross one screen width.
    let screenCrossSeconds: CGFloat
    let absorptionEfficiency: CGFloat
    var effectiveAbsorptionEfficiency: CGFloat { absorptionEfficiency * GameTuning.mealGrowthScale }
    var jellies: JellyLayout? = nil
    var aiCanEat: Bool = true
    /// The layout's own number in its world's list of specs, independent of the slot it plays in (analytics' setup).
    var ecosystemSeedIndex: Int? = nil
    var worldScreens: CGFloat = GameTuning.worldScreens
    /// The planned meetings every fish swims to; see docs/meeting-planner.md. Only the tutorial has none.
    var meetingPlan: MeetingPlan? = nil
}
