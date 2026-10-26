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
    /// Its own swimming speed (world points a second), for how long its body is alongside you: a fish swimming your
    /// way is beside you for a while, one coming at you passes in a moment. Optional so older plans decode.
    var speed: Double? = nil
}

/// A jellyfish crossing the player's column: stinging tentacles hang below its rim, and its dome
/// launches you upward if you land on it from above.
struct JellyPass: Codable, Equatable {
    let jellyID: Int
    let time: Double
    /// World y of the bell's rim.
    let rim: Double
    let domeRadius: Double
    let tentacleLength: Double
    /// Your forward speed (world points per second) and the zoom when you pass it.
    let speed: Double
    let zoom: Double

    /// Half the time the bell's curtain spends in your column, for a player of this radius.
    func halfWindow(playerRadius: CGFloat) -> Double {
        Double(CGFloat(domeRadius) * 0.72 + playerRadius * GameTuning.hazardHitboxScale) / speed
    }
    /// The heights where a player's center touches the tentacles or bumps the bell.
    func band(playerRadius: CGFloat) -> ClosedRange<CGFloat> {
        let body = playerRadius * GameTuning.hazardHitboxScale
        return (CGFloat(rim - tentacleLength) - body)...domeTop(playerRadius: playerRadius)
    }
    /// A player's center resting on top of the dome.
    func domeTop(playerRadius: CGFloat) -> CGFloat {
        CGFloat(rim + domeRadius * 0.65) + playerRadius * GameTuning.hazardHitboxScale
    }
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
        /// The fish ids of the biggest fewest-meal route to it. Optional so older plans decode.
        var fewestRoute: [Int]? = nil
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

    static func analyze(_ crossings: [EncounterCrossing], jellies: [JellyPass] = [],
                        efficiency: CGFloat = GameTuning.freeEncounterAbsorption * GameTuning.mealGrowthScale,
                        startRadius: CGFloat = GameTuning.baseRadius,
                        startY: CGFloat = (GameTuning.waterBottomMargin + GameTuning.playfieldSize.height - GameTuning.waterTopMargin) / 2,
                        reachScale: CGFloat = 1) -> EncounterAnalysis {
        var graph = RouteGraph(crossings.sorted { $0.time < $1.time }, jellies: jellies.sorted { $0.time < $1.time },
                               efficiency: efficiency, startRadius: startRadius, startY: startY)
        graph.reachScale = reachScale
        return graph.analysis()
    }

    /// Whether a player of `radius` who ate `from` (nil: the start) can reach `to` by swimming, and by
    /// bouncing off a jelly between them. Optimistic about steering, like the route graph.
    static func reach(from: EncounterCrossing?, to: EncounterCrossing, jellies: [JellyPass], radius: CGFloat,
                      startY: CGFloat = (GameTuning.waterBottomMargin + GameTuning.playfieldSize.height - GameTuning.waterTopMargin) / 2) -> (swim: Bool, bounce: Bool) {
        let tolerance = (radius + CGFloat(to.radius)) * catchTolerance
        let start = (time: from?.time ?? 0, y: from.map { CGFloat($0.y) } ?? startY)
        let jellies = jellies.sorted { $0.time < $1.time }
        return (JellyRoutes.swim(from: start, to: (to.time, CGFloat(to.y), CGFloat(to.zoom)), tolerance: tolerance,
                                 radius: radius, jellies: jellies),
                JellyRoutes.bounce(from: start, to: (to.time, CGFloat(to.y), CGFloat(to.zoom)), tolerance: tolerance,
                                   radius: radius, jellies: jellies,
                                   startSlack: from.map { (radius + CGFloat($0.radius)) * catchTolerance } ?? 0))
    }

