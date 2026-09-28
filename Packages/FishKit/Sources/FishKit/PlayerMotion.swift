import CoreGraphics

/// Constants for hold-to-rise / release-to-fall movement. Each app owns its values.
public struct MotionTuning {
    /// Upward acceleration while holding (pt/s²).
    public var riseAcceleration: CGFloat
    /// Downward acceleration while released (pt/s²).
    public var fallAcceleration: CGFloat
    /// Exponential vertical damping per second; keeps motion controllable rather than ballistic.
    public var verticalDamping: CGFloat
    public var maxRiseSpeed: CGFloat
    public var maxFallSpeed: CGFloat
    /// Fraction of vertical speed reflected when touching the top or bottom of the water.
    public var boundaryBounce: CGFloat
    /// Maximum nose-up / nose-down tilt in radians.
    public var maxTilt: CGFloat

    public init(
        riseAcceleration: CGFloat, fallAcceleration: CGFloat, verticalDamping: CGFloat,
        maxRiseSpeed: CGFloat, maxFallSpeed: CGFloat, boundaryBounce: CGFloat, maxTilt: CGFloat
    ) {
        self.riseAcceleration = riseAcceleration
        self.fallAcceleration = fallAcceleration
        self.verticalDamping = verticalDamping
        self.maxRiseSpeed = maxRiseSpeed
        self.maxFallSpeed = maxFallSpeed
        self.boundaryBounce = boundaryBounce
        self.maxTilt = maxTilt
    }
}

/// Hold-to-rise / release-to-fall vertical movement.
public enum PlayerMotion {
    /// One step of vertical movement. `zoom` keeps the on-screen feel constant when zoomed out.
    public static func step(
        y: CGFloat, vy: CGFloat, holding: Bool, dt: CGFloat,
        minY: CGFloat, maxY: CGFloat, zoom: CGFloat = 1, tuning t: MotionTuning
    ) -> (y: CGFloat, vy: CGFloat) {
        var vy = vy
        vy += (holding ? t.riseAcceleration : -t.fallAcceleration) / zoom * dt
        vy *= exp(-t.verticalDamping * dt)
        vy = vy.clamped(-t.maxFallSpeed / zoom, t.maxRiseSpeed / zoom)

        var y = y + vy * dt
        if y < minY {
            y = minY
            if vy < 0 { vy = -vy * t.boundaryBounce }
        } else if y > maxY {
            y = maxY
            if vy > 0 { vy = -vy * t.boundaryBounce }
        }
        return (y, vy)
    }
}
