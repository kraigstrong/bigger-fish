#if DEBUG
import CoreGraphics
import Foundation
import FishKit

/// Offline diagnostics use different player policies, not a claim to measure human enjoyment.
enum ArcadeSimulation {
    enum Policy: String, CaseIterable, Codable { case collector, opportunist, cautious }
    struct Swimmer { let x: CGFloat; let y: CGFloat; let vx: CGFloat; let vy: CGFloat; let radius: CGFloat }
    struct Bell { let x: CGFloat; let y: CGFloat; let radius: CGFloat; let tentacles: CGFloat }
    struct Observation {
        let player: Swimmer
        var fish: [Swimmer]
        let bells: [Bell]
        let width: CGFloat
        let screenWidth: CGFloat
        let zoom: CGFloat
        let bottom: CGFloat
        let top: CGFloat
        let speed: CGFloat
        let bouncing: Bool
        let bounceSpeed: CGFloat
        /// Sunset Cove's hooks on screen, each as the circle its bait and bend catch you in (`radius`), moving as it is now.
        var hooks: [Swimmer] = []
        /// Smaller fish to swim round rather than eat (meals a planned route skips), and how close (screen points of
        /// water) a bigger fish may come before the bot starts to give it room.
        var avoids: [Swimmer] = []
        var threatMargin: CGFloat = 75
        var seeksFood = true
        /// Screen points of water the bot likes to keep from a hook (it never touches one it sees coming).
        var hookMargin: CGFloat = 8
    }
    /// Internal steering state for controlled repeatability investigations.
    struct AuditFish: Codable, Equatable {
        let id: Int
        let x: Double
        let y: Double
        let vx: Double
        let vy: Double
        let radius: Double
        let targetY: Double
        let retargetTimer: Double
        let turnTimer: Double
        let state: String
    }
    struct Audit: Codable, Equatable {
        let seconds: Double
        let zoom: Double
        let waterBottom: Double
        let waterTop: Double
        let fish: [AuditFish]
    }

    /// How a bot's run ended (`GameScene.debugSimulate`).
    struct Result {
        let outcome: String
        let reason: String
        let seconds: Double
        let playerMeals: Int
    }

    /// Predict short local trajectories for both inputs. Only visible fish enter the observation.
    /// Prediction is approximate; the rollout itself always advances the actual scene physics.
    /// `path`: the height to be at so many seconds from now, and how much it matters then, followed instead of making for
    /// the nearest meal (a planned level's reference route: a straight swim from one meeting to the next, and being at
    /// each meeting matters most).
    static func holding(_ observation: Observation, policy: Policy,
                        path: ((CGFloat) -> (y: CGFloat, weight: CGFloat))? = nil) -> Bool {
        let p = observation.player
        let wrapped = WrappedWorld(width: observation.width)
        let food = observation.fish.filter { GameRules.playerEncounter(p.radius, $0.radius) == .firstEatsSecond }
        let target = food.min { a, b in
            func value(_ f: Swimmer) -> CGFloat {
                var dx = wrapped.delta(from: p.x, to: f.x)
                if dx < -(p.radius + f.radius) { dx += observation.width }
                let intercept = min(2, max(0, dx / max(60, observation.speed - f.vx)))
                let vertical = abs(f.y + f.vy * intercept - p.y)
                let mealValue = f.radius * (policy == .opportunist ? 4 : 0)
                return dx + vertical * 1.6 - mealValue
            }
            return value(a) < value(b)
        }
        let targetY = target.map { f -> CGFloat in
            let dx = max(0, wrapped.delta(from: p.x, to: f.x))
            let arrival = min(1.5, dx / max(60, observation.speed - f.vx))
            return (f.y + f.vy * arrival).clamped(observation.bottom + p.radius, observation.top - p.radius)
        } ?? (observation.bottom + observation.top) / 2
        var best = CGFloat.greatestFiniteMagnitude
        var choice = false
        // Four input sequences let the bot brake a fall or start a descent instead of holding forever.
        let predictionSteps = 18
        for sequence in 0..<4 {
            var y = p.y, vy = p.vy, x = p.x
            var cost: CGFloat = 0
            var bounced = observation.bouncing
            for step in 1...predictionSteps {
                let dt: CGFloat = 1.0 / 30
                let hold = sequence & (step <= predictionSteps / 2 ? 1 : 2) != 0
                var motion = GameTuning.motion
                if bounced { motion.maxRiseSpeed = observation.bounceSpeed; motion.fallAcceleration *= 0.35 }
                let old = CGPoint(x: x, y: y)
                (y, vy) = PlayerMotion.step(y: y, vy: vy, holding: hold, dt: dt,
                    minY: observation.bottom + p.radius * 0.95, maxY: observation.top - p.radius * 0.95,
                    zoom: observation.zoom, tuning: motion)
                x = wrapped.wrap(x + observation.speed * dt)
                let time = CGFloat(step) * dt
                for bell in observation.bells {
                    let relative = CGPoint(x: wrapped.delta(from: bell.x, to: x), y: y - bell.y)
                    let previous = CGPoint(x: relative.x - observation.speed * dt, y: old.y - bell.y)
                    let contact = JellyRules.contact(at: relative, previous: previous, fishRadius: p.radius,
                        domeRadius: bell.radius, tentacleLength: bell.tentacles)
                    if contact == .tentacles { cost += 100_000 }
                    if contact == .bounce && !bounced {
                        vy = observation.bounceSpeed / observation.zoom
                        y = bell.y + bell.radius * 0.65 + p.radius * GameTuning.hazardHitboxScale + 2
                        bounced = true
                    }
                }
                for hook in observation.hooks {
                    let dx = wrapped.delta(from: x, to: wrapped.wrap(hook.x + hook.vx * time))
                    let gap = hypot(dx, hook.y + hook.vy * time - y) - p.radius * GameTuning.hazardHitboxScale - hook.radius
                    if gap < 0 { cost += 100_000 } else { cost += max(0, observation.hookMargin - gap) * 60 / CGFloat(predictionSteps) }
                }
                for f in observation.fish {
                    let dx = wrapped.delta(from: x, to: wrapped.wrap(f.x + f.vx * time))
                    let dy = f.y + f.vy * time - y
                    let gap = hypot(dx, dy) - (p.radius + f.radius) * GameTuning.collisionScale
                    if GameRules.playerEncounter(p.radius, f.radius) == .secondEatsFirst {
                        let threatCost: CGFloat = policy == .cautious ? 140 : (policy == .opportunist ? 45 : 80)
                        if gap < 0 { cost += 100_000 }
                        else { cost += max(0, observation.threatMargin - gap) * threatCost / CGFloat(predictionSteps) }
                    } else if observation.seeksFood, GameRules.playerEncounter(p.radius, f.radius) == .firstEatsSecond && gap < 0 {
                        cost += policy == .opportunist ? -300 : -150
                    }
                }
                for f in observation.avoids {
                    let dx = wrapped.delta(from: x, to: wrapped.wrap(f.x + f.vx * time))
                    if hypot(dx, f.y + f.vy * time - y) < (p.radius + f.radius) * GameTuning.collisionScale { cost += 20_000 }
                }
                if let wanted = path?(time) { cost += abs(y - wanted.y) * wanted.weight * 4 / CGFloat(predictionSteps) }
            }
            if path == nil { cost += abs(y - targetY) * 2 }
            cost += abs(vy) * 0.02
            if cost < best { best = cost; choice = sequence & 1 != 0 }
        }
        return choice
    }
}
#endif
