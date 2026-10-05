import CoreGraphics
import Foundation
import FishKit
import SpriteKit

/// Difficulty settings for a level whose meetings are planned rather than left to the seed.
/// A lap is a run of segments; each ends at a gate: a fish about your size that becomes edible
/// once you've eaten enough of the segment's food.
struct MeetingSpec: Codable, Equatable {
    /// Two lanes, one high and one low, crossing at about the same moment: you can only take one.
    /// The long lane has more meals, and any danger in the fork crosses beside it.
    struct Fork: Codable, Equatable {
        var long: Int
        var short: Int
    }
    struct Segment: Codable, Equatable {
        /// Lone meals, split around the forks.
        var singles: Int
        var forks: [Fork] = []
        /// How many meals make the gate edible. Fewer than the most you can eat leaves slack, and a
        /// short lane that still reaches `needed` makes the long lane a choice rather than the only way.
        var needed: Int
        /// Meals with a bigger fish crossing close by (long lanes first), when that fish can still be
        /// outgrown by lap two.
        var dangerFoods: Int = 0

        var foods: Int { singles + forks.reduce(0) { $0 + $1.long + $1.short } }
        /// Every single plus each fork's long lane.
        var mostMeals: Int { singles + forks.reduce(0) { $0 + $1.long } }
    }
    var name: String
    var segments: [Segment]
    /// Screens around the world. A wider world gives a longer first lap, so more planned meetings fit
    /// before the camera's zoom-out speeds you around.
    var worldScreens: Double = Double(GameTuning.worldScreens)
    /// Bigger fish crossing in open water on the first lap. They come back around on lap two.
    var extraThreats: Int
    /// Those fish's size against yours at the end of lap one on the fewest-meal route. Near 1, lap two
    /// tests lap one: they're edible only if you ate what every gate needed.
    var lapTwoSize: ClosedRange<Double>
    /// Share of fish swimming toward you (a brief window) rather than being overtaken.
    var headOnShare: Double
    /// Height change between consecutive meals, as a share of the farthest you can swim in the time between them.
    var heightSwing: ClosedRange<Double>
    /// Food radius relative to your size when you reach its segment on the fewest-meal route.
    var foodSize: ClosedRange<Double>
    /// 1: once you've eaten enough, a gate is clearly smaller than you. 0: it's barely smaller.
    var gateMargin: Double
    /// Clear water, in screen points, between a danger meal and the bigger fish beside it.
    var dangerGap: Double
    /// Clear water, in screen points, between an open-water threat and your path from one meal to the next.
    var threatClearance: Double
    /// Screen widths between consecutive meetings.
    var spacing: Double
    var aiSpeed: ClosedRange<Double>
    var aiVertical: Double
    var crossSeconds: Double
    /// Time meetings against the player who barely makes each gate rather than a random lane choice.
    /// With near-size meals, routes grow and zoom apart quickly; precision matters most at the edge, and
    /// players ahead of it have margin to spare.
    var timesTheEdge = false
}

/// A planned fish: where and when you meet it, and the spawn that gets it there on its own free swim.
struct PlannedFish: Codable, Equatable {
    enum Role: String, Codable { case food, gate, threat }
    let id: Int
    let role: Role
    let segment: Int
    /// A fork meal's fork and lane (0 long, 1 short).
    let fork: Int?
    let lane: Int
    /// World points.
    let radius: CGFloat
    /// Your forward distance when you meet it.
    let meetingDistance: CGFloat
    let headOn: Bool
    /// A late head-on fish starts out swimming your way and makes one ordinary turn, off screen, before the meeting.
    let startHeading: CGFloat
    let spawn: CGPoint
    let cruiseSpeed: CGFloat
    let phase: CGFloat
    let turnTimer: CGFloat
    let retargetTimer: CGFloat
    let variant: UInt64
    let styleSeed: UInt64
    /// Eaten on the reference route the meetings were timed against.
    let referenceMeal: Bool

}

struct MeetingPlan {
    let spec: MeetingSpec
    let variation: Int
    let seed: UInt64
    /// Spawn order; ids start at 1.
    let fish: [PlannedFish]
    /// Where each fish meets the reference route.
    let predicted: [EncounterCrossing]
    let analysis: EncounterAnalysis
    /// Player radius after each simulation step on the reference route, for ghost checks.
    let referenceRadii: [CGFloat]
    /// Empty when every planned meeting, gate, and option checked out.
    let issues: [String]

    var level: Level {
        let radii = fish.map { $0.radius / GameTuning.baseRadius }
        var level = Level(spawnGroups: [(fish.count, (radii.min() ?? 1)...(radii.max() ?? 1))],
            aiSpeedRange: CGFloat(spec.aiSpeed.lowerBound)...CGFloat(spec.aiSpeed.upperBound),
            aiVerticalSpeed: CGFloat(spec.aiVertical), screenCrossSeconds: CGFloat(spec.crossSeconds),
            absorptionEfficiency: GameTuning.freeEncounterAbsorption, roamingFoodChain: true)
        level.freeEncounterMovement = true
        level.worldScreens = CGFloat(spec.worldScreens)
        level.meetingPlan = self
        return level
    }

    /// The fewest-meal route: each segment's smallest `needed` foods, then its gate.
    var fewestMealRoute: Set<Int> {
        var ids: Set<Int> = []
        for (index, segment) in spec.segments.enumerated() {
            let foods = fish.filter { $0.role == .food && $0.segment == index }.sorted { $0.radius < $1.radius }
            ids.formUnion(foods.prefix(segment.needed).map(\.id))
            ids.formUnion(fish.filter { $0.role == .gate && $0.segment == index }.map(\.id))
        }
        return ids
    }
    /// A route with the most first-lap meals the analyzer found.
    var fullestRoute: Set<Int> { Set(analysis.fullestRoute) }

