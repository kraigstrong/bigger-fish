import CoreGraphics
import FishKit

/// A fish crossing the player's column: the one moment you can eat it, or it can eat you.
struct EncounterCrossing: Codable, Equatable {
    let fishID: Int
    /// Simulation seconds since the run started.
    let time: Double
    /// The player's forward distance in world points.
    let distance: Double
    let y: Double
    /// World points.
    let radius: Double
    /// Swimming toward the player rather than being overtaken.
    let headOn: Bool
    let zoom: Double
}

/// Route structure of a lap: which fish you can reach, after how many meals, and how forgiving each is.
/// Optimistic about steering (it plans the player's height perfectly) and about AI eating (fish are
/// protected until you pass them, so every fish is still there when you meet it).
struct EncounterAnalysis: Codable, Equatable {
    struct Meeting: Codable, Equatable {
        let crossing: EncounterCrossing
        /// Fewest earlier meals on a route that can eat this fish. Nil: no first-lap route reaches it.
        var minimumMeals: Int?
        /// Most earlier meals on a route that can still eat it.
        var maximumMeals: Int?
        /// Distinct fewest-meal routes, capped at `routeCap`.
        var routes: Int
        /// The smallest number of missed fish that makes this one unreachable, minus one. Capped at 3 (three or more).
        var robustSlack: Int?
        /// This fish's radius over yours on the biggest fewest-meal route.
        var sizeRatio: Double?
        /// A fish bigger than you crosses close by at about the same time.
        var danger: Bool
    }
    static let routeCap = 999
    static let slackCap = 3

    let meetings: [Meeting]
    let maximumMeals: Int
    /// Fish ids of a route with the most meals (the biggest such route when tied).
    let fullestRoute: [Int]

    func meeting(fishID: Int) -> Meeting? { meetings.first { $0.crossing.fishID == fishID } }
}

enum EncounterAnalyzer {
    /// Meals closer together than a swallow can't both happen; this lets the next contact start a beat early.
    static let swallowLead: Double = 0.05
    /// Fraction of the combined radii the player's center may be off a fish's height and still catch it.
    static let catchTolerance: CGFloat = 0.9
    static let dangerWindow: Double = 0.5
    static let dangerGap: CGFloat = 60

    static func analyze(_ crossings: [EncounterCrossing],
                        efficiency: CGFloat = GameTuning.freeEncounterAbsorption * GameTuning.mealGrowthScale,
                        startRadius: CGFloat = GameTuning.baseRadius,
                        startY: CGFloat = (GameTuning.waterBottomMargin + GameTuning.playfieldSize.height - GameTuning.waterTopMargin) / 2) -> EncounterAnalysis {
        let graph = RouteGraph(crossings.sorted { $0.time < $1.time }, efficiency: efficiency,
                               startRadius: startRadius, startY: startY)
        return graph.analysis()
    }

    /// Maximum vertical travel from rest in `seconds` at zoom 1, the slower of rising and falling.
    static func verticalReach(seconds: Double) -> CGFloat {
        guard seconds > 0 else { return 0 }
        let index = min(reachTable.count - 1, Int((seconds / Double(GameTuning.simulationStep)).rounded(.down)))
        return reachTable[index]
    }

    private static let reachTable: [CGFloat] = {
        var up = (y: CGFloat(0), vy: CGFloat(0)), down = (y: CGFloat(0), vy: CGFloat(0))
        var table: [CGFloat] = [0]
        for _ in 0..<(60 * 4) {
            up = PlayerMotion.step(y: up.y, vy: up.vy, holding: true, dt: GameTuning.simulationStep,
                                   minY: -10_000, maxY: 10_000, tuning: GameTuning.motion)
            down = PlayerMotion.step(y: down.y, vy: down.vy, holding: false, dt: GameTuning.simulationStep,
                                     minY: -10_000, maxY: 10_000, tuning: GameTuning.motion)
            table.append(min(up.y, -down.y))
        }
        return table
    }()
}