    /// Height gained (up) or lost (down) in `seconds` after a bounce at zoom 1, holding the whole time or
    /// letting go at once.
    static func bounceReach(seconds: Double) -> (up: CGFloat, down: CGFloat) {
        guard seconds > 0 else { return (0, 0) }
        let index = min(bounceTable.count - 1, Int((seconds / Double(GameTuning.simulationStep)).rounded(.down)))
        return bounceTable[index]
    }

    private static let bounceTable: [(up: CGFloat, down: CGFloat)] = {
        let step = GameTuning.simulationStep
        var bounced = GameTuning.motion
        bounced.maxRiseSpeed = GameTuning.jellyBounceSpeed
        bounced.fallAcceleration *= 0.35
        var up = (y: CGFloat(0), vy: GameTuning.jellyBounceSpeed), down = up
        var table: [(up: CGFloat, down: CGFloat)] = [(0, 0)]
        for index in 0..<(60 * 4) {
            let tuning = CGFloat(index) * step < GameTuning.jellyBounceSeconds ? bounced : GameTuning.motion
            up = PlayerMotion.step(y: up.y, vy: up.vy, holding: true, dt: step, minY: -10_000, maxY: 10_000, tuning: tuning)
            down = PlayerMotion.step(y: down.y, vy: down.vy, holding: false, dt: step, minY: -10_000, maxY: 10_000, tuning: tuning)
            table.append((up.y, down.y))
        }
        return table
    }()

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

/// Getting between two meals around jellyfish: over or under each curtain as it passes, or off a dome.
enum JellyRoutes {
    typealias Point = (time: Double, y: CGFloat)

    private static func reach(_ seconds: Double, zoom: CGFloat) -> CGFloat {
        EncounterAnalyzer.verticalReach(seconds: seconds) / zoom
    }

    private static func water(radius: CGFloat, zoom: CGFloat) -> ClosedRange<CGFloat> {
        let bounds = PlayerTimeline.waterBounds(zoom: zoom)
        return (bounds.bottom + radius * 0.95)...max(bounds.bottom + radius * 0.95, bounds.top - radius * 0.95)
    }

    /// Passes whose curtain is in your column at some moment strictly between the two meals.
    private static func passes(_ jellies: [JellyPass], from start: Double, to end: Double, radius: CGFloat) -> [JellyPass] {
        jellies.filter { pass in
            let window = pass.halfWindow(playerRadius: radius)
            return pass.time + window > start && pass.time - window < end
        }
    }

    /// Swimming only: every curtain on the way is passed above its dome or below its tentacles.
    static func swim(from start: Point, to target: (time: Double, y: CGFloat, zoom: CGFloat), tolerance: CGFloat,
                     radius: CGFloat, jellies: [JellyPass]) -> Bool {
        let elapsed = target.time - start.time
        guard elapsed > 0 else { return false }
        let between = passes(jellies, from: start.time, to: target.time, radius: radius)
        guard !between.isEmpty else {
            return reach(elapsed, zoom: target.zoom) >= max(0, abs(target.y - start.y) - tolerance)
        }
        // Heights you could be at, as separate stretches of water, propagated pass by pass.
        var spans: [ClosedRange<CGFloat>] = [start.y...start.y]
        var time = start.time
        for pass in between {
            let zoom = CGFloat(pass.zoom)
            let window = pass.halfWindow(playerRadius: radius)
            let opens = max(time, pass.time - window), closes = min(target.time, pass.time + window)
            let water = water(radius: radius, zoom: zoom)
            let band = pass.band(playerRadius: radius)
            let sides = [(water.lowerBound, min(water.upperBound, band.lowerBound)),
                         (max(water.lowerBound, band.upperBound), water.upperBound)].filter { $0.0 < $0.1 }.map { $0.0...$0.1 }
            let arrive = reach(opens - time, zoom: zoom), through = reach(closes - opens, zoom: zoom)
            spans = sides.flatMap { side in
                spans.compactMap { span -> ClosedRange<CGFloat>? in
                    let low = max(side.lowerBound, span.lowerBound - arrive), high = min(side.upperBound, span.upperBound + arrive)
                    guard low <= high else { return nil }
                    return max(side.lowerBound, low - through)...min(side.upperBound, high + through)
                }
            }
            time = closes
            if spans.isEmpty { return false }
        }
        let last = reach(target.time - time, zoom: target.zoom)
        return spans.contains { span in
            target.y >= span.lowerBound - last - tolerance && target.y <= span.upperBound + last + tolerance
        }
    }