    /// Player size per simulation step for a player who eats exactly `meals` at their meetings.
    func radii(eating meals: Set<Int>) -> [CGFloat] {
        PlayerTimeline.reference(meals: fish.filter { meals.contains($0.id) }.map { ($0.meetingDistance, $0.radius) },
            crossSeconds: CGFloat(spec.crossSeconds),
            until: GameTuning.playfieldSize.width * CGFloat(spec.worldScreens) * 1.05).radius
    }

    /// Fewest meals before each planned gate on the designed route.
    var designedGateMeals: [Int: Int] {
        var meals = 0
        var result: [Int: Int] = [:]
        for (index, segment) in spec.segments.enumerated() {
            meals += segment.needed
            if let gate = fish.first(where: { $0.role == .gate && $0.segment == index }) { result[gate.id] = meals }
            meals += 1
        }
        return result
    }
}

enum MeetingPlanner {
    static let designAttempts = 12
    private static let lock = NSLock()
    private static var cache: [String: MeetingPlan] = [:]

    /// Deterministic for a spec and variation; the first design that passes every check, else the best one.
    static func plan(_ spec: MeetingSpec, variation: Int = 0) -> MeetingPlan {
        let key = (try? JSONEncoder().encode(spec)).map { String(decoding: $0, as: UTF8.self) + "#\(variation)" } ?? spec.name
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        lock.unlock()
        let base = GameTuning.spawnSeed &+ 7_000 &+ stableHash(spec.name) &+ UInt64(variation) &* 1_000_003
        var best: MeetingPlan?
        for attempt in 0..<designAttempts {
            let plan = makePlan(spec, variation: variation, seed: base &+ UInt64(attempt) &* 0x9E37_79B9)
            if plan.issues.isEmpty { best = plan; break }
            if best.map({ plan.issues.count < $0.issues.count }) ?? true { best = plan }
        }
        lock.lock()
        cache[key] = best!
        lock.unlock()
        return best!
    }

    static func makePlan(_ spec: MeetingSpec, variation: Int, seed: UInt64) -> MeetingPlan {
        let design = MeetingDesigner.design(spec, seed: seed)
        let solved = MeetingSolver.solve(design.meetings, spec: spec, seed: seed, timeline: design.timeline)
        let analysis = EncounterAnalyzer.analyze(solved.crossings)
        let unchecked = MeetingPlan(spec: spec, variation: variation, seed: seed, fish: solved.fish,
            predicted: solved.crossings, analysis: analysis, referenceRadii: design.timeline.radius, issues: [])
        return MeetingPlan(spec: spec, variation: variation, seed: seed, fish: solved.fish, predicted: solved.crossings,
            analysis: analysis, referenceRadii: design.timeline.radius,
            issues: design.issues + solved.issues + check(unchecked))
    }

    /// The analyzer must find the designed structure: every gate needs exactly its designed meals,
    /// a gate with slack has more than one way in, and every food is on some route.
    static func check(_ plan: MeetingPlan) -> [String] {
        var issues: [String] = []
        let gates = plan.designedGateMeals
        for fish in plan.fish {
            guard let meeting = plan.analysis.meeting(fishID: fish.id) else {
                issues.append("fish \(fish.id) never crosses the first lap"); continue
            }
            switch fish.role {
            case .food:
                if meeting.minimumMeals == nil { issues.append("food \(fish.id) is unreachable") }
            case .gate:
                let segment = plan.spec.segments[fish.segment]
                // Eating bigger food early can save a meal at a later gate; more meals than designed can't.
                if meeting.minimumMeals.map({ $0 > gates[fish.id]! || $0 < gates[fish.id]! - 1 }) ?? true {
                    issues.append("gate \(fish.id) needs \(meeting.minimumMeals.map(String.init) ?? "unreachable") meals, designed \(gates[fish.id] ?? -1)")
                }
                if (segment.mostMeals > segment.needed || !segment.forks.isEmpty) && meeting.routes < 2 {
                    issues.append("gate \(fish.id) has one route")
                }
            case .threat:
                if meeting.minimumMeals == 0 { issues.append("threat \(fish.id) is edible from the start") }
            }
        }
        return issues
    }

    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }
}

/// Player size, zoom, and forward distance for every simulation step of a route, mirroring
/// GameScene's update order: zoom, then movement, then swallowing, then growth, then contact.
struct PlayerTimeline {
    private(set) var zoom: [CGFloat] = [1]
    private(set) var distance: [CGFloat] = [0]
    private(set) var radius: [CGFloat] = [GameTuning.baseRadius]

    var lastStep: Int { distance.count - 1 }

    /// The first step at which the player has covered `target`.
    func step(reaching target: CGFloat) -> Int {
        var low = 0, high = lastStep
        guard distance[high] >= target else { return high }
        while low < high {
            let mid = (low + high) / 2
            if distance[mid] >= target { high = mid } else { low = mid + 1 }
        }
        return low
    }

    static func waterBounds(zoom: CGFloat) -> (bottom: CGFloat, top: CGFloat) {
        let bottom = GameTuning.waterBottomMargin
        let top = GameTuning.playfieldSize.height - GameTuning.waterTopMargin
        let center = (bottom + top) / 2
        return (center - (center - bottom) / zoom, center + (top - center) / zoom)
    }