/// Meetings in time order; node 0 is the run's start.
private struct RouteGraph {
    let meetings: [EncounterCrossing]
    let efficiency: CGFloat
    let startRadius: CGFloat
    let startY: CGFloat
    /// Other crossings at nearly the same moment, which can block a meal.
    private let simultaneous: [[Int]]
    private var count: Int { meetings.count }

    init(_ meetings: [EncounterCrossing], efficiency: CGFloat, startRadius: CGFloat, startY: CGFloat) {
        self.meetings = meetings
        self.efficiency = efficiency
        self.startRadius = startRadius
        self.startY = startY
        simultaneous = meetings.indices.map { i in
            meetings.indices.filter { $0 != i && abs(meetings[$0].time - meetings[i].time) < 0.08 }
        }
    }

    private func radius(eatenArea: CGFloat) -> CGFloat {
        sqrt(startRadius * startRadius + efficiency * eatenArea)
    }

    /// Whether a player who has eaten `area` (squared radii), most recently `previous` (nil = start), can eat `next`.
    /// Bigger is never worse, so routes compare by eaten area.
    private func canStep(from previous: Int?, area: CGFloat, to next: Int) -> Bool {
        let target = meetings[next]
        let player = radius(eatenArea: area)
        let prey = CGFloat(target.radius)
        guard GameRules.playerEncounter(player, prey) == .firstEatsSecond else { return false }
        let fromTime = previous.map { meetings[$0].time } ?? 0
        let fromY = previous.map { CGFloat(meetings[$0].y) } ?? startY
        let elapsed = target.time - fromTime
        guard elapsed > 0 else { return false }
        if let previous {
            let eaten = CGFloat(meetings[previous].radius)
            let before = radius(eatenArea: max(0, area - eaten * eaten))
            let swallow = Double(SwallowTiming.duration(sizeRatio: eaten / before, curve: GameTuning.swallowDurationCurve))
            guard elapsed + EncounterAnalyzer.swallowLead >= swallow else { return false }
        }
        let tolerance = (player + prey) * EncounterAnalyzer.catchTolerance
        let needed = max(0, abs(CGFloat(target.y) - fromY) - tolerance)
        guard EncounterAnalyzer.verticalReach(seconds: elapsed) / CGFloat(target.zoom) >= needed else { return false }
        // A bigger fish crossing on top of this one at the same moment makes the meal impossible.
        // A missed fish is still swimming, so this applies even to fish a route skips.
        for index in simultaneous[next] {
            let other = meetings[index]
            guard CGFloat(other.radius) > player else { continue }
            if abs(CGFloat(other.y) - CGFloat(target.y)) < (player + CGFloat(other.radius)) * GameTuning.collisionScale { return false }
        }
        return true
    }

    /// best[i][c]: the most area eaten by a route whose c-th meal is meeting i (c >= 1), and the meal before it.
    private func bestAreas() -> (area: [[CGFloat?]], previous: [[Int?]]) {
        var best = Array(repeating: Array<CGFloat?>(repeating: nil, count: count + 1), count: count)
        var previous = Array(repeating: Array<Int?>(repeating: nil, count: count + 1), count: count)
        for i in 0..<count {
            let r = CGFloat(meetings[i].radius)
            if canStep(from: nil, area: 0, to: i) { best[i][1] = r * r }
            for p in 0..<i {
                for c in 1..<count {
                    guard let area = best[p][c], canStep(from: p, area: area, to: i) else { continue }
                    if best[i][c + 1].map({ area + r * r > $0 }) ?? true {
                        best[i][c + 1] = area + r * r
                        previous[i][c + 1] = p
                    }
                }
            }
        }
        return (best, previous)
    }

    /// The most area a route can eat and still reach `target`, ignoring meal counts.
    private func reachable(_ target: Int, excluding excluded: Set<Int>) -> Bool {
        var best = Array<CGFloat?>(repeating: nil, count: count)
        if canStep(from: nil, area: 0, to: target) { return true }
        for i in 0..<target where !excluded.contains(i) {
            let r = CGFloat(meetings[i].radius)
            var value: CGFloat? = canStep(from: nil, area: 0, to: i) ? r * r : nil
            for p in 0..<i where !excluded.contains(p) {
                if let area = best[p], canStep(from: p, area: area, to: i), value.map({ area + r * r > $0 }) ?? true {
                    value = area + r * r
                }
            }
            best[i] = value
            if let value, canStep(from: i, area: value, to: target) { return true }
        }
        return false
    }

