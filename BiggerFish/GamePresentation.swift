import CoreGraphics
import FishKit

/// Copies only drawing state. Interpolation never writes back into a live fish.
struct FishPresentation {
    var position: CGPoint
    var velocity: CGVector
    var radius: CGFloat
    var facing: CGFloat
    var pulse: CGFloat
    var squash: CGFloat
    var shrink: CGFloat
    var struggle: CGFloat
    var mouth: CGFloat
    var chew: CGFloat

    init(_ fish: Fish) {
        position = fish.position
        velocity = fish.velocity
        radius = fish.radius
        facing = fish.facing
        pulse = fish.pulse
        squash = fish.squash
        shrink = fish.shrink
        struggle = fish.struggle
        mouth = fish.mouth
        chew = fish.chew
    }

    func interpolated(to current: Self, fraction: CGFloat, world: WrappedWorld) -> Self {
        let t = fraction.clamped(0, 1)
        func blend(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        var pose = current
        pose.position = PresentationInterpolation.position(from: position, to: current.position, fraction: t, world: world)
        pose.velocity = CGVector(dx: blend(velocity.dx, current.velocity.dx), dy: blend(velocity.dy, current.velocity.dy))
        pose.radius = blend(radius, current.radius)
        pose.facing = blend(facing, current.facing)
        pose.pulse = blend(pulse, current.pulse)
        pose.squash = blend(squash, current.squash)
        pose.shrink = blend(shrink, current.shrink)
        pose.struggle = blend(struggle, current.struggle)
        pose.mouth = blend(mouth, current.mouth)
        pose.chew = blend(chew, current.chew)
        return pose
    }
}

enum PresentationInterpolation {
    static func fraction(simulationRemainder: CGFloat, frameRemainder: CGFloat,
                         timeScale: CGFloat, step: CGFloat) -> CGFloat {
        // Include time between real-time ticks so 120 Hz displays also get fresh poses.
        ((simulationRemainder + frameRemainder * timeScale) / step).clamped(0, 1)
    }

    static func position(from previous: CGPoint, to current: CGPoint, fraction: CGFloat,
                         world: WrappedWorld) -> CGPoint {
        let t = fraction.clamped(0, 1)
        return CGPoint(x: world.wrap(previous.x + world.delta(from: previous.x, to: current.x) * t),
                       y: previous.y + (current.y - previous.y) * t)
    }
}