    /// Meals start when the player reaches each fish (sorted by distance) and complete like real swallows.
    static func reference(meals: [(distance: CGFloat, radius: CGFloat)], crossSeconds: CGFloat, until end: CGFloat) -> PlayerTimeline {
        typealias T = GameTuning
        let dt = T.simulationStep
        let meals = meals.sorted { $0.distance < $1.distance }
        var timeline = PlayerTimeline()
        var zoom: CGFloat = 1, covered: CGFloat = 0
        var radius = T.baseRadius, target = radius, growFrom = radius
        var growElapsed = CGFloat.greatestFiniteMagnitude
        var swallow: (elapsed: CGFloat, duration: CGFloat, prey: CGFloat)?
        var next = 0
        while covered < end {
            let growth = radius / (T.baseRadius * T.zoomStartSize)
            let targetZoom = growth > 1 ? max(T.minZoom, pow(1 / growth, T.zoomExponent)) : 1
            zoom += (targetZoom - zoom) * min(1, dt * T.zoomEase)
            covered += T.playfieldSize.width / crossSeconds / zoom * dt
            if var current = swallow {
                current.elapsed += dt
                if min(1, current.elapsed / current.duration) >= 1 {
                    target = GameRules.grownRadius(predator: target, prey: current.prey,
                        efficiency: T.freeEncounterAbsorption * T.mealGrowthScale)
                    growFrom = radius
                    growElapsed = 0
                    swallow = nil
                } else {
                    swallow = current
                }
            }
            if growElapsed < T.growDuration {
                growElapsed += dt
                let t = min(1, growElapsed / T.growDuration)
                radius = growFrom + (target - growFrom) * (1 - pow(1 - t, 3))
            }
            if swallow == nil, next < meals.count,
               covered >= meals[next].distance - (radius + meals[next].radius) * T.collisionScale {
                swallow = (0, SwallowTiming.duration(sizeRatio: meals[next].radius / radius, curve: T.swallowDurationCurve),
                           meals[next].radius)
                next += 1
            }
            timeline.zoom.append(zoom)
            timeline.distance.append(covered)
            timeline.radius.append(radius)
        }
        return timeline
    }
}

struct DesignedMeeting {
    /// Stable while threats are inserted around the meals.
    var key: Int
    var role: PlannedFish.Role
    var segment: Int
    /// Relative to the player's starting radius.
    var size: CGFloat
    var distance: CGFloat = 0
    /// 0 is the bottom of the water this fish can reach, 1 the top.
    var height: CGFloat = 0.5
    var headOn = false
    var speed: CGFloat = 100
    /// Key of the food this threat crosses beside, and whether it crosses just after it.
    var guards: Int?
    var guardsAfter = false
    /// A fork meal's fork (unique in the level), lane (0 long, 1 short), and place in the lane.
    var fork: Int?
    var lane = 0
    var rank = 0
    /// Eaten on the reference route used for timing.
    var onReferenceRoute = false
}

enum MeetingDesigner {
    typealias T = GameTuning
    static let firstMeetingScreens: CGFloat = 0.6
    /// The last meeting comes this many screens before the lap ends.
    static let lastMeetingMargin: CGFloat = 0.3
    /// A near-equal swallow takes up to 0.8 s; the next meeting waits a beat longer.
    static let gateSwallowSeconds: CGFloat = 1.0
    static let dangerOffsetScreens: CGFloat = 0.07
    /// Seconds between a fork's two lanes crossing: too close to take both.
    static let forkOffsetSeconds: CGFloat = 0.12
    /// Room, in meeting gaps, to reach either lane before a fork and to come back after it.
    static let forkLead: CGFloat = 1.3
    static let heightLimits: ClosedRange<CGFloat> = 0.08...0.92
    static let highLane: ClosedRange<CGFloat> = 0.78...0.92
    static let lowLane: ClosedRange<CGFloat> = 0.08...0.22
    static let middle: ClosedRange<CGFloat> = 0.42...0.58
    /// Screen points of combined body overlap counted on top of swimming reach between meals.
    static let mealHeightTolerance: CGFloat = 20
    /// The first meal (zero-based) a threat may cross beside.
    static let earliestDangerMeal = 3

    static func design(_ spec: MeetingSpec, seed: UInt64) -> (meetings: [DesignedMeeting], timeline: PlayerTimeline, issues: [String]) {
        var rng = SeededGenerator(seed: seed)
        var issues: [String] = []
        var meetings = sizedMeetings(spec, rng: &rng, issues: &issues)
        for i in meetings.indices {
            meetings[i].headOn = Double.random(in: 0..<1, using: &rng) < spec.headOnShare
            meetings[i].speed = CGFloat(Double.random(in: spec.aiSpeed, using: &rng))
        }
        // Space meetings in time: you cross a screen width every `crossSeconds` at any zoom, so equal
        // times are equal gaps on screen. Distances follow from the route's growth, so settle them over a few passes.
        var times = meetingTimes(meetings, spec: spec)
        let order = times.indices.sorted { times[$0] < times[$1] }
        meetings = order.map { meetings[$0] }
        times = order.map { times[$0] }
        var timeline = PlayerTimeline()
        let lastDistance = (CGFloat(spec.worldScreens) - lastMeetingMargin) * T.playfieldSize.width
        for _ in 0..<6 {
            for i in meetings.indices {
                let step = Int((times[i] / T.simulationStep).rounded())
                meetings[i].distance = timeline.lastStep > 0
                    ? timeline.distance[min(step, timeline.lastStep)]
                    : times[i] * T.playfieldSize.width / CGFloat(spec.crossSeconds)
            }
            timeline = PlayerTimeline.reference(
                meals: meetings.filter(\.onReferenceRoute).map { ($0.distance, $0.size * T.baseRadius) },
                crossSeconds: CGFloat(spec.crossSeconds), until: T.playfieldSize.width * CGFloat(spec.worldScreens) * 1.05)
            // Squeeze the lap's meetings into its first pass if they run long.
            let lastTime = CGFloat(timeline.step(reaching: lastDistance)) * T.simulationStep * 0.99
            if let first = times.first, let last = times.last, last > lastTime {
                times = times.map { first + ($0 - first) * (lastTime - first) / (last - first) }
            }
        }
        if let last = meetings.last, last.distance > lastDistance + 1 {
            issues.append("meetings overflow the lap")
        }
        layHeights(&meetings, times: times, spec: spec, timeline: timeline, rng: &rng)
        return (meetings, timeline, issues)
    }

