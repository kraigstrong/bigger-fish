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

/// One Open Water run, start to end (`ArcadeAnalytics`' `endless` event): levels cleared, fish eaten (its score), pearls
/// taken, game seconds across every level, whether it beat the best kept so far, the levels that waited on the next
/// one's plan and the game seconds spent waiting, the slowest of its levels' plans (wall seconds, off the main thread),
/// and whether your fish wore any look. Counts saturate as the run summaries' do; they never limit play.
struct ArcadeOpenWaterMetrics: Codable, Equatable {
    var levels = 0
    var fish = 0
    var pearls = 0
    var seconds: Double = 0
    var best = false
    var waits = 0
    var waitSeconds: Double = 0
    var slowestPlan: Double = 0
    var dressed = false
}

/// An Open Water run's numbers as it plays, in memory only. Each level's clock starts again at 0, so a cleared level's
/// seconds are added up here.
struct OpenWaterMetricAccumulator {
    private(set) var levels = 0
    private var clearedSeconds: Double = 0
    private var waits = 0
    private var waitSeconds: Double = 0
    /// When (on the level's clock) the level was done and began waiting for the next one's plan.
    private var waitingSince: Double?
    private var slowestPlan: Double = 0

    /// The level is done, but the next one isn't planned yet: it plays on until it is.
    mutating func waiting(at seconds: Double) {
        if waitingSince == nil { waitingSince = seconds }
    }

    /// The level was cleared `seconds` into it.
    mutating func cleared(at seconds: Double) {
        if let since = waitingSince {
            waits += 1
            waitSeconds += max(0, seconds - since)
            waitingSince = nil
        }
        clearedSeconds += max(0, seconds)
        levels += 1
    }

    /// One of the run's levels took `seconds` to plan.
    mutating func planned(seconds: Double) {
        if seconds.isFinite { slowestPlan = max(slowestPlan, seconds) }
    }

    /// The run so far, `seconds` into the level it's on. A wait still going counts as one.
    func summary(at seconds: Double, fish: Int, pearls: Int, best: Bool, dressed: Bool) -> ArcadeOpenWaterMetrics {
        let total = min(3600, clearedSeconds + max(0, seconds))
        let open = waitingSince.map { max(0, seconds - $0) }
        let levels = min(1000, levels)
        return ArcadeOpenWaterMetrics(levels: levels, fish: min(10000, max(0, fish)), pearls: min(10000, max(0, pearls)),
            seconds: total, best: best, waits: min(levels + 1, waits + (open == nil ? 0 : 1)),
            waitSeconds: min(total, waitSeconds + (open ?? 0)), slowestPlan: min(600, slowestPlan), dressed: dressed)
    }
}
