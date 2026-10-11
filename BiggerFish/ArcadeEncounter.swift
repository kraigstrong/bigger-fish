import CoreGraphics
import Foundation
import FishKit

/// Protection follows forward world distance, independent of camera zoom or wall-clock time.
struct EncounterLease {
    let home: CGPoint
    let releaseDistance: CGFloat
    var index: Int = 0
    func isProtected(distance: CGFloat) -> Bool { distance < releaseDistance }
}

enum EncounterSteering {
    /// Relative position points away from the neighbor. Only approaching or overlapping pairs steer.
    static func separation(relative: CGVector, velocity: CGVector, reach: CGFloat,
                           stableDirection: CGFloat) -> CGVector? {
        let speedSquared = velocity.dx * velocity.dx + velocity.dy * velocity.dy
        let time = speedSquared > 0
            ? min(GameTuning.encounterSeparationLookAhead,
                max(0, -(relative.dx * velocity.dx + relative.dy * velocity.dy) / speedSquared)) : 0
        let x = relative.dx + velocity.dx * time, y = relative.dy + velocity.dy * time
        guard hypot(x, y) < reach else { return nil }
        let distance = hypot(relative.dx, relative.dy)
        let strength = GameTuning.encounterSeparationSpeed * (1 - min(1, hypot(x, y) / reach))
        return distance > 0.001
            ? CGVector(dx: relative.dx / distance * strength, dy: relative.dy / distance * strength)
            : CGVector(dx: stableDirection * GameTuning.encounterSeparationSpeed, dy: 0)
    }
}