    /// Sizes on the fewest-meal route: whichever lanes you take, any `needed` meals of a segment make
    /// its gate edible, and no `needed - 1` do.
    private static func sizedMeetings(_ spec: MeetingSpec, rng: inout SeededGenerator, issues: inout [String]) -> [DesignedMeeting] {
        let efficiency = T.freeEncounterAbsorption * T.mealGrowthScale
        func grow(_ radius: CGFloat, _ prey: [CGFloat]) -> CGFloat {
            sqrt(radius * radius + efficiency * prey.reduce(0) { $0 + $1 * $1 })
        }
        var fewest: CGFloat = 1, most: CGFloat = 1
        var meetings: [DesignedMeeting] = []
        var dangerFoods: [(key: Int, playerMost: CGFloat)] = []
        var forkCount = 0
        for (segmentIndex, segment) in spec.segments.enumerated() {
            // Lay out the segment's meals: singles before, the forks, singles after.
            var meals: [DesignedMeeting] = []
            let before = (segment.singles + 1) / 2
            func single() -> DesignedMeeting { DesignedMeeting(key: 0, role: .food, segment: segmentIndex, size: 0) }
            meals += (0..<before).map { _ in single() }
            for fork in segment.forks {
                for rank in 0..<max(fork.long, fork.short) {
                    for (lane, length) in [fork.long, fork.short].enumerated() where rank < length {
                        var meal = single()
                        meal.fork = forkCount
                        meal.lane = lane
                        meal.rank = rank
                        meals.append(meal)
                    }
                }
                forkCount += 1
            }
            meals += (before..<segment.singles).map { _ in single() }
            // Every way through: one lane per fork, plus the singles.
            let forkIDs = Array(Set(meals.compactMap(\.fork))).sorted()
            let routes: [[Int]] = (0..<(1 << forkIDs.count)).map { choice in
                meals.indices.filter { i in
                    guard let fork = meals[i].fork else { return true }
                    return meals[i].lane == (choice >> forkIDs.firstIndex(of: fork)! & 1)
                }
            }
            var sizes: [CGFloat] = []
            var gate: CGFloat = 0, enoughRoute: [CGFloat] = [], enoughMeals: [Int] = []
            for _ in 0..<100 {
                sizes = meals.map { _ in fewest * CGFloat(Double.random(in: spec.foodSize, using: &rng)) }
                let viable = routes.filter { $0.count >= segment.needed }.map { route in
                    Array(route.sorted { sizes[$0] < sizes[$1] }.prefix(segment.needed))
                }
                guard let weakestMeals = viable.min(by: { grow(fewest, $0.map { sizes[$0] }) < grow(fewest, $1.map { sizes[$0] }) })
                else { break }
                let weakest = weakestMeals.map { sizes[$0] }
                let short = routes.map { grow(fewest, Array($0.map { sizes[$0] }.sorted().suffix(max(0, segment.needed - 1)))) }.max() ?? fewest
                let lower = short * 1.035, upper = grow(fewest, weakest) * 0.985
                if lower < upper {
                    gate = lower + (upper - lower) * CGFloat(1 - spec.gateMargin)
                    enoughRoute = weakest
                    enoughMeals = weakestMeals
                    break
                }
            }
            if gate == 0 {
                issues.append("segment \(segmentIndex + 1) has no gate size")
                gate = grow(fewest, sizes) * 0.98
            }
            let anyRoute = Set(routes.randomElement(using: &rng) ?? [])
            let referenceRoute = spec.timesTheEdge ? Set(enoughMeals) : anyRoute
            // Danger crosses beside long lanes first, then singles; never in the opening.
            let longLane = meals.indices.filter { meals[$0].fork != nil && meals[$0].lane == 0 }.shuffled(using: &rng)
            let others = meals.indices.filter { meals[$0].fork == nil }.shuffled(using: &rng)
            let danger = Set((longLane + others).filter { meetings.count + $0 >= earliestDangerMeal }.prefix(segment.dangerFoods))
            var playerMost = most
            for (index, var meal) in meals.enumerated() {
                meal.key = meetings.count
                meal.size = sizes[index]
                meal.onReferenceRoute = referenceRoute.contains(index)
                if danger.contains(index) { dangerFoods.append((meal.key, playerMost)) }
                meetings.append(meal)
                playerMost = grow(playerMost, [sizes[index]])
            }
            meetings.append(DesignedMeeting(key: meetings.count, role: .gate, segment: segmentIndex, size: gate,
                                            onReferenceRoute: true))
            let fullest = routes.map { grow(most, $0.map { sizes[$0] }) }.max() ?? most
            most = grow(fullest, [gate])
            fewest = grow(grow(fewest, enoughRoute), [gate])
        }
        // Threats are bigger than even a player who ate everything so far, yet edible by the end of the lap.
        let ceiling = fewest * 0.9
        var key = meetings.count
        // Open-water threats spread between the first gate and the last segment, while there's still
        // a lap to outgrow them; never two in a row, and never inside a fork.
        let gates = meetings.indices.filter { meetings[$0].role == .gate }
        let window = gates.count > 1 ? (gates[0] + 1)...max(gates[0] + 1, gates[gates.count - 2]) : 1...1
        let slots = (0..<spec.extraThreats).map { index -> Int in
            let share = (CGFloat(index) + CGFloat.random(in: 0.25...0.75, using: &rng)) / CGFloat(max(1, spec.extraThreats))
            return window.lowerBound + Int((CGFloat(window.count) * share).rounded(.down))
        }
        for slot in Set(slots).sorted(by: >) where gates.count > 1 {
            var position = min(slot, window.upperBound)
            while position < meetings.count, let fork = meetings[position].fork, meetings[position - 1].fork == fork { position += 1 }
            let playerMost = meetings[..<position].filter { $0.role != .threat && $0.lane == 0 }.reduce(CGFloat(1)) { grow($0, [$1.size]) }
            let lower = playerMost * 1.12
            let size = fewest * CGFloat(Double.random(in: spec.lapTwoSize, using: &rng))
            // Late in the lap even a player who ate everything may already be big enough; skip rather than fail.
            guard lower < size, size < fewest * 0.985 else { continue }
            meetings.insert(DesignedMeeting(key: key, role: .threat, segment: meetings[min(position, meetings.count - 1)].segment, size: size),
                            at: position)
            key += 1
        }
        for (food, playerMost) in dangerFoods {
            let lower = playerMost * 1.12
            guard let index = meetings.firstIndex(where: { $0.key == food }) else { continue }
            guard lower < ceiling else {
                if meetings[index].segment < spec.segments.count - 1 { issues.append("no room for the threat beside food \(food)") }
                continue
            }
            var threat = DesignedMeeting(key: key, role: .threat, segment: meetings[index].segment,
                size: CGFloat.random(in: lower...min(ceiling, lower * 1.2), using: &rng), guards: food)
            threat.guardsAfter = Bool.random(using: &rng)
            meetings.insert(threat, at: index + 1)
            key += 1
        }
        return meetings
    }

