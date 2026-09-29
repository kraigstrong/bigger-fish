import CoreGraphics
import SpriteKit
import Testing
@testable import FishKit

struct WrappedWorldTests {
    let world = WrappedWorld(width: 1000)

    @Test func wrapsIntoRange() {
        #expect(world.wrap(1010) == 10)
        #expect(world.wrap(-10) == 990)
        #expect(world.wrap(1000) == 0)
        #expect(world.wrap(0) == 0)
    }

    @Test func shortestDeltaCrossesSeam() {
        #expect(world.delta(from: 990, to: 10) == 20)
        #expect(world.delta(from: 10, to: 990) == -20)
        #expect(world.delta(from: 100, to: 300) == 200)
        #expect(world.delta(from: 300, to: 100) == -200)
    }

    @Test func distanceCrossesSeam() {
        let d = world.distance(CGPoint(x: 995, y: 0), CGPoint(x: 5, y: 0))
        #expect(abs(d - 10) < 1e-9)
        let diagonal = world.distance(CGPoint(x: 997, y: 0), CGPoint(x: 1, y: 3))
        #expect(abs(diagonal - 5) < 1e-9)
    }
}

struct SwallowTimingTests {
    let curve: [(ratio: CGFloat, seconds: CGFloat)] = [(0.5, 0.1), (1.0, 0.5)]

    @Test func interpolatesAndClamps() {
        #expect(SwallowTiming.duration(sizeRatio: 0.2, curve: curve) == 0.1)
        #expect(abs(SwallowTiming.duration(sizeRatio: 0.75, curve: curve) - 0.3) < 1e-9)
        #expect(SwallowTiming.duration(sizeRatio: 2, curve: curve) == 0.5)
    }
}

struct PlayerMotionTests {
    let tuning = MotionTuning(
        riseAcceleration: 1000, fallAcceleration: 1000, verticalDamping: 0,
        maxRiseSpeed: 200, maxFallSpeed: 200, boundaryBounce: 0.5, maxTilt: 0.3
    )

    @Test func holdingRisesAndReleasingFalls() {
        let up = PlayerMotion.step(y: 100, vy: 0, holding: true, dt: 0.1, minY: 0, maxY: 1000, tuning: tuning)
        let down = PlayerMotion.step(y: 100, vy: 0, holding: false, dt: 0.1, minY: 0, maxY: 1000, tuning: tuning)
        #expect(up.vy == 100 && up.y > 100)
        #expect(down.vy == -100 && down.y < 100)
    }

    @Test func capsSpeedAndSoftensBoundaries() {
        let capped = PlayerMotion.step(y: 100, vy: 190, holding: true, dt: 0.1, minY: 0, maxY: 1000, tuning: tuning)
        #expect(capped.vy == 200)
        // Hitting the top clamps position and reflects a fraction of the speed.
        let top = PlayerMotion.step(y: 99, vy: 200, holding: true, dt: 0.1, minY: 0, maxY: 100, tuning: tuning)
        #expect(top.y == 100)
        #expect(top.vy == -100)
    }
}

struct SeededGeneratorTests {
    @Test func isDeterministic() {
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42)
        #expect((0..<5).map { _ in a.next() } == (0..<5).map { _ in b.next() })
    }
}

/// Headwear (Math Reef's crowns) sits on the head and turns with the fish.
@MainActor
struct HeadwearTests {
    @Test func wearingReplacingAndRemoving() {
        let fish = FishNode(style: .player, isPlayer: true, tailPhase: 0)
        let crown = SKNode(), hat = SKNode()
        fish.setHeadwear(crown)
        #expect(crown.parent != nil)
        #expect(crown.position == FishNode.headwearAnchor)
        fish.setHeadwear(hat)
        #expect(crown.parent == nil && hat.parent != nil)
        fish.setHeadwear(nil)
        #expect(hat.parent == nil)
    }

    @Test func headwearFlipsAndScalesWithTheFish() {
        let fish = FishNode(style: .player, isPlayer: true, tailPhase: 0)
        let crown = SKNode()
        fish.setHeadwear(crown)
        fish.apply(radius: 60, facing: -1, tilt: 0, stretchX: 1, stretchY: 1, mouthOpen: 0, time: 0, tailRate: 0)
        let onScreen = crown.convert(CGPoint.zero, to: fish)
        #expect(abs(onScreen.x - -2 * FishNode.headwearAnchor.x) < 0.001)  // mirrored, at twice the size
        #expect(abs(onScreen.y - 2 * FishNode.headwearAnchor.y) < 0.001)
    }
}