    /// Landing on a dome between the meals and riding the bounce to the target.
    /// `startSlack`: how far from the last meal's height you could have been while eating it.
    static func bounce(from start: Point, to target: (time: Double, y: CGFloat, zoom: CGFloat), tolerance: CGFloat,
                       radius: CGFloat, jellies: [JellyPass], startSlack: CGFloat = 0) -> Bool {
        let between = passes(jellies, from: start.time, to: target.time, radius: radius)
        for pass in between {
            let zoom = CGFloat(pass.zoom)
            let window = pass.halfWindow(playerRadius: radius)
            let dome = pass.domeTop(playerRadius: radius)
            // Be above the dome before its curtain reaches you (or fall onto it from above), then land.
            let landing = max(start.time, pass.time - window)
            let ready = start.y + startSlack >= dome
                ? reach(pass.time + window - start.time, zoom: zoom) + startSlack >= start.y - dome
                : reach(landing - start.time, zoom: zoom) >= dome - start.y && landing > start.time
            guard ready else { continue }
            let bounced = max(start.time, pass.time)
            // Every other curtain on the way still has to be passed: over or under on the way to the dome,
            // and with part of the bounce's reach clear of it afterward.
            let others = between.filter { $0 != pass }
            if bounced - start.time > 0.02 {
                let before = others.filter { $0.time < bounced }
                guard before.isEmpty || swim(from: start, to: (bounced, dome, zoom), tolerance: startSlack,
                                             radius: radius, jellies: before) else { continue }
            }
            let laterClear = others.filter { $0.time > bounced }.allSatisfy { later in
                let rise = EncounterAnalyzer.bounceReach(seconds: later.time - bounced)
                let band = later.band(playerRadius: radius)
                return dome + rise.down / CGFloat(later.zoom) < band.lowerBound || dome + rise.up / CGFloat(later.zoom) > band.upperBound
            }
            guard laterClear else { continue }
            let after = EncounterAnalyzer.bounceReach(seconds: target.time - bounced)
            let water = water(radius: radius, zoom: target.zoom)
            let high = min(water.upperBound, dome + after.up / target.zoom), low = max(water.lowerBound, dome + after.down / target.zoom)
            if target.y >= low - tolerance && target.y <= high + tolerance { return true }
        }
        return false
    }
}

/// Getting between two meals past the bigger fish crossing your column on the way: each one's body shuts a band of
/// water for as long as it's alongside you, and you have to be above or below it then, with the time to get there and
/// on to the meal. Optimistic about steering, like the rest of the route graph: it rises and falls as fast as it can.
enum ThreatRoutes {
    /// A bigger fish crossing your column: the moment its center is level with yours, how long its body is alongside
    /// you either side of that, and its reach (your radius and its, at the collision scale). The heights it shuts
    /// taper from the full reach at the crossing to nothing at the ends of the window, as a circle does.
    struct Band {
        let center: Double
        let half: Double
        let y: CGFloat
        let reach: CGFloat
        let zoom: CGFloat
        /// `opens`: not before the end of the last meal's swallow, which keeps you safe.
        var opens: Double = -.infinity

        var from: Double { max(opens, center - half) }
        var to: Double { center + half }
        /// The heights shut at `time`: the body's half-height at that moment, as a circle's.
        func shut(at time: Double) -> ClosedRange<CGFloat> {
            let away = abs(time - center)
            let h = reach * CGFloat((max(0, 1 - (away / half) * (away / half))).squareRoot())
            return (y - h)...(y + h)
        }
    }