    /// Seconds into the run for each meeting: even spacing between meals; a fork's lanes a beat apart,
    /// with room to reach either lane and come back; room after a gate for its long swallow; threats a
    /// short beat from the meal they guard, open-water threats between meals. Not yet in time order.
    private static func meetingTimes(_ meetings: [DesignedMeeting], spec: MeetingSpec) -> [CGFloat] {
        let screen = CGFloat(spec.crossSeconds)
        let spacing = CGFloat(spec.spacing) * screen
        var times = Array(repeating: CGFloat(0), count: meetings.count)
        var cursor = firstMeetingScreens * screen
        var previous: DesignedMeeting?
        for i in meetings.indices where meetings[i].role != .threat {
            let meal = meetings[i]
            defer { previous = meal }
            guard let last = previous else { times[i] = cursor; continue }
            if let fork = meal.fork, last.fork == fork {
                // The other lane of this rank crosses a beat after; the next rank, a full gap after this one.
                if meal.rank == last.rank { times[i] = cursor + forkOffsetSeconds; continue }
                cursor += spacing
            } else {
                var gap = meal.fork != nil || last.fork != nil ? spacing * forkLead : spacing
                if last.role == .gate { gap = max(gap, gateSwallowSeconds) }
                cursor += gap
            }
            times[i] = cursor
        }
        for i in meetings.indices where meetings[i].role == .threat {
            if let guarded = meetings[i].guards, let food = meetings.firstIndex(where: { $0.key == guarded }) {
                times[i] = times[food] + (meetings[i].guardsAfter ? 1 : -1) * dangerOffsetScreens * screen
            } else {
                let before = meetings[..<i].lastIndex { $0.role != .threat }
                let after = meetings[(i + 1)...].firstIndex { $0.role != .threat }
                times[i] = switch (before, after) {
                case let (before?, after?): (times[before] + times[after]) / 2
                case let (before?, nil): times[before] + spacing / 2
                case let (nil, after?): max(0, times[after] - spacing / 2)
                default: cursor
                }
            }
        }
        return times
    }