    private func countRoutes(to target: Int, meals: Int) -> Int {
        var total = 0
        func extend(from previous: Int?, area: CGFloat, remaining: Int) {
            guard total < EncounterAnalysis.routeCap else { return }
            if remaining == 0 {
                if canStep(from: previous, area: area, to: target) { total += 1 }
                return
            }
            let start = (previous ?? -1) + 1
            guard start < target else { return }
            for i in start..<target where canStep(from: previous, area: area, to: i) {
                let r = CGFloat(meetings[i].radius)
                extend(from: i, area: area + r * r, remaining: remaining - 1)
            }
        }
        extend(from: nil, area: 0, remaining: meals)
        return min(total, EncounterAnalysis.routeCap)
    }

    private func robustSlack(for target: Int) -> Int {
        let earlier = Array(0..<target)
        for size in 1...EncounterAnalysis.slackCap {
            var blocked = false
            forEachSubset(of: earlier, size: size) { subset in
                if !blocked && !reachable(target, excluding: Set(subset)) { blocked = true }
                return !blocked
            }
            if blocked { return size - 1 }
        }
        return EncounterAnalysis.slackCap
    }

    func analysis() -> EncounterAnalysis {
        let (best, previous) = bestAreas()
        var maximum = 0
        var results: [EncounterAnalysis.Meeting] = []
        for (index, crossing) in meetings.enumerated() {
            let counts = (1...count).filter { best[index][$0] != nil }
            maximum = max(maximum, counts.max() ?? 0)
            guard let fewest = counts.min() else {
                results.append(.init(crossing: crossing, minimumMeals: nil, maximumMeals: nil, routes: 0,
                                     robustSlack: nil, sizeRatio: nil, danger: false))
                continue
            }
            let r = CGFloat(crossing.radius)
            let player = radius(eatenArea: best[index][fewest]! - r * r)
            let danger = meetings.enumerated().contains { other, candidate in
                other != index && abs(candidate.time - crossing.time) <= EncounterAnalyzer.dangerWindow
                    && CGFloat(candidate.radius) > player
                    && abs(CGFloat(candidate.y - crossing.y)) - (player + CGFloat(candidate.radius)) * GameTuning.collisionScale
                        <= EncounterAnalyzer.dangerGap / CGFloat(crossing.zoom)
            }
            results.append(.init(crossing: crossing, minimumMeals: fewest - 1, maximumMeals: counts.max()! - 1,
                routes: countRoutes(to: index, meals: fewest - 1), robustSlack: robustSlack(for: index),
                sizeRatio: Double(r / player), danger: danger))
        }
        var route: [Int] = []
        let ends = (0..<count).compactMap { i in best[i][maximum].map { (i, $0) } }
        if maximum > 0, var current = ends.max(by: { $0.1 < $1.1 })?.0 {
            for c in stride(from: maximum, through: 1, by: -1) {
                route.append(current)
                guard let before = previous[current][c] else { break }
                current = before
            }
        }
        return EncounterAnalysis(meetings: results, maximumMeals: maximum,
                                 fullestRoute: route.reversed().map { meetings[$0].fishID })
    }
}

/// Visits each `size`-element subset until `body` returns false.
private func forEachSubset(of items: [Int], size: Int, _ body: ([Int]) -> Bool) {
    guard size <= items.count else { return }
    var indices = Array(0..<size)
    while true {
        guard body(indices.map { items[$0] }) else { return }
        var position = size - 1
        while position >= 0 && indices[position] == items.count - size + position { position -= 1 }
        guard position >= 0 else { return }
        indices[position] += 1
        for next in (position + 1)..<size { indices[next] = indices[next - 1] + 1 }
    }
}