    /// `water` with the `shut` stretches taken out.
    private static func sides(_ water: ClosedRange<CGFloat>, shut: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var sides = [water]
        for band in shut {
            sides = sides.flatMap { side -> [ClosedRange<CGFloat>] in
                guard band.upperBound > side.lowerBound, band.lowerBound < side.upperBound else { return [side] }
                var left: [ClosedRange<CGFloat>] = []
                if band.lowerBound > side.lowerBound { left.append(side.lowerBound...band.lowerBound) }
                if band.upperBound < side.upperBound { left.append(band.upperBound...side.upperBound) }
                return left
            }
        }
        return sides
    }

    static func swim(from start: (time: Double, y: CGFloat), to target: (time: Double, y: CGFloat, zoom: CGFloat), tolerance: CGFloat,
                     startSlack: CGFloat, radius: CGFloat, bands: [Band], reachScale: CGFloat = 1) -> Bool {
        let fastest = Double(GameTuning.motion.maxRiseSpeed * reachScale)
        // The lap in stretches, one per change of which fish are alongside you, each window in eighths so the taper
        // shows. Over a stretch you must be clear of what's shut as it begins, and clear of what's shut as it ends
        // after swimming as far as you can meanwhile: a band still widening leaves you the time to get out of its way.
        let moments = Set(bands.flatMap { band in
            stride(from: -1.0, through: 1.0, by: 0.25).map { band.center + band.half * $0 } + [band.opens]
        }.filter { $0 > start.time && $0 < target.time } + [start.time, target.time]).sorted()
        var spans = [(start.y - startSlack)...(start.y + startSlack)]
        for (a, b) in zip(moments, moments.dropFirst()) {
            let active = bands.filter { $0.from < b && $0.to > a }
            let zoom = active.map(\.zoom).min() ?? target.zoom
            let bounds = PlayerTimeline.waterBounds(zoom: zoom)
            let water = (bounds.bottom + radius * 0.95)...max(bounds.bottom + radius * 0.95, bounds.top - radius * 0.95)
            let opening = sides(water, shut: active.map { $0.shut(at: max(a, $0.from)) })
            let closing = sides(water, shut: active.map { $0.shut(at: min(b, $0.to)) })
            let through = CGFloat(fastest * (b - a)) / zoom
            let clear = opening.flatMap { side in
                spans.compactMap { span -> ClosedRange<CGFloat>? in
                    let low = max(side.lowerBound, span.lowerBound), high = min(side.upperBound, span.upperBound)
                    return low <= high ? low...high : nil
                }
            }
            spans = closing.flatMap { side in
                clear.compactMap { span -> ClosedRange<CGFloat>? in
                    let low = max(side.lowerBound, span.lowerBound - through), high = min(side.upperBound, span.upperBound + through)
                    return low <= high ? low...high : nil
                }
            }
            if spans.isEmpty { return false }
        }
        return spans.contains { target.y >= $0.lowerBound - tolerance && target.y <= $0.upperBound + tolerance }
    }
}

/// Meetings in time order; node 0 is the run's start.
private struct RouteGraph {
    let meetings: [EncounterCrossing]
    let jellies: [JellyPass]
    let efficiency: CGFloat
    let startRadius: CGFloat
    let startY: CGFloat
    /// Share of your usual rising and falling the routes allow for (Kelp Forest's kelp slows you).
    var reachScale: CGFloat = 1
    /// Other crossings at nearly the same moment, which can block a meal.
    private let simultaneous: [[Int]]
    private final class Steps {
        struct Key: Hashable { let previous: Int; let next: Int; let area: UInt; let least: UInt }
        var known: [Key: Bool] = [:]
    }
    private let steps = Steps()
    private var count: Int { meetings.count }