    /// Single meals walk up and down by a share of the farthest you can swim between them. A fork's
    /// lanes sit near the top and bottom, too far apart to switch, and the meals either side of a fork
    /// stay mid-water so both lanes are in reach.
    private static func layHeights(_ meetings: inout [DesignedMeeting], times: [CGFloat], spec: MeetingSpec,
                                   timeline: PlayerTimeline, rng: inout SeededGenerator) {
        let screenWater = T.playfieldSize.height - T.waterTopMargin - T.waterBottomMargin
        func usable(_ meeting: DesignedMeeting) -> (low: CGFloat, high: CGFloat) {
            let bounds = PlayerTimeline.waterBounds(zoom: timeline.zoom[timeline.step(reaching: meeting.distance)])
            let r = meeting.size * T.baseRadius
            return (bounds.bottom + r, bounds.top - r)
        }
        let meals = meetings.indices.filter { meetings[$0].role != .threat }
        var longLaneHigh: [Int: Bool] = [:]
        var height = CGFloat.random(in: 0.35...0.65, using: &rng)
        for (position, i) in meals.enumerated() {
            if let fork = meetings[i].fork {
                let high = longLaneHigh[fork] ?? Bool.random(using: &rng)
                longLaneHigh[fork] = high
                height = CGFloat.random(in: high == (meetings[i].lane == 0) ? highLane : lowLane, using: &rng)
            } else if position > 0 {
                let neighbors = [meals[position - 1]] + (position + 1 < meals.count ? [meals[position + 1]] : [])
                if neighbors.contains(where: { meetings[$0].fork != nil }) {
                    height = CGFloat.random(in: middle, using: &rng)
                } else {
                    let reach = EncounterAnalyzer.verticalReach(seconds: Double(times[i] - times[meals[position - 1]]))
                    let farthest = min(heightLimits.upperBound - heightLimits.lowerBound, (reach + mealHeightTolerance) / screenWater)
                    let swing = farthest * CGFloat(Double.random(in: spec.heightSwing, using: &rng))
                    var sign: CGFloat = Bool.random(using: &rng) ? 1 : -1
                    if !heightLimits.contains(height + sign * swing) { sign = -sign }
                    height = (height + sign * swing).clamped(heightLimits.lowerBound, heightLimits.upperBound)
                }
            } else if position + 1 < meals.count, meetings[meals[1]].fork != nil {
                height = CGFloat.random(in: middle, using: &rng)
            }
            meetings[i].height = height
        }
        for i in meetings.indices where meetings[i].role == .threat {
            let range = usable(meetings[i])
            guard let guarded = meetings[i].guards else {
                // Open water: well clear of a straight swim between the meals before and after.
                let before = meetings[..<i].lastIndex { $0.role != .threat }
                let after = meetings[(i + 1)...].firstIndex { $0.role != .threat }
                func y(_ index: Int) -> CGFloat {
                    let bounds = usable(meetings[index])
                    return bounds.low + (bounds.high - bounds.low) * meetings[index].height
                }
                let pathY: CGFloat
                switch (before, after) {
                case let (before?, after?):
                    let share = (times[i] - times[before]) / max(0.01, times[after] - times[before])
                    pathY = y(before) + (y(after) - y(before)) * share
                case let (before?, nil): pathY = y(before)
                case let (nil, after?): pathY = y(after)
                default: pathY = (range.low + range.high) / 2
                }
                let zoom = timeline.zoom[timeline.step(reaching: meetings[i].distance)]
                let offset = (meetings[i].size + 1.5) * T.baseRadius * T.collisionScale + CGFloat(spec.threatClearance) / zoom
                let fits = [CGFloat(1), -1].map { side in (side, (pathY + side * offset - range.low) / max(1, range.high - range.low)) }
                    .filter { (0...1).contains($0.1) }
                meetings[i].height = (fits.randomElement(using: &rng)?.1 ?? (pathY > (range.low + range.high) / 2 ? 0 : 1))
                continue
            }
            guard let food = meetings.first(where: { $0.key == guarded }) else { continue }
            let foodRange = usable(food)
            let foodY = foodRange.low + (foodRange.high - foodRange.low) * food.height
            let zoom = timeline.zoom[timeline.step(reaching: food.distance)]
            let offset = (food.size + meetings[i].size) * T.baseRadius * T.collisionScale + CGFloat(spec.dangerGap) / zoom
            var sides: [CGFloat] = [1, -1]
            if Bool.random(using: &rng) { sides.reverse() }
            let fraction: (CGFloat) -> CGFloat = { side in (foodY + side * offset - range.low) / max(1, range.high - range.low) }
            let side = sides.first { (0...1).contains(fraction($0)) } ?? sides[0]
            meetings[i].height = fraction(side).clamped(0, 1)
        }
    }
}

enum MeetingSolver {
    typealias T = GameTuning
    /// World points a planned fish may miss its meeting height by (scaled up as the camera zooms out).
    static let heightTolerance: CGFloat = 12
    static let attempts = 1_200
    /// Extra clear water planned paths keep before either fish has been passed, beyond the separation reach.
    static let contactMargin: CGFloat = 4
    static let contactPenalty: CGFloat = 50
    /// Fish you overtake swim within this share of the slow end of the speed range.
    static let sameDirectionSpeedShare = 0.3
    /// About how long FreeSwim's easing takes to reverse a fish's swim.
    static let turnSeconds: CGFloat = 1.6
    private static let unwrapped = WrappedWorld(width: 10_000_000)

