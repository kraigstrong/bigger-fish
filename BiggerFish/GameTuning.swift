import CoreGraphics
import FishKit

/// Every feel-related constant lives here so it can be tweaked quickly between device runs.
enum GameTuning {
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
    /// Radii differing by less than this fraction bump apart instead of eating.
    static let nearEqualThreshold: CGFloat = 0.01
    /// Collision distance = (rA + rB) * collisionScale. Bodies are 1.35r long and 0.95r tall.
    static let collisionScale: CGFloat = 1.05
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
    static let bloomAggroRadius: CGFloat = 220
    static let bloomGiveUpRadius: CGFloat = 340
    static let bloomChaseSeconds: CGFloat = 2.5
    static let bloomChaseTurnRate: CGFloat = 1.1
    static let bloomFloorLanePadding: CGFloat = 20
    /// Predators can intercept from ahead, but cannot run down a fish that has escaped them.
    static let bloomChaseSpeedFraction: CGFloat = 0.75
    static let bloomChaseVerticalFraction: CGFloat = 0.55
    static let bloomChaseReactionSeconds: CGFloat = 0.45
    static let bloomChaseCooldown: CGFloat = 4
    static let bloomAggressiveFraction: CGFloat = 0.6

    /// Ordinary swimmers anticipate curtains; committed chases ignore this steering.
    static let bloomAvoidanceLookAhead: CGFloat = 1.2
    static let bloomAvoidancePadding: CGFloat = 16
    static let bloomAvoidanceRiseSpeed: CGFloat = 140
    static let bloomAvoidanceTurnRate: CGFloat = 8

    static let bloomFoodRefillSeconds: CGFloat = 3
    static let bloomFoodRefillCount = 2
    static let bloomFoodRadiusFraction: ClosedRange<CGFloat> = 0.45...0.65

    /// These remain separate from the five original levels so their feel stays intact.
    static let bloomLevels: [Level] = [
        Level(spawnGroups: [(9, 0.30...0.65), (5, 0.65...0.85)],
              aiSpeedRange: 30...80, aiVerticalSpeed: 35, screenCrossSeconds: 3.1,
              absorptionEfficiency: 0.90,
              jellies: JellyLayout(count: 4, radius: 40, tentacleLength: 70, sway: 6), aiCanEat: false),
        Level(spawnGroups: [(7, 0.30...0.62), (5, 0.62...0.85), (2, 1.15...1.45)],
              aiSpeedRange: 35...95, aiVerticalSpeed: 45, screenCrossSeconds: 3.0,
              absorptionEfficiency: 0.90,
              jellies: JellyLayout(count: 6, tentacleLength: 110, sway: 8, urchinBeds: 3)),
        Level(spawnGroups: [(6, 0.35...0.65), (5, 0.65...0.88), (3, 1.10...1.50), (1, 1.70...1.95)],
              aiSpeedRange: 40...110, aiVerticalSpeed: 60, screenCrossSeconds: 2.85,
              absorptionEfficiency: 0.87,
              jellies: JellyLayout(count: 8, radius: 36, tentacleLength: 100, urchinBeds: 5)),
        Level(spawnGroups: [(6, 0.35...0.65), (5, 0.65...0.88), (3, 1.15...1.55), (2, 1.70...2.05)],
              aiSpeedRange: 45...120, aiVerticalSpeed: 65, screenCrossSeconds: 2.8,
              absorptionEfficiency: 0.86,
              jellies: JellyLayout(count: 6, radius: 36, tentacleLength: 115, urchinBeds: 6, night: true, maintainsFloorLane: true),
              predatorSpawnSeparationScreens: 0.45),
        Level(spawnGroups: [(5, 0.35...0.65), (5, 0.65...0.90), (4, 1.15...1.55), (2, 1.75...2.20)],
              aiSpeedRange: 50...130, aiVerticalSpeed: 72, screenCrossSeconds: 2.7,
              absorptionEfficiency: 0.85,
              jellies: JellyLayout(count: 7, radius: 35, tentacleLength: 125, urchinBeds: 8, maintainsFloorLane: true),
              predatorSpawnSeparationScreens: 0.4),
    ]

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
    var jellies: JellyLayout? = nil
    var aiCanEat: Bool = true
    var requiredMeals: Int = 0
    var predatorSpawnSeparationScreens: CGFloat = 0
}