    init(_ meetings: [EncounterCrossing], jellies: [JellyPass], efficiency: CGFloat, startRadius: CGFloat, startY: CGFloat) {
        self.meetings = meetings
        self.jellies = jellies
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
    /// Bigger is never worse, so routes compare by eaten area. The slack search asks the same question many times over,
    /// so the answers are kept.
    /// `least`: the smallest area a route to the same state could have eaten. Bigger is better for eating, but a
    /// bigger body has less room past the bigger fish on the way, so the threats are checked for the smallest player
    /// who could be here and the meal for the biggest: no route that exists is turned down.
    private func canStep(from previous: Int?, area: CGFloat, least: CGFloat? = nil, to next: Int) -> Bool {
        let least = min(area, least ?? area)
        let key = Steps.Key(previous: previous ?? -1, next: next, area: area.bitPattern, least: least.bitPattern)
        if let known = steps.known[key] { return known }
        let answer = step(from: previous, area: area, least: least, to: next)
        steps.known[key] = answer
        return answer
    }

    private func step(from previous: Int?, area: CGFloat, least: CGFloat, to next: Int) -> Bool {
        let target = meetings[next]
        let player = radius(eatenArea: area), small = radius(eatenArea: least)
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
        // Bigger fish crossing your column on the way: each shuts a band of water for as long as its body is alongside
        // you, and you have to be above or below it then and still make the next meal (Sunset Cove 12's gate needed a
        // meal nobody could dive to between two of them; 15's designed route climbed into a giant).
        let swallowed = previous.map { p -> Double in
            let eaten = CGFloat(meetings[p].radius), before = radius(eatenArea: max(0, area - eaten * eaten))
            return Double(SwallowTiming.duration(sizeRatio: eaten / before, curve: GameTuning.swallowDurationCurve))
        } ?? 0
        let yourSpeed = max(1, (target.distance - (previous.map { meetings[$0].distance } ?? 0)) / elapsed)
        let bands = (((previous ?? -1) + 1)..<next).compactMap { index -> ThreatRoutes.Band? in
            let other = meetings[index]
            guard CGFloat(other.radius) > player, other.time < target.time else { return nil }
            let reach = (small + CGFloat(other.radius)) * GameTuning.collisionScale
            let closing = other.headOn ? yourSpeed + (other.speed ?? 0) : max(yourSpeed * 0.25, yourSpeed - (other.speed ?? 0))
            let half = Double(reach) / closing
            // Swallowing the last meal keeps you safe for a while; the fish is still there once that's over.
            guard other.time + half > fromTime + swallowed else { return nil }
            return ThreatRoutes.Band(center: other.time, half: half, y: CGFloat(other.y), reach: reach, zoom: CGFloat(other.zoom),
                                     opens: fromTime + swallowed)
        }
        let startSlack = previous.map { (player + CGFloat(meetings[$0].radius)) * EncounterAnalyzer.catchTolerance } ?? 0
        let pastThreats = bands.isEmpty || ThreatRoutes.swim(from: (fromTime, fromY), to: (target.time, CGFloat(target.y), CGFloat(target.zoom)),
                                                              tolerance: tolerance, startSlack: startSlack, radius: small, bands: bands, reachScale: reachScale)
        if jellies.isEmpty {
            guard pastThreats else { return false }
            let needed = max(0, abs(CGFloat(target.y) - fromY) - tolerance)
            guard EncounterAnalyzer.verticalReach(seconds: elapsed) * reachScale / CGFloat(target.zoom) >= needed else { return false }
        } else {
            // A bounce off a dome carries you faster than the threat check allows for, so a step that takes one is
            // checked for bells alone, as before.
            let to = (time: target.time, y: CGFloat(target.y), zoom: CGFloat(target.zoom))
            guard pastThreats && JellyRoutes.swim(from: (fromTime, fromY), to: to, tolerance: tolerance, radius: player, jellies: jellies)
                || JellyRoutes.bounce(from: (fromTime, fromY), to: to, tolerance: tolerance, radius: player, jellies: jellies,
                                      startSlack: startSlack)
            else { return false }
        }
        // A bigger fish crossing on top of this one at the same moment makes the meal impossible.
        // A missed fish is still swimming, so this applies even to fish a route skips.
        for index in simultaneous[next] {
            let other = meetings[index]
            guard CGFloat(other.radius) > player else { continue }
            if abs(CGFloat(other.y) - CGFloat(target.y)) < (player + CGFloat(other.radius)) * GameTuning.collisionScale { return false }
        }
        return true
    }

    /// best[i][c]: the most area eaten by a route whose c-th meal is meeting i (c >= 1), and the meal before it;
    /// least[i][c]: the least such area, for the room past the bigger fish on the way.
    private func bestAreas() -> (area: [[CGFloat?]], least: [[CGFloat?]], previous: [[Int?]]) {
        var best = Array(repeating: Array<CGFloat?>(repeating: nil, count: count + 1), count: count)
        var least = best
        var previous = Array(repeating: Array<Int?>(repeating: nil, count: count + 1), count: count)
        for i in 0..<count {
            let r = CGFloat(meetings[i].radius)
            if canStep(from: nil, area: 0, to: i) { best[i][1] = r * r; least[i][1] = r * r }
            for p in 0..<i {
                for c in 1..<count {
                    guard let area = best[p][c], canStep(from: p, area: area, least: least[p][c], to: i) else { continue }
                    if best[i][c + 1].map({ area + r * r > $0 }) ?? true {
                        best[i][c + 1] = area + r * r
                        previous[i][c + 1] = p
                    }
                    let small = least[p][c]! + r * r
                    if least[i][c + 1].map({ small < $0 }) ?? true { least[i][c + 1] = small }
                }
            }
        }
        return (best, least, previous)
    }

    /// Whether a route can reach `target`, ignoring meal counts: the most area a route can have eaten at each meal on
    /// the way, and the least.
    private func reachable(_ target: Int, excluding excluded: Set<Int>) -> Bool {
        var best = Array<CGFloat?>(repeating: nil, count: count), least = best
        if canStep(from: nil, area: 0, to: target) { return true }
        for i in 0..<target where !excluded.contains(i) {
            let r = CGFloat(meetings[i].radius)
            var value: CGFloat? = canStep(from: nil, area: 0, to: i) ? r * r : nil, small = value
            for p in 0..<i where !excluded.contains(p) {
                if let area = best[p], canStep(from: p, area: area, least: least[p], to: i) {
                    if value.map({ area + r * r > $0 }) ?? true { value = area + r * r }
                    if small.map({ least[p]! + r * r < $0 }) ?? true { small = least[p]! + r * r }
                }
            }
            best[i] = value
            least[i] = small
            if let value, canStep(from: i, area: value, least: small, to: target) { return true }
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
        let (best, _, previous) = bestAreas()
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
            } || jellies.contains { pass in
                // Tentacles hang just above it as you eat it.
                let tips = CGFloat(pass.rim - pass.tentacleLength)
                let clear = tips - CGFloat(crossing.y) - r
                return abs(pass.time - crossing.time) <= pass.halfWindow(playerRadius: player) + 0.1
                    && clear >= 0 && clear <= EncounterAnalyzer.dangerGap / CGFloat(crossing.zoom)
            }
            var way: [Int] = [], at = index
            for c in stride(from: fewest, through: 1, by: -1) {
                way.append(meetings[at].fishID)
                guard let before = previous[at][c] else { break }
                at = before
            }
            results.append(.init(crossing: crossing, minimumMeals: fewest - 1, maximumMeals: counts.max()! - 1,
                routes: countRoutes(to: index, meals: fewest - 1), robustSlack: robustSlack(for: index),
                sizeRatio: Double(r / player), danger: danger, fewestRoute: way.reversed()))
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