    static func solve(_ meetings: [DesignedMeeting], spec: MeetingSpec, seed: UInt64,
                      timeline: PlayerTimeline) -> (fish: [PlannedFish], crossings: [EncounterCrossing], issues: [String]) {
        let width = T.playfieldSize.width
        let worldWidth = width * CGFloat(spec.worldScreens)
        let meetSteps = meetings.map { timeline.step(reaching: $0.distance) }
        let releaseSteps = meetings.map { timeline.step(reaching: $0.distance + width * T.freeEncounterReleaseScreens) }
        let horizon = releaseSteps.max() ?? 0
        var placed: [(fish: PlannedFish, path: [CGPoint], release: Int)] = []
        var crossings: [EncounterCrossing] = []
        var issues: [String] = []

        for (index, meeting) in meetings.enumerated() {
            let id = index + 1
            let radius = meeting.size * T.baseRadius
            let meetStep = meetSteps[index]
            let meetTime = CGFloat(meetStep) * T.simulationStep
            let zoom = timeline.zoom[meetStep]
            let bounds = PlayerTimeline.waterBounds(zoom: zoom)
            let targetY = bounds.bottom + radius + (bounds.top - bounds.bottom - 2 * radius) * meeting.height
            let start = PlayerTimeline.waterBounds(zoom: 1)
            let clearAhead = width * (meeting.size >= T.spawnDangerRatio ? T.spawnClearAheadDanger : T.spawnClearAheadSmall)
            var chosen: (fish: PlannedFish, path: [CGPoint], error: CGFloat)?
            var fallback: (fish: PlannedFish, path: [CGPoint], error: CGFloat)?
            let world = WrappedWorld(width: worldWidth)
            let tolerance = heightTolerance / zoom
            for attempt in 0..<attempts {
                var draw = SeededGenerator(seed: seed &+ UInt64(id) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(attempt) &* 0xBF58_476D_1CE4_E5B9)
                let headOn = attempt < attempts / 2 ? meeting.headOn : !meeting.headOn
                // A fish swimming your way near your speed creeps toward you for seconds, as if fleeing;
                // slow ones are quick, lazy overtakes.
                let speeds = headOn ? spec.aiSpeed
                    : spec.aiSpeed.lowerBound...(spec.aiSpeed.lowerBound + (spec.aiSpeed.upperBound - spec.aiSpeed.lowerBound) * sameDirectionSpeedShare)
                let speed = attempt % (attempts / 2) < 100 && speeds.contains(Double(meeting.speed)) ? meeting.speed
                    : CGFloat(Double.random(in: speeds, using: &draw))
                let phase = CGFloat.random(in: 0..<(2 * .pi), using: &draw)
                // A head-on fish met late would already have crossed your path, so every other try starts it
                // swimming your way and turns it while it's still far off screen. Otherwise no turn before the meeting.
                let closing = width / CGFloat(spec.crossSeconds) / zoom + speed
                let onScreenSeconds = (width * (1 - T.playerScreenX) / zoom + T.plannerContactScreenMargin) / closing
                let latestTurn = meetTime - onScreenSeconds - turnSeconds
                let earliestTurn = max(0.3, meetTime - T.aiTurnIntervalRange.lowerBound + 0.5)
                let turns = headOn && attempt % 2 == 1 && latestTurn > earliestTurn
                let turnTimer = turns ? CGFloat.random(in: earliestTurn...latestTurn, using: &draw)
                    : CGFloat.random(in: max(T.aiTurnIntervalRange.lowerBound, meetTime + 1.5)...max(T.aiTurnIntervalRange.upperBound, meetTime + 6), using: &draw)
                let startHeading: CGFloat = headOn && !turns ? -1 : 1
                let retargetTimer = CGFloat.random(in: T.aiRetargetRange, using: &draw)
                var startY = CGFloat.random(in: (start.bottom + radius)...(start.top - radius), using: &draw)
                // Horizontal travel ignores the movement stream, so infeasible spawns are rejected cheaply.
                let spawnX = timeline.distance[meetStep] - horizontalTravel(heading: startHeading, speed: speed, phase: phase,
                                                                             turnTimer: turnTimer, steps: meetStep)
                guard spawnX >= clearAhead, spawnX <= worldWidth - width * T.spawnClearBehind else { continue }
                var candidate = PlannedFish(id: id, role: meeting.role, segment: meeting.segment, fork: meeting.fork,
                    lane: meeting.lane, radius: radius,
                    meetingDistance: meeting.distance, headOn: headOn, startHeading: startHeading,
                    spawn: CGPoint(x: 0, y: startY), cruiseSpeed: speed,
                    phase: phase, turnTimer: turnTimer, retargetTimer: retargetTimer, variant: UInt64(attempt), styleSeed: 0,
                    referenceMeal: meeting.onReferenceRoute)
                guard var early = path(candidate, seed: seed, vertical: CGFloat(spec.aiVertical), steps: meetStep, timeline: timeline) else { continue }
                var error = early[meetStep].y - targetY
                // Starting height carries through until the fish settles on its own targets: nudge it toward the meeting.
                for _ in 0..<2 where abs(error) > tolerance && abs(error) < 150 {
                    let nudged = (startY - error).clamped(start.bottom + radius, start.top - radius)
                    guard nudged != startY else { break }
                    let retry = candidate.moved(to: CGPoint(x: 0, y: nudged))
                    guard let path = path(retry, seed: seed, vertical: CGFloat(spec.aiVertical), steps: meetStep, timeline: timeline),
                          abs(path[meetStep].y - targetY) < abs(error) else { break }
                    startY = nudged; candidate = retry; early = path; error = path[meetStep].y - targetY
                }
                let fish = candidate.moved(to: CGPoint(x: timeline.distance[meetStep] - early[meetStep].x, y: startY))
                if turns {
                    // Nobody sees it swim away or turn: it's off screen until it's well into its approach.
                    let settled = min(meetStep, Int((turnTimer + turnSeconds) / T.simulationStep))
                    guard !(0...settled).contains(where: { visible(fish.spawn.x + early[$0].x, step: $0, timeline: timeline, world: world) }) else { continue }
                }
                if abs(error) > tolerance {
                    if fallback.map({ abs(error) < $0.error }) ?? true { fallback = (fish, early, abs(error)) }
                    continue
                }
                guard let full = path(candidate, seed: seed, vertical: CGFloat(spec.aiVertical), steps: horizon, timeline: timeline) else { continue }
                var clear = true
                for other in placed where clear {
                    let reach = (radius + other.fish.radius) * T.collisionScale + T.encounterSeparationPadding + contactMargin
                    // Only fish you haven't met avoid each other, and only on screen; fish you've passed give way.
                    for step in 0...min(horizon, releaseSteps[index], other.release) {
                        let x = fish.spawn.x + full[step].x
                        let dx = world.delta(from: other.path[step].x, to: x)
                        let dy = full[step].y - other.path[step].y
                        guard dx * dx + dy * dy <= reach * reach else { continue }
                        if visible(x, step: step, timeline: timeline, world: world) || visible(other.path[step].x, step: step, timeline: timeline, world: world) {
                            clear = false; break
                        }
                    }
                }
                let route = full.map { CGPoint(x: fish.spawn.x + $0.x, y: $0.y) }
                if clear { chosen = (fish, route, abs(error)); break }
                // Brushing past another fish before you meet it nudges both paths: worse than a small height miss.
                if fallback.map({ abs(error) + contactPenalty < $0.error }) ?? true { fallback = (fish, early, abs(error) + contactPenalty) }
            }
            let result: (fish: PlannedFish, path: [CGPoint], error: CGFloat)
            if let chosen {
                result = chosen
            } else if let fallback, let full = path(fallback.fish, seed: seed, vertical: CGFloat(spec.aiVertical), steps: horizon, timeline: timeline) {
                // Keep every planned fish so ids stay contiguous; the issue marks the plan as imperfect.
                result = (fallback.fish, full.map { CGPoint(x: fallback.fish.spawn.x + $0.x, y: $0.y) }, fallback.error)
                issues.append("fish \(id) is off its plan (score \(Int(result.error)))")
            } else {
                issues.append("fish \(id) has no valid spawn")
                continue
            }
            placed.append((result.fish, result.path, releaseSteps[index]))
            crossings.append(EncounterCrossing(fishID: id, time: Double(meetTime), distance: Double(timeline.distance[meetStep]),
                y: Double(result.path[min(meetStep, result.path.count - 1)].y), radius: Double(radius),
                headOn: result.fish.headOn, zoom: Double(zoom)))
        }
        return (styled(placed.map(\.fish), seed: seed), crossings, issues)
    }

