import CoreGraphics

/// Every feel-related constant lives here so it can be tweaked quickly between device runs.
enum GameTuning {
    // MARK: Player movement

    /// Seconds for the player to cross one screen width (spec target: 2.5–3 s).
    static let screenCrossSeconds: CGFloat = 2.75
    /// Upward acceleration while holding (pt/s²).
    static let riseAcceleration: CGFloat = 1100
    /// Downward acceleration while released (pt/s²).
    static let fallAcceleration: CGFloat = 1200
    /// Exponential vertical damping per second; keeps motion controllable rather than ballistic.
    static let verticalDamping: CGFloat = 1.2
    static let maxRiseSpeed: CGFloat = 250
    static let maxFallSpeed: CGFloat = 250
    /// Fraction of vertical speed reflected when touching the top or bottom of the water.
    static let boundaryBounce: CGFloat = 0.15
    /// Maximum nose-up / nose-down tilt in radians.
    static let maxTilt: CGFloat = 0.35
    /// Where the player sits horizontally on screen (fraction of width).
    static let playerScreenX: CGFloat = 0.30

    // MARK: World

    static let worldScreens: CGFloat = 4
    static let waterTopMargin: CGFloat = 12
    static let waterBottomMargin: CGFloat = 10

    // MARK: Size and growth

    /// Points of radius for a normalized size of 1.0 (the player's starting size).
    static let baseRadius: CGFloat = 16
    static let absorptionEfficiency: CGFloat = 0.90
    /// Radii differing by less than this fraction bump apart instead of eating.
    static let nearEqualThreshold: CGFloat = 0.01
    /// Collision distance = (rA + rB) * collisionScale. Bodies are 1.35r long and 0.95r tall.
    static let collisionScale: CGFloat = 1.05
    static let growDuration: CGFloat = 0.35
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
    static let aiSpeedRange: ClosedRange<CGFloat> = 35...95
    static let aiVerticalSpeed: CGFloat = 45
    static let aiMaxTilt: CGFloat = 0.15
    static let aiRetargetRange: ClosedRange<CGFloat> = 2...6
    static let aiTurnIntervalRange: ClosedRange<CGFloat> = 8...20

    // MARK: Initial ecosystem

    static let spawnSeed: UInt64 = 20_260_927
    /// Normalized radii (player = 1.0).
    static let spawnGroups: [(count: Int, radii: ClosedRange<CGFloat>)] = [
        (6, 0.30...0.55),
        (5, 0.55...0.80),
        (3, 0.90...1.15),
        (2, 1.35...1.70),
        (1, 2.10...2.50),
    ]
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
}
