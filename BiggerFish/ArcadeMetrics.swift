import Foundation
import FishKit

/// No identifiers, trajectories, or wall-clock play timestamps. Context identifies game content only.
struct ArcadeMetricContext: Codable, Equatable {
    let world: String
    let level: Int
    let setup: Int
    let seed: String
    var mode: String = "campaign"
    let revision: String
}

struct ArcadeGrowthSnapshot: Codable, Equatable {
    enum Path: String, Codable { case available, noPath = "no_path_in_snapshot", unknown }
    let path: Path
    let playerRadius: Double
    let remaining: Int
    let edible: Int
    let largestRatio: Double

    static func measure(player: CGFloat, opponents: [CGFloat], efficiency: CGFloat, inFlight: Bool = false) -> Self {
        guard player.isFinite, player > 0, efficiency.isFinite, efficiency >= 0,
              opponents.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return Self(path: .unknown, playerRadius: 0, remaining: 0, edible: 0, largestRatio: 0)
        }
        return Self(path: inFlight ? .unknown : (ArcadeGrowthBudget.hasPath(player: player, radii: opponents, efficiency: efficiency) ? .available : .noPath),
            playerRadius: min(100000, Double(player)), remaining: min(10000, opponents.count),
            edible: min(10000, opponents.filter { GameRules.playerEncounter(player, $0) == .firstEatsSecond }.count),
            largestRatio: min(1000, Double((opponents.max() ?? 0) / player)))
    }
}

/// An optimistic size-budget check. It does not model reachability, hazards, or future AI meals.
enum ArcadeGrowthBudget {
    static func hasPath(player: CGFloat, radii: [CGFloat], efficiency: CGFloat) -> Bool {
        var radius = player
        for prey in radii.sorted() {
            guard GameRules.playerEncounter(radius, prey) == .firstEatsSecond else { return false }
            radius = GameRules.grownRadius(predator: radius, prey: prey, efficiency: efficiency)
        }
        return true
    }
}

struct ArcadeRunMetrics: Codable, Equatable {
    var seconds: Double = 0
    var circuits: Double = 0
    var playerMeals = 0
    var aiMeals = 0
    var closeMeals = 0
    var nearEqualMeals = 0
    var bounces = 0
    var cleanupSeconds: Double = 0
    var longestMealGap: Double = 0
    var noPathSeconds: Double = 0
    var firstNoPathSeconds: Double?
    var firstNoPathCircuits: Double?
    var pathRecovered = false
    var snapshot = ArcadeGrowthSnapshot(path: .unknown, playerRadius: 0, remaining: 0, edible: 0, largestRatio: 0)
    var fatalRatio: Double?
}

/// In-memory accounting only. No persistence or networking on the frame/meal path.
struct ArcadeMetricAccumulator {
    private(set) var summary = ArcadeRunMetrics()
    private var lastMealSeconds: Double = 0
    private var hadNoPath = false

    mutating func advance(seconds: Double, circuits: Double) {
        let dt = max(0, seconds - summary.seconds)
        summary.seconds = min(3600, seconds)
        summary.circuits = min(100, circuits)
        summary.longestMealGap = min(3600, max(summary.longestMealGap, seconds - lastMealSeconds))
        if summary.snapshot.path == .noPath { summary.noPathSeconds = min(3600, summary.noPathSeconds + dt) }
        if summary.snapshot.path == .available && summary.snapshot.remaining > 0 && summary.snapshot.edible == summary.snapshot.remaining {
            summary.cleanupSeconds = min(3600, summary.cleanupSeconds + dt)
        }
    }

    mutating func observe(_ snapshot: ArcadeGrowthSnapshot) {
        summary.snapshot = snapshot
        if snapshot.path == .noPath {
            hadNoPath = true
            if summary.firstNoPathSeconds == nil {
                summary.firstNoPathSeconds = summary.seconds
                summary.firstNoPathCircuits = summary.circuits
            }
        } else if snapshot.path == .available && hadNoPath { summary.pathRecovered = true }
    }

    mutating func meal(player: Bool, ratio: Double) {
        if player {
            summary.playerMeals = min(10000, summary.playerMeals + 1)
            if ratio >= Double(GameTuning.closeCallRatio) { summary.closeMeals = min(10000, summary.closeMeals + 1) }
            if ratio >= 0.95 { summary.nearEqualMeals = min(10000, summary.nearEqualMeals + 1) }
            lastMealSeconds = summary.seconds
        } else { summary.aiMeals = min(10000, summary.aiMeals + 1) }
    }
    mutating func bounce() { summary.bounces = min(10000, summary.bounces + 1) }
    mutating func fatal(ratio: Double?) { summary.fatalRatio = ratio.map { min(1000, $0) } }
}