    /// Within the reference route's screen at `step`, plus the planner's margin.
    private static func visible(_ x: CGFloat, step: Int, timeline: PlayerTimeline, world: WrappedWorld) -> Bool {
        let zoom = timeline.zoom[step]
        let dx = world.delta(from: timeline.distance[step], to: x)
        return dx > -T.playfieldSize.width * T.playerScreenX / zoom - T.plannerContactScreenMargin
            && dx < T.playfieldSize.width * (1 - T.playerScreenX) / zoom + T.plannerContactScreenMargin
    }

    /// FreeSwim's horizontal motion through at most one turn: it doesn't use the movement stream, so it's
    /// a cheap filter. The solver still takes the spawn from the full simulation.
    static func horizontalTravel(heading start: CGFloat, speed: CGFloat, phase: CGFloat, turnTimer: CGFloat, steps: Int) -> CGFloat {
        var heading = start, timer = turnTimer
        var vx = heading * speed, x: CGFloat = 0
        for step in stride(from: 1, through: steps, by: 1) {
            timer -= T.simulationStep
            if timer <= 0 { heading = -heading; timer = .greatestFiniteMagnitude }
            let target = heading * speed * (1 + 0.15 * sin(CGFloat(step) * T.simulationStep * 0.7 + phase))
            vx += (target - vx) * min(1, T.simulationStep * 1.5)
            x += vx * T.simulationStep
        }
        return x
    }

    /// The fish's free swim in isolation, relative to its spawn x. Nil if it can't be simulated.
    static func path(_ fish: PlannedFish, seed: UInt64, vertical: CGFloat, steps: Int, timeline: PlayerTimeline) -> [CGPoint]? {
        guard steps <= timeline.lastStep else { return nil }
        let f = Fish(id: fish.id, isPlayer: false, position: CGPoint(x: 0, y: fish.spawn.y), radius: fish.radius)
        f.heading = fish.startHeading
        f.cruiseSpeed = fish.cruiseSpeed
        f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
        f.facing = f.heading
        f.targetY = fish.spawn.y
        f.retargetTimer = fish.retargetTimer
        f.turnTimer = fish.turnTimer
        f.phase = fish.phase
        var rng = FreeSwim.movementGenerator(ecosystemSeed: seed, id: fish.id, variant: fish.variant)
        var points = [CGPoint(x: 0, y: fish.spawn.y)]
        points.reserveCapacity(steps + 1)
        for step in stride(from: 1, through: steps, by: 1) {
            let bounds = PlayerTimeline.waterBounds(zoom: timeline.zoom[step])
            let minY = bounds.bottom + fish.radius
            let maxY = max(minY, bounds.top - fish.radius)
            let velocity = FreeSwim.steer(f, dt: T.simulationStep, clock: CGFloat(step) * T.simulationStep,
                minY: minY, maxY: maxY, verticalSpeed: vertical, leash: nil, rng: &rng)
            FreeSwim.integrate(f, velocity: velocity, dt: T.simulationStep, minY: minY, maxY: maxY, world: unwrapped)
            let x = f.position.x > unwrapped.width / 2 ? f.position.x - unwrapped.width : f.position.x
            points.append(CGPoint(x: x, y: f.position.y))
        }
        return points
    }

    /// Neighboring meetings get different colors, so a route reads as "the purple one, then the green one".
    private static func styled(_ fish: [PlannedFish], seed: UInt64) -> [PlannedFish] {
        var colors: [SKColor] = []
        return fish.map { planned in
            var chosen: UInt64 = 0
            for attempt in UInt64(0)..<64 {
                let candidate = seed &+ UInt64(planned.id) &* 0x94D0_49BB_1331_11EB &+ attempt
                var generator = SeededGenerator(seed: candidate)
                let body = FishStyle.random(using: &generator).body
                chosen = candidate
                if !colors.suffix(2).contains(where: { $0.isEqual(body) }) { break }
            }
            var generator = SeededGenerator(seed: chosen)
            colors.append(FishStyle.random(using: &generator).body)
            return planned.styled(chosen)
        }
    }
}

private extension PlannedFish {
    func moved(to spawn: CGPoint) -> PlannedFish {
        PlannedFish(id: id, role: role, segment: segment, fork: fork, lane: lane, radius: radius,
            meetingDistance: meetingDistance, headOn: headOn,
            startHeading: startHeading, spawn: spawn, cruiseSpeed: cruiseSpeed, phase: phase, turnTimer: turnTimer,
            retargetTimer: retargetTimer, variant: variant, styleSeed: styleSeed, referenceMeal: referenceMeal)
    }
    func styled(_ seed: UInt64) -> PlannedFish {
        PlannedFish(id: id, role: role, segment: segment, fork: fork, lane: lane, radius: radius,
            meetingDistance: meetingDistance, headOn: headOn,
            startHeading: startHeading, spawn: spawn, cruiseSpeed: cruiseSpeed, phase: phase, turnTimer: turnTimer,
            retargetTimer: retargetTimer, variant: variant, styleSeed: seed, referenceMeal: referenceMeal)
    }
}
