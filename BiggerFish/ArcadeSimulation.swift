#if DEBUG
import CoreGraphics
import Foundation
import FishKit

/// Offline diagnostics use different player policies, not a claim to measure human enjoyment.
enum ArcadeSimulation {
    enum Policy: String, CaseIterable, Codable { case collector, opportunist, cautious }
    struct Swimmer { var canEat = true; let x: CGFloat; let y: CGFloat; let vx: CGFloat; let vy: CGFloat; let radius: CGFloat }
    struct Bell { let x: CGFloat; let y: CGFloat; let radius: CGFloat; let tentacles: CGFloat }
    struct Observation {
        let player: Swimmer
        let fish: [Swimmer]
        let bells: [Bell]
        let width: CGFloat
        let screenWidth: CGFloat
        let zoom: CGFloat
        let bottom: CGFloat
        let top: CGFloat
        let speed: CGFloat
        let bouncing: Bool
        let bounceSpeed: CGFloat
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

    struct Stats: Codable {
        var playerMeals = 0
        var aiMeals = 0
        var closeMeals = 0
        var contestedMeals = 0
        var bounces = 0
        var aiHazardDeaths = 0
        var threatSeconds: Double = 0
        var nearbyThreatSeconds: Double = 0
        var stalledSeconds: Double = 0
        var lastThreat: Double = 0
        var firstStallLap: Double?
        var lastStallLap: Double?
        var recoveredPaths = 0
        var mealLaps: [Double] = []
        var mealRatios: [Double] = []
        var mealFishIDs: [Int] = []
        var mealStartLaps: [Double] = []
        var mealStartFishIDs: [Int] = []
        var minimumThreatClearance: Double = 100_000
    }
    struct Result: Codable {
        let candidate: String
        let level: Int
        let policy: Policy
        var decisionIntervalSeconds: Double? = nil
        var predictionSeconds: Double? = nil
        var foodPriority: Double? = nil
        var dangerWeight: Double? = nil
        let seed: Int
        let width: Double
        let skippedFirstPassFishIDs: [Int]
        let firstPassMealLimit: Int?
        let delayedPasses: Double
        let ecologyProbe: Bool
        let laps: Double
        let outcome: String
        let reason: String
        let seconds: Double
        let remaining: Int
        let playerRadius: Double
        let spawned: Int
        let configured: Int
        let initialGrowthPath: Bool
        let stats: Stats
        let tuning: ArcadeTuning
    }

    static func hasGrowthPath(player: CGFloat, radii: [CGFloat], efficiency: CGFloat) -> Bool {
        var radius = player
        for prey in radii.sorted() {
            guard GameRules.playerEncounter(radius, prey) == .firstEatsSecond else { return false }
            radius = GameRules.grownRadius(predator: radius, prey: prey, efficiency: efficiency)
        }
        return true
    }

    /// Predict short local trajectories for both inputs. Only visible fish enter the observation.
    /// Prediction is approximate; the rollout itself always advances the actual scene physics.
    static func holding(_ observation: Observation, policy: Policy, feeding: Bool = true, predictionSeconds: CGFloat = 0.6, foodPriority: CGFloat? = nil, dangerWeight: CGFloat? = nil) -> Bool {
        let p = observation.player
        let wrapped = WrappedWorld(width: observation.width)
        let food = observation.fish.filter { feeding && $0.canEat && GameRules.playerEncounter(p.radius, $0.radius) == .firstEatsSecond }
        let target = food.min { a, b in
            func value(_ f: Swimmer) -> CGFloat {
                var dx = wrapped.delta(from: p.x, to: f.x)
                if dx < -(p.radius + f.radius) { dx += observation.width }
                let intercept = min(2, max(0, dx / max(60, observation.speed - f.vx)))
                let vertical = abs(f.y + f.vy * intercept - p.y)
                let mealValue = f.radius * (foodPriority ?? (policy == .opportunist ? 4 : 0))
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
        let predictionSteps = max(2, Int((predictionSeconds * 30).rounded()))
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
                for f in observation.fish {
                    let dx = wrapped.delta(from: x, to: wrapped.wrap(f.x + f.vx * time))
                    let dy = f.y + f.vy * time - y
                    let gap = hypot(dx, dy) - (p.radius + f.radius) * GameTuning.collisionScale
                    if GameRules.playerEncounter(p.radius, f.radius) == .secondEatsFirst {
                        let threatCost: CGFloat = dangerWeight ?? (policy == .cautious ? 140 : (policy == .opportunist ? 45 : 80))
                        if gap < 0 { cost += 100_000 }
                        else { cost += max(0, 75 - gap) * threatCost / CGFloat(predictionSteps) }
                    } else if GameRules.playerEncounter(p.radius, f.radius) == .firstEatsSecond && gap < 0 {
                        cost += feeding && f.canEat ? (policy == .opportunist ? -300 : -150) : 100_000
                    }
                }
            }
            cost += abs(y - targetY) * 2 + abs(vy) * 0.02
            if cost < best { best = cost; choice = sequence & 1 != 0 }
        }
        return choice
    }
}
#endif
