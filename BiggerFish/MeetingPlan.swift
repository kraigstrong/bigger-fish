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
        /// A jelly splits the lanes: the long lane starts on its dome and climbs with the bounce, the
        /// short lane passes under its tentacles. Needs `long` of at least 2. Optional so older plans decode.
        var bounce: Bool? = nil

        var splitsOnAJelly: Bool { bounce == true }
    }
    struct Segment: Codable, Equatable {
        /// Lone meals, split around the forks.
        var singles: Int
        var forks: [Fork] = []
        /// How many meals make the gate edible. Fewer than the most you can eat leaves slack, and a
        /// short lane that still reaches `needed` makes the long lane a choice rather than the only way.
        var needed: Int
        /// Meals with a bigger fish crossing close by, long lanes first. Near the end of the lap, where no
        /// fish could be both bigger than you and outgrown by lap two, it crosses beside an earlier meal.
        var dangerFoods: Int = 0
        /// Pairs of extra singles that open the segment: a meal on a jelly's dome, then one high above it
        /// that only the bounce gets you to in time. Optional so older plans decode.
        var bounceMeals: Int? = nil

        var bouncePairs: Int { bounceMeals ?? 0 }
        var foods: Int { singles + 2 * bouncePairs + forks.reduce(0) { $0 + $1.long + $1.short } }
        /// Every single plus each fork's long lane.
        var mostMeals: Int { singles + 2 * bouncePairs + forks.reduce(0) { $0 + $1.long } }
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
    /// A big fish crosses just above and just below each gate, too tight to slip between, so you can't
    /// dodge a gate and save it for lap two: eat it or be eaten. Skipped when the wall couldn't be
    /// outgrown by the end of the lap.
    var walledGates = false
    /// Time meetings against the player who barely makes each gate rather than a random lane choice.
    /// With near-size meals, routes grow and zoom apart quickly; precision matters most at the edge, and
    /// players ahead of it have margin to spare.
    var timesTheEdge = false
    /// Drifting jellyfish placed around the meetings (Jelly Bloom 2). Optional so older plans decode.
    var jellies: JellySpec? = nil
    /// Kelp Forest's kelp: it slows you, so the plan allows for slower rising and falling everywhere.
    var kelp: KelpSpec? = nil
    /// You're in kelp for about its share of any swim.
    var reachScale: CGFloat { kelp.map { 1 - CGFloat($0.coverage) * (1 - GameTuning.kelpDrag) } ?? 1 }
}

/// Jellyfish for a planned level: their size, and which meetings they sit beside.
struct JellySpec: Codable, Equatable {
    var radius: Double = 40
    var tentacleLength: Double = 70
    var night = false
    /// The second meal bounces off the first jelly while it's on screen ahead of you, to show what bells do.
    var demoBounce = false
    /// Meals sitting on a jelly's dome as you pass it: you bounce as you eat.
    var pockets = 0
    /// Meals with stinging tentacles hanging just above them.
    var stingMeals = 0
    /// Clear water, in screen points, between a sting meal and the tentacles above it (or under a split fork).
    var stingGap: Double = 26
    /// Walled gates get a jelly's tentacles as their upper wall instead of a big fish.
    var tentacleWalls = false
    /// Jellies in open water, this many screen points clear of a straight swim between the meals around them.
    var open = 0
    var openClearance: Double = 60
    /// Open-water jellies that don't fit between two quiet meals go anywhere along the lap clear of every
    /// swim between nearby meals, so a level can be thick with bells. Optional so older plans decode.
    var scattered: Bool? = nil
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
    /// A meal high above a pocket meal (this fish id) that only the pocket's bounce reaches in time.
    var bounceFrom: Int? = nil
    /// Kelp Forest: your forward distance when this fish appears, just off screen (0: there from the start),
    /// swimming straight at its meeting height from `spawn`. Nil: there from the start on its own free swim.
    var appearsAt: CGFloat? = nil
    /// Kelp Forest: the path from `spawn` to the meeting, when it isn't a straight line.
    var approach: Approach? = nil
}

/// How a Kelp Forest fish gets from where it appears to its meeting: gliding in from another height, weaving
/// and settling, or swimming away before turning toward you. Every path ends exactly at the meeting, then
/// carries straight on.
struct Approach: Codable, Equatable {
    enum Style: String, Codable { case straight, glide, weave, turn }
    var style: Style
    /// Where you meet it (world point) and the seconds from appearing to then.
    var meeting: CGPoint
    var seconds: CGFloat
    /// Glide: how far above (+) or below its meeting height it appears. Weave: how far it strays either way.
    var height: CGFloat = 0
    /// Weave: how many sways it makes, settling as it reaches you.
    var waves: CGFloat = 0
    var phase: CGFloat = 0
    /// Turn: it swims away from you at this speed, then turns toward you this many seconds before the meeting.
    var awaySpeed: CGFloat = 0
    var turnBefore: CGFloat = 0

    /// Its offset from the meeting point `time` seconds after appearing, for a fish meeting you at `speed`
    /// going `heading` (-1: toward you).
    func offset(at time: CGFloat, heading: CGFloat, speed: CGFloat) -> CGVector {
        CGVector(dx: Self.dx(beforeMeeting: seconds - time, style: style, heading: heading, speed: speed,
                             awaySpeed: awaySpeed, turnBefore: turnBefore),
                 dy: dy(progress: min(1, max(0, time / max(seconds, 0.001)))))
    }

    /// Horizontal offset `remaining` seconds before the meeting (negative: after it). It depends only on
    /// the time left, so the planner can find where a fish must appear before knowing its whole path.
    static func dx(beforeMeeting remaining: CGFloat, style: Style, heading: CGFloat, speed: CGFloat,
                   awaySpeed: CGFloat, turnBefore: CGFloat) -> CGFloat {
        guard style == .turn, remaining > turnBefore else { return -heading * speed * remaining }
        return -heading * speed * turnBefore + heading * awaySpeed * (remaining - turnBefore)
    }

    private func dy(progress u: CGFloat) -> CGFloat {
        switch style {
        case .straight, .turn: 0
        case .glide: height * (1 - u * u * (3 - 2 * u))
        case .weave: height * sin(2 * .pi * waves * u + phase) * (1 - u) * (1 - u)
        }
    }
}

/// A Kelp Forest level's kelp: columns from the floor to the surface, which you can't swim over, this many
/// screens wide and this many screens of open water apart.
struct KelpSpec: Codable, Equatable {
    var columns: Double
    var gap: Double
    /// Share of the lap that's kelp.
    var coverage: Double { columns / (columns + gap) }
}

/// A kelp column from the floor to the surface, `halfWidth` either side of `x`. Inside it you rise and fall
/// slowly, and other fish show only as silhouettes.
struct PlannedKelp: Codable, Equatable {
    let x: CGFloat
    let halfWidth: CGFloat
}

/// A jellyfish the planner placed: the home it drifts around, and the meeting it was placed for.
struct PlannedJelly: Codable, Equatable {
    enum Role: String, Codable { case demo, pocket, sting, wall, open }
    let role: Role
    let origin: CGPoint
    let phase: CGFloat
    /// The planned fish it sits beside (the demo: the fish that bounces off it).
    let fishID: Int?
}

/// Every planned jelly's position at every simulation step, as GameScene drifts them.
struct JellyTrack {
    let layout: JellyLayout
    let world: WrappedWorld
    /// [step][jelly]
    let positions: [[CGPoint]]

    init(_ jellies: [PlannedJelly], spec: JellySpec, worldWidth: CGFloat, steps: Int) {
        layout = JellySpec.layout(spec, count: jellies.count)
        let world = WrappedWorld(width: worldWidth)
        self.world = world
        positions = (0...steps).map { step in
            jellies.map { JellyDrift.position(origin: $0.origin, phase: $0.phase, time: CGFloat(step) * GameTuning.simulationStep,
                                              screenWidth: GameTuning.playfieldSize.width, world: world) }
        }
    }
}

extension JellySpec {
    static func layout(_ spec: JellySpec, count: Int) -> JellyLayout {
        var layout = JellyLayout(count: count, radius: CGFloat(spec.radius), tentacleLength: CGFloat(spec.tentacleLength),
                                 sway: 0, night: spec.night)
        layout.drifts = true
        return layout
    }
}

struct MeetingPlan: Codable {
    let spec: MeetingSpec
    let variation: Int
    let seed: UInt64
    /// Spawn order; ids start at 1.
    let fish: [PlannedFish]
    /// Where each fish meets the reference route.
    let predicted: [EncounterCrossing]
    let analysis: EncounterAnalysis
    /// Empty when every planned meeting, gate, and option checked out.
    let issues: [String]
    /// Jelly Bloom 2's jellies, in the order GameScene spawns them. Optional so older plans decode.
    var jellies: [PlannedJelly]? = nil
    /// Kelp Forest's kelp columns.
    var kelp: [PlannedKelp]? = nil

    var level: Level {
        let radii = fish.map { $0.radius / GameTuning.baseRadius }
        var level = Level(spawnGroups: [(fish.count, (radii.min() ?? 1)...(radii.max() ?? 1))],
            aiSpeedRange: CGFloat(spec.aiSpeed.lowerBound)...CGFloat(spec.aiSpeed.upperBound),
            aiVerticalSpeed: CGFloat(spec.aiVertical), screenCrossSeconds: CGFloat(spec.crossSeconds),
            absorptionEfficiency: GameTuning.freeEncounterAbsorption, roamingFoodChain: true)
        level.freeEncounterMovement = true
        level.worldScreens = CGFloat(spec.worldScreens)
        if let jellySpec = spec.jellies, let jellies, !jellies.isEmpty {
            level.jellies = JellySpec.layout(jellySpec, count: jellies.count)
        }
        level.meetingPlan = self
        return level
    }

    /// Where the reference route passes each jelly on the first lap.
    var jellyPasses: [JellyPass] {
        guard let jellySpec = spec.jellies, let jellies, !jellies.isEmpty else { return [] }
        let timeline = PlayerTimeline.reference(meals: fish.filter(\.referenceMeal).map { ($0.meetingDistance, $0.radius) },
            crossSeconds: CGFloat(spec.crossSeconds), until: GameTuning.playfieldSize.width * CGFloat(spec.worldScreens) * 1.05)
        return MeetingPlanner.jellyPasses(jellies, spec: jellySpec, crossSeconds: CGFloat(spec.crossSeconds),
            worldWidth: GameTuning.playfieldSize.width * CGFloat(spec.worldScreens), timeline: timeline)
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

    /// Player radius after each simulation step on the route the meetings were timed against, for ghost checks.
    var referenceRadii: [CGFloat] { radii(eating: Set(fish.filter(\.referenceMeal).map(\.id))) }

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
    /// Jelly levels are harder to solve cleanly, so they try more layouts.
    static let jellyDesignAttempts = 36
    /// A quick plan for a playtest tries only this many layouts: about a minute for a jelly level.
    static let quickDesignAttempts = 6
    private static let lock = NSLock()
    private static var cache: [String: MeetingPlan] = [:]
    private static var inFlight: [String: DispatchGroup] = [:]

    /// Deterministic for a spec and variation; the first design that passes every check, else the best one.
    /// Cached in memory. Reef Lab's own levels ship pre-planned (`ReefLabPlans.json`); this plans the tuner's
    /// other variations and regenerates that file.
    /// `attempts` overrides how many layouts it tries (`quickDesignAttempts` for a playtest).
    static func plan(_ spec: MeetingSpec, variation: Int = 0, attempts: Int? = nil) -> MeetingPlan {
        let key = cacheKey(spec, variation: variation) + (attempts.map { "/\($0)" } ?? "")
        lock.lock()
        if let cached = cache[key] { lock.unlock(); return cached }
        // Another thread is already planning this one (the launch-time background pass): wait for it.
        if let pending = inFlight[key] {
            lock.unlock()
            pending.wait()
            return plan(spec, variation: variation, attempts: attempts)
        }
        let done = DispatchGroup()
        done.enter()
        inFlight[key] = done
        lock.unlock()
        defer {
            lock.lock(); inFlight[key] = nil; lock.unlock()
            done.leave()
        }
        let base = GameTuning.spawnSeed &+ 7_000 &+ stableHash(spec.name) &+ UInt64(variation) &* 1_000_003
        var best: MeetingPlan?
        for attempt in 0..<(attempts ?? (spec.jellies == nil ? designAttempts : jellyDesignAttempts)) {
            let plan = makePlan(spec, variation: variation, seed: base &+ UInt64(attempt) &* 0x9E37_79B9)
            if plan.issues.isEmpty { best = plan; break }
            if best.map({ plan.issues.count < $0.issues.count || plan.issues.count == $0.issues.count && offPlanScore(plan) < offPlanScore($0) }) ?? true {
                best = plan
            }
        }
        lock.lock()
        cache[key] = best!
        lock.unlock()
        return best!
    }

    /// Kelp Forest: every fish appears just off screen shortly before you meet it and swims straight to the
    /// meeting, so its spawn is worked out directly rather than searched for. One layout, in milliseconds.
    static func kelpPlan(_ spec: MeetingSpec, variation: Int = 0) -> MeetingPlan {
        let seed = GameTuning.spawnSeed &+ 7_000 &+ stableHash(spec.name) &+ UInt64(variation) &* 1_000_003
        let design = MeetingDesigner.design(spec, seed: seed)
        var meetings = design.meetings
        for id in GameTuning.kelpSwimsAtYou[spec.name] ?? [] where meetings.indices.contains(id - 1) {
            meetings[id - 1].headOn = true
        }
        let solved = MeetingSolver.justInTime(meetings, spec: spec, seed: seed, timeline: design.timeline)
        let analysis = EncounterAnalyzer.analyze(solved.crossings, jellies: [], reachScale: spec.reachScale)
        let unchecked = MeetingPlan(spec: spec, variation: variation, seed: seed, fish: solved.fish,
            predicted: solved.crossings, analysis: analysis, issues: [])
        return MeetingPlan(spec: spec, variation: variation, seed: seed, fish: solved.fish, predicted: solved.crossings,
            analysis: analysis, issues: design.issues + check(unchecked),
            kelp: KelpLayout.columns(spec, seed: seed))
    }

    /// How far off plan a plan's fish are, in total ("fish 4 is off its plan (score 21)" counts 21).
    private static func offPlanScore(_ plan: MeetingPlan) -> Int {
        plan.issues.reduce(0) { total, issue in
            guard let range = issue.range(of: "(score ") else { return total + 100 }
            return total + (Int(issue[range.upperBound...].prefix { $0.isNumber }) ?? 100)
        }
    }

    private static func cacheKey(_ spec: MeetingSpec, variation: Int) -> String {
        (try? JSONEncoder().encode(spec)).map { String(decoding: $0, as: UTF8.self) + "#\(variation)" } ?? spec.name
    }

    static func makePlan(_ spec: MeetingSpec, variation: Int, seed: UInt64) -> MeetingPlan {
        let design = MeetingDesigner.design(spec, seed: seed)
        let solved = MeetingSolver.solve(design.meetings, spec: spec, seed: seed, timeline: design.timeline, jellies: design.jellies)
        let jellies = spec.jellies == nil ? nil : solved.jellies
        let passes = spec.jellies.map { jellyPasses(solved.jellies, spec: $0, crossSeconds: CGFloat(spec.crossSeconds),
            worldWidth: GameTuning.playfieldSize.width * CGFloat(spec.worldScreens), timeline: design.timeline) } ?? []
        let analysis = EncounterAnalyzer.analyze(solved.crossings, jellies: passes)
        let unchecked = MeetingPlan(spec: spec, variation: variation, seed: seed, fish: solved.fish,
            predicted: solved.crossings, analysis: analysis, issues: [], jellies: jellies)
        return MeetingPlan(spec: spec, variation: variation, seed: seed, fish: solved.fish, predicted: solved.crossings,
            analysis: analysis, issues: design.issues + solved.issues + check(unchecked), jellies: jellies)
    }

    /// Where the route `timeline` passes each jelly on its first lap.
    static func jellyPasses(_ jellies: [PlannedJelly], spec: JellySpec, crossSeconds: CGFloat, worldWidth: CGFloat,
                            timeline: PlayerTimeline) -> [JellyPass] {
        let world = WrappedWorld(width: worldWidth)
        let dt = GameTuning.simulationStep
        var passes: [JellyPass] = []
        for (index, jelly) in jellies.enumerated() {
            var previous: CGFloat?
            for step in 0...timeline.lastStep where timeline.distance[step] < worldWidth {
                let position = JellyDrift.position(origin: jelly.origin, phase: jelly.phase, time: CGFloat(step) * dt,
                                                   screenWidth: GameTuning.playfieldSize.width, world: world)
                let ahead = world.delta(from: world.wrap(timeline.distance[step]), to: position.x)
                defer { previous = ahead }
                guard let before = previous, before > 0, ahead <= 0, before < worldWidth / 4 else { continue }
                let zoom = timeline.zoom[step]
                passes.append(JellyPass(jellyID: index, time: Double((CGFloat(step) - 1 + before / (before - ahead)) * dt),
                    rim: Double(position.y), domeRadius: spec.radius, tentacleLength: spec.tentacleLength,
                    speed: Double(GameTuning.playfieldSize.width / crossSeconds / zoom), zoom: Double(zoom)))
            }
        }
        return passes.sorted { $0.time < $1.time }
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
        if let jellySpec = plan.spec.jellies { issues += checkJellies(plan, spec: jellySpec) }
        return issues
    }

    /// Jellies do their jobs: the demo exists, bounce meals need their bounce, sting meals are close
    /// calls, and no two bells drift into each other.
    private static func checkJellies(_ plan: MeetingPlan, spec: JellySpec) -> [String] {
        var issues: [String] = []
        let jellies = plan.jellies ?? []
        let passes = plan.jellyPasses
        if spec.demoBounce {
            if let demo = jellies.firstIndex(where: { $0.role == .demo }) {
                if passes.first?.jellyID != demo { issues.append("the demo jelly isn't the first one you pass") }
            } else {
                issues.append("no demo bounce")
            }
        }
        let referenceRadii = plan.referenceRadii
        func radius(at crossing: EncounterCrossing) -> CGFloat {
            referenceRadii[min(referenceRadii.count - 1, Int((crossing.time / Double(GameTuning.simulationStep)).rounded()))]
        }
        for fish in plan.fish {
            guard let from = fish.bounceFrom, let pocket = plan.predicted.first(where: { $0.fishID == from }),
                  let target = plan.predicted.first(where: { $0.fishID == fish.id }) else { continue }
            let reach = EncounterAnalyzer.reach(from: pocket, to: target, jellies: passes, radius: radius(at: pocket))
            if reach.swim { issues.append("bounce meal \(fish.id) is in swimming reach of its pocket") }
            if !reach.bounce { issues.append("bounce meal \(fish.id) is out of the bounce's reach") }
        }
        for jelly in jellies where jelly.role == .sting {
            if let id = jelly.fishID, plan.analysis.meeting(fishID: id)?.danger != true {
                issues.append("sting meal \(id) isn't a close call")
            }
        }
        if let crowded = MeetingDesigner.crowdedJellies(jellies, radius: CGFloat(spec.radius),
                                                        world: WrappedWorld(width: GameTuning.playfieldSize.width * CGFloat(plan.spec.worldScreens))) {
            issues.append(crowded)
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
    /// Key of the meal this threat crosses beside, and whether it crosses just after it.
    var guards: Int?
    var guardsAfter = false
    /// A gate wall's side: 1 above the gate, -1 below.
    var wall: CGFloat?
    /// A fork meal's fork (unique in the level), lane (0 long, 1 short), and place in the lane.
    var fork: Int?
    var lane = 0
    var rank = 0
    /// Eaten on the reference route used for timing.
    var onReferenceRoute = false
    /// This meal's jelly: on its dome (pocket), under its tentacles (sting), or tentacles above a gate (wall).
    var jelly: PlannedJelly.Role?
    /// Key of the pocket meal whose bounce reaches this one.
    var bounceFrom: Int?
    /// Key of the pocket meal whose jelly this short-lane meal passes under.
    var under: Int?
    /// Bounces off the first jelly ahead of you before you meet it.
    var demo = false
    /// An open-water threat on a jelly level: any height at least `by` from your path at `y` will do.
    var clearOf: (y: CGFloat, by: CGFloat)?
}

/// A jelly the designer places beside a meeting (the solver adds the demo's).
struct DesignedJelly {
    let role: PlannedJelly.Role
    /// When and where (world x, rim y) the reference route passes it.
    let time: CGFloat
    let position: CGPoint
    let phase: CGFloat
    let fishID: Int?
}

enum MeetingDesigner {
    typealias T = GameTuning

    static func design(_ spec: MeetingSpec, seed: UInt64)
        -> (meetings: [DesignedMeeting], timeline: PlayerTimeline, jellies: [PlannedJelly], issues: [String]) {
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
        let lastDistance = (CGFloat(spec.worldScreens) - T.plannerLastMeetingMargin) * T.playfieldSize.width
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
        if let jellies = spec.jellies {
            // A gate that takes a tentacle wall loses its upper wall fish.
            let dropped = markJellyMeals(&meetings, spec: jellies, timeline: timeline, rng: &rng, issues: &issues)
            times = zip(meetings, times).filter { !dropped.contains($0.0.key) }.map(\.1)
            meetings.removeAll { dropped.contains($0.key) }
        }
        layHeights(&meetings, times: times, spec: spec, timeline: timeline, rng: &rng, issues: &issues)
        let jellies = spec.jellies.map { placeJellies(meetings, times: times, spec: spec, jellySpec: $0, timeline: timeline,
                                                      rng: &rng, issues: &issues) } ?? []
        return (meetings, timeline, jellies, issues)
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
        var walledGates: [(key: Int, playerMost: CGFloat)] = []
        var forkCount = 0
        for (segmentIndex, segment) in spec.segments.enumerated() {
            // Lay out the segment's meals: singles before, the forks, singles after.
            var meals: [DesignedMeeting] = []
            let before = (segment.singles + 1) / 2
            func single() -> DesignedMeeting { DesignedMeeting(key: 0, role: .food, segment: segmentIndex, size: 0) }
            // Bounce pairs open the segment; `bounceFrom` and `under` hold indexes into `meals` until keys exist.
            for _ in 0..<segment.bouncePairs {
                var pocket = single()
                pocket.jelly = .pocket
                meals.append(pocket)
                var high = single()
                high.bounceFrom = meals.count - 1
                meals.append(high)
            }
            meals += (0..<before).map { _ in single() }
            for fork in segment.forks {
                let first = meals.count
                for rank in 0..<max(fork.long, fork.short) {
                    for (lane, length) in [fork.long, fork.short].enumerated() where rank < length {
                        var meal = single()
                        meal.fork = forkCount
                        meal.lane = lane
                        meal.rank = rank
                        if fork.splitsOnAJelly {
                            if lane == 0 && rank == 0 { meal.jelly = .pocket }
                            if lane == 0 && rank == 1 { meal.bounceFrom = first }
                            if lane == 1 && rank == 0 { meal.under = first }
                        }
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
            // A meal you bounce off is quick to swallow, so the climb after it isn't spent chewing.
            let bouncedOff = Set(meals.compactMap(\.bounceFrom))
            for _ in 0..<100 {
                sizes = meals.indices.map { index in
                    let share = CGFloat(Double.random(in: spec.foodSize, using: &rng))
                    return fewest * (bouncedOff.contains(index) ? min(share, T.plannerBouncePocketSize) : share)
                }
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
            // Never beside a jelly's meal: the jelly is that meal's danger.
            let plain = meals.indices.filter { meals[$0].jelly == nil && meals[$0].bounceFrom == nil && meals[$0].under == nil }
            let longLane = plain.filter { meals[$0].fork != nil && meals[$0].lane == 0 }.shuffled(using: &rng)
            let others = plain.filter { meals[$0].fork == nil }.shuffled(using: &rng)
            let danger = Set((longLane + others).filter { meetings.count + $0 >= T.plannerEarliestDangerMeal }.prefix(segment.dangerFoods))
            var playerMost = most
            let firstKey = meetings.count
            for (index, var meal) in meals.enumerated() {
                meal.key = meetings.count
                meal.bounceFrom = meal.bounceFrom.map { firstKey + $0 }
                meal.under = meal.under.map { firstKey + $0 }
                meal.size = sizes[index]
                meal.onReferenceRoute = referenceRoute.contains(index)
                if danger.contains(index) { dangerFoods.append((meal.key, playerMost)) }
                meetings.append(meal)
                playerMost = grow(playerMost, [sizes[index]])
            }
            let fullest = routes.map { grow(most, $0.map { sizes[$0] }) }.max() ?? most
            if spec.walledGates { walledGates.append((meetings.count, fullest)) }
            meetings.append(DesignedMeeting(key: meetings.count, role: .gate, segment: segmentIndex, size: gate,
                                            onReferenceRoute: true))
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
            let size = fewest * CGFloat(Double.random(in: spec.lapTwoSize, using: &rng))
            guard size < fewest * 0.985 else { continue }
            // A threat goes outside forks, never beside another threat, and only where it's bigger than anyone
            // could be yet. Late in the lap a player who ate everything may already be this big, and an earlier
            // threat may have moved into this slot: either way it takes the latest earlier slot that fits.
            func fits(_ slot: Int) -> Bool {
                guard slot >= T.plannerEarliestDangerMeal, slot < meetings.count,
                      meetings[slot].role != .threat, meetings[slot - 1].role != .threat else { return false }
                if let fork = meetings[slot].fork, meetings[slot - 1].fork == fork { return false }
                // Nor beside a jelly's meals: above a bell, a big fish closes the way over it.
                if [meetings[slot], meetings[slot - 1]].contains(where: { $0.jelly != nil || $0.bounceFrom != nil || $0.under != nil }) {
                    return false
                }
                // Nor between a fork's lanes and the gate right after them: you're still swallowing a lane's meal
                // high or low when you need mid-water for the gate, so a big fish there walls off both lanes.
                if meetings[slot].role == .gate, meetings[slot - 1].fork != nil { return false }
                let most = meetings[..<slot].filter { $0.role != .threat && $0.lane == 0 }.reduce(CGFloat(1)) { grow($0, [$1.size]) }
                return most * 1.12 < size
            }
            if !fits(position) {
                guard let earlier = stride(from: position - 1, through: 1, by: -1).first(where: fits) else {
                    issues.append("no room for an open-water big fish")
                    continue
                }
                position = earlier
            }
            meetings.insert(DesignedMeeting(key: key, role: .threat, segment: meetings[min(position, meetings.count - 1)].segment, size: size),
                            at: position)
            key += 1
        }
        for (gate, playerMost) in walledGates {
            let lower = playerMost * 1.12
            guard lower < ceiling, let index = meetings.firstIndex(where: { $0.key == gate }) else { continue }
            for side: CGFloat in [1, -1] {
                var wall = DesignedMeeting(key: key, role: .threat, segment: meetings[index].segment,
                    size: CGFloat.random(in: lower...min(ceiling, lower * 1.15), using: &rng), guards: gate)
                wall.wall = side
                wall.guardsAfter = side < 0
                meetings.insert(wall, at: index + 1)
                key += 1
            }
        }
        var guarded = Set(dangerFoods.map(\.key))
        for (food, playerMost) in dangerFoods {
            var lower = playerMost * 1.12
            guard var index = meetings.firstIndex(where: { $0.key == food }) else { continue }
            if lower >= ceiling {
                // Late in the lap, a fish bigger than anyone could be then couldn't be outgrown by lap two:
                // it crosses beside the latest earlier meal where it can be both.
                func mostBefore(_ slot: Int) -> CGFloat {
                    meetings[..<slot].filter { $0.role != .threat && $0.lane == 0 }.reduce(CGFloat(1)) { grow($0, [$1.size]) }
                }
                let earlier = stride(from: index - 1, through: T.plannerEarliestDangerMeal, by: -1)
                    .first { meetings[$0].role == .food && !guarded.contains(meetings[$0].key) && mostBefore($0) * 1.12 < ceiling }
                guard let earlier else {
                    if meetings[index].segment < spec.segments.count - 1 { issues.append("no room for the threat beside food \(food)") }
                    continue
                }
                index = earlier
                lower = mostBefore(earlier) * 1.12
                guarded.insert(meetings[earlier].key)
            }
            var threat = DesignedMeeting(key: key, role: .threat, segment: meetings[index].segment,
                size: CGFloat.random(in: lower...min(ceiling, lower * 1.2), using: &rng), guards: meetings[index].key)
            threat.guardsAfter = Bool.random(using: &rng)
            meetings.insert(threat, at: index + 1)
            key += 1
        }
        return meetings
    }

    /// Picks the demo meal, then spreads pocket and sting meals through the lap: plain singles first, then
    /// fork lanes (a pocket under a long lane, tentacles over a short one), each far enough from every other
    /// jelly that their drifts never overlap. Runs once meetings have their distances.
    /// Returns the keys of upper wall fish replaced by tentacles.
    private static func markJellyMeals(_ meetings: inout [DesignedMeeting], spec: JellySpec, timeline: PlayerTimeline,
                                       rng: inout SeededGenerator, issues: inout [String]) -> Set<Int> {
        // Tentacles wall a gate from above wherever the bell fits over it with the gate still in mid-water;
        // elsewhere (early, before the camera zooms out) the gate keeps both wall fish.
        var dropped = Set<Int>()
        if spec.tentacleWalls {
            for index in meetings.indices where meetings[index].role == .gate {
                guard let upper = meetings.first(where: { $0.guards == meetings[index].key && $0.wall == 1 }) else { continue }
                let gate = meetings[index]
                let zoom = timeline.zoom[timeline.step(reaching: gate.distance)]
                let water = PlayerTimeline.waterBounds(zoom: zoom)
                let r = gate.size * T.baseRadius
                let midWater = water.bottom + r + (water.top - water.bottom - 2 * r) * T.plannerMidWater.lowerBound
                let domeTop = midWater + r + T.plannerWallGap / zoom + CGFloat(spec.tentacleLength) + CGFloat(spec.radius) * 0.65
                guard domeTop + domeHeadroom(zoom: zoom) <= water.top else { continue }
                meetings[index].jelly = .wall
                dropped.insert(upper.key)
            }
        }
        let meals = meetings.indices.filter { meetings[$0].role != .threat }
        func plain(_ index: Int) -> Bool {
            let meal = meetings[index]
            return meal.role == .food && meal.fork == nil && meal.jelly == nil && meal.bounceFrom == nil && meal.under == nil
        }
        if spec.demoBounce, let demo = meals.dropFirst().first(where: plain) ?? meals.first {
            meetings[demo].demo = true
        }
        let spacing = minimumJellySpacing(CGFloat(spec.radius))
        // Where jellies already are: bounce pairs, split forks, walled gates, and the demo's (somewhere ahead of its meal).
        var occupied = meetings.filter { $0.jelly != nil }.map(\.distance)
        if let demo = meetings.first(where: \.demo) { occupied.append(demo.distance) }
        let guarded = Set(meetings.compactMap(\.guards))
        // Meals crossing next to a big fish in open water: a bell there would leave no way past.
        let besideOpenWater = Set(meetings.indices.filter { index in
            [index - 1, index + 1].contains { meetings.indices.contains($0) && meetings[$0].role == .threat
                && meetings[$0].guards == nil && meetings[$0].wall == nil }
        }.map { meetings[$0].key })
        let splitForks = Set(meetings.filter { $0.under != nil }.compactMap(\.fork))
        func candidates(for role: PlannedJelly.Role) -> [Int] {
            let open = meals.dropFirst(2).filter { index in
                let meal = meetings[index]
                guard meal.role == .food, meal.jelly == nil, meal.bounceFrom == nil, meal.under == nil, !meal.demo,
                      !guarded.contains(meal.key), !besideOpenWater.contains(meal.key) else { return false }
                guard let fork = meal.fork else { return true }
                // In a fork, the jelly takes the lane that keeps it clear of the other: under the high long
                // lane, or over the low short lane.
                return !splitForks.contains(fork) && meal.lane == (role == .pocket ? 0 : 1)
                    && !meetings.contains { $0.fork == fork && $0.jelly != nil }
            }
            return open.sorted { (meetings[$0].fork == nil ? 0 : 1) < (meetings[$1].fork == nil ? 0 : 1) }
        }
        var roles = Array(repeating: PlannedJelly.Role.pocket, count: spec.pockets)
            + Array(repeating: PlannedJelly.Role.sting, count: spec.stingMeals)
        roles.shuffle(using: &rng)
        let lap = (meetings.map(\.distance).min() ?? 0)...(meetings.map(\.distance).max() ?? 1)
        for (slot, role) in roles.enumerated() {
            // Aim for an even spread; prefer singles, then the nearest to the aim.
            let aim = lap.lowerBound + (lap.upperBound - lap.lowerBound) * (CGFloat(slot) + 0.5) / CGFloat(roles.count)
            let fits = candidates(for: role).filter { index in occupied.allSatisfy { abs($0 - meetings[index].distance) >= spacing } }
            guard let pick = fits.min(by: { a, b in
                let forkA = meetings[a].fork == nil ? 0 : 1, forkB = meetings[b].fork == nil ? 0 : 1
                return forkA != forkB ? forkA < forkB : abs(meetings[a].distance - aim) < abs(meetings[b].distance - aim)
            }) else {
                issues.append("no room for a \(role.rawValue) meal")
                continue
            }
            meetings[pick].jelly = role
            occupied.append(meetings[pick].distance)
        }
        return dropped
    }

    /// Seconds into the run for each meeting: even spacing between meals; a fork's lanes a beat apart,
    /// with room to reach either lane and come back; room after a gate for its long swallow; threats a
    /// short beat from the meal they guard, open-water threats between meals. Not yet in time order.
    private static func meetingTimes(_ meetings: [DesignedMeeting], spec: MeetingSpec) -> [CGFloat] {
        let screen = CGFloat(spec.crossSeconds)
        let spacing = CGFloat(spec.spacing) * screen
        var times = Array(repeating: CGFloat(0), count: meetings.count)
        var cursor = T.plannerFirstMeetingScreens * screen
        var previous: DesignedMeeting?
        for i in meetings.indices where meetings[i].role != .threat {
            let meal = meetings[i]
            defer { previous = meal }
            guard let last = previous else { times[i] = cursor; continue }
            // A bounce meal comes a moment after the pocket it climbs from.
            if let from = meal.bounceFrom, let pocket = meetings.firstIndex(where: { $0.key == from }) {
                times[i] = times[pocket] + T.plannerBounceSeconds
                cursor = max(cursor, times[i])
                continue
            }
            if let fork = meal.fork, last.fork == fork {
                // The other lane of this rank crosses a beat after; the next rank, a full gap after this one.
                if meal.rank == last.rank { times[i] = cursor + T.plannerForkOffsetSeconds; continue }
                cursor += spacing
            } else {
                var gap = meal.fork != nil || last.fork != nil ? spacing * T.plannerForkLead : spacing
                if last.role == .gate { gap = max(gap, T.plannerGateRecoverySeconds) }
                cursor += gap
            }
            times[i] = cursor
        }
        for i in meetings.indices where meetings[i].role == .threat {
            if let guarded = meetings[i].guards, let food = meetings.firstIndex(where: { $0.key == guarded }) {
                let offset = meetings[i].wall != nil ? T.plannerWallOffsetSeconds : T.plannerDangerOffsetScreens * screen
                times[i] = times[food] + (meetings[i].guardsAfter ? 1 : -1) * offset
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
                                   timeline: PlayerTimeline, rng: inout SeededGenerator, issues: inout [String]) {
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
                // A fork split by a jelly climbs from its dome: its long lane is the high one.
                let carriesJelly = meetings.contains { $0.fork == fork && ($0.jelly != nil || $0.under != nil) }
                let high = longLaneHigh[fork] ?? (carriesJelly ? true : Bool.random(using: &rng))
                longLaneHigh[fork] = high
                height = CGFloat.random(in: high == (meetings[i].lane == 0) ? T.plannerHighLane : T.plannerLowLane, using: &rng)
            } else if position > 0 {
                let neighbors = [meals[position - 1]] + (position + 1 < meals.count ? [meals[position + 1]] : [])
                let walled = meetings[i].role == .gate && spec.walledGates
                if walled || neighbors.contains(where: { meetings[$0].fork != nil }) {
                    height = CGFloat.random(in: T.plannerMidWater, using: &rng)
                } else {
                    let reach = EncounterAnalyzer.verticalReach(seconds: Double(times[i] - times[meals[position - 1]]))
                        * spec.reachScale
                    let farthest = min(T.plannerHeightLimits.upperBound - T.plannerHeightLimits.lowerBound, (reach + T.plannerMealHeightTolerance) / screenWater)
                    let swing = farthest * CGFloat(Double.random(in: spec.heightSwing, using: &rng))
                    var sign: CGFloat = Bool.random(using: &rng) ? 1 : -1
                    if !T.plannerHeightLimits.contains(height + sign * swing) { sign = -sign }
                    height = (height + sign * swing).clamped(T.plannerHeightLimits.lowerBound, T.plannerHeightLimits.upperBound)
                }
            } else if position + 1 < meals.count, meetings[meals[1]].fork != nil {
                height = CGFloat.random(in: T.plannerMidWater, using: &rng)
            }
            meetings[i].height = height
            if let jellies = spec.jellies, let y = jellyMealHeight(i, meetings: meetings, times: times, spec: jellies,
                                                                   timeline: timeline, rng: &rng, issues: &issues) {
                let range = usable(meetings[i])
                meetings[i].height = ((y - range.low) / max(1, range.high - range.low)).clamped(0, 1)
                height = meetings[i].height
            }
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
                // Around jellies, a big fish rarely swims to one exact height, and it only has to stay clear of you.
                if spec.jellies != nil { meetings[i].clearOf = (pathY, offset) }
                continue
            }
            guard let food = meetings.first(where: { $0.key == guarded }) else { continue }
            let foodRange = usable(food)
            let foodY = foodRange.low + (foodRange.high - foodRange.low) * food.height
            let zoom = timeline.zoom[timeline.step(reaching: food.distance)]
            let gap = meetings[i].wall != nil ? T.plannerWallGap : CGFloat(spec.dangerGap)
            let offset = (food.size + meetings[i].size) * T.baseRadius * T.collisionScale + gap / zoom
            var sides: [CGFloat] = meetings[i].wall.map { [$0] } ?? [1, -1]
            if meetings[i].wall == nil && Bool.random(using: &rng) { sides.reverse() }
            let fraction: (CGFloat) -> CGFloat = { side in (foodY + side * offset - range.low) / max(1, range.high - range.low) }
            let side = sides.first { (0...1).contains(fraction($0)) } ?? sides[0]
            meetings[i].height = fraction(side).clamped(0, 1)
        }
    }
}

extension MeetingDesigner {
    /// A meal's center above the dome of the jelly it sits on.
    static func pocketGap(radius: CGFloat, zoom: CGFloat) -> CGFloat { T.plannerPocketGap / zoom + radius * 0.2 }

    private static func worldY(_ meeting: DesignedMeeting, timeline: PlayerTimeline) -> CGFloat {
        let bounds = PlayerTimeline.waterBounds(zoom: timeline.zoom[timeline.step(reaching: meeting.distance)])
        let r = meeting.size * T.baseRadius
        return bounds.bottom + r + (bounds.top - bounds.bottom - 2 * r) * meeting.height
    }

    /// World y of the rim of the jelly a meal sits on, sits under, or (a gate) hangs over.
    static func jellyRim(_ meeting: DesignedMeeting, spec: JellySpec, timeline: PlayerTimeline) -> CGFloat? {
        let zoom = timeline.zoom[timeline.step(reaching: meeting.distance)]
        let r = meeting.size * T.baseRadius, y = worldY(meeting, timeline: timeline)
        switch meeting.jelly {
        case .pocket: return y - r - pocketGap(radius: r, zoom: zoom) - CGFloat(spec.radius) * 0.65
        case .sting: return y + r + CGFloat(spec.stingGap) / zoom + CGFloat(spec.tentacleLength)
        case .wall: return y + r + T.plannerWallGap / zoom + CGFloat(spec.tentacleLength)
        default: return nil
        }
    }

    /// The height a jelly's meal needs (world y), or nil for a meal without one. Pockets leave room under
    /// their tentacles for a split fork's short lane and above for the climb; a bounce meal sits beyond
    /// swimming reach from its pocket but within the bounce's; sting meals and walled gates leave room above
    /// for the jelly hanging over them.
    fileprivate static func jellyMealHeight(_ i: Int, meetings: [DesignedMeeting], times: [CGFloat], spec: JellySpec,
                                            timeline: PlayerTimeline, rng: inout SeededGenerator, issues: inout [String]) -> CGFloat? {
        let meeting = meetings[i]
        let step = timeline.step(reaching: meeting.distance)
        let zoom = timeline.zoom[step]
        let water = PlayerTimeline.waterBounds(zoom: zoom)
        let r = meeting.size * T.baseRadius
        let low = water.bottom + r, high = water.top - r
        let R = CGFloat(spec.radius), L = CGFloat(spec.tentacleLength)
        let current = worldY(meeting, timeline: timeline)
        let headroom = domeHeadroom(zoom: zoom)
        if meeting.demo {
            return low + (high - low) * CGFloat.random(in: T.plannerDemoHeight, using: &rng)
        }
        if let from = meeting.bounceFrom, let pocket = meetings.firstIndex(where: { $0.key == from }) {
            let pocketY = worldY(meetings[pocket], timeline: timeline)
            let pocketR = meetings[pocket].size * T.baseRadius
            let pocketZoom = timeline.zoom[timeline.step(reaching: meetings[pocket].distance)]
            let player = timeline.radius[step]
            let elapsed = Double(times[i] - times[pocket])
            let tolerance = (player + r) * EncounterAnalyzer.catchTolerance
            let margin = T.plannerBounceMargin / zoom
            let dome = pocketY - pocketR - pocketGap(radius: pocketR, zoom: pocketZoom) + player * T.hazardHitboxScale
            let swimTop = pocketY + EncounterAnalyzer.verticalReach(seconds: elapsed) / zoom + tolerance + margin
            let bounceTop = min(high, dome + EncounterAnalyzer.bounceReach(seconds: elapsed).up / zoom + tolerance - margin)
            guard swimTop <= bounceTop else {
                issues.append("no height for bounce meal \(meeting.key)")
                return min(high, swimTop)
            }
            return CGFloat.random(in: swimTop...bounceTop, using: &rng)
        }
        if let from = meeting.under, let pocket = meetings.first(where: { $0.key == from }),
           let rim = jellyRim(pocket, spec: spec, timeline: timeline) {
            let y = rim - L - CGFloat(spec.stingGap) / zoom - r
            if y < low { issues.append("no room under the jelly for meal \(meeting.key)") }
            return max(low, y)
        }
        switch meeting.jelly {
        case .pocket:
            // Room below for a split lane's meal (or just the tentacle tips), and above for the climb.
            let under = meetings.first { $0.under == meeting.key }.map { $0.size * T.baseRadius }
            let room = under.map { 2 * $0 + CGFloat(spec.stingGap) / zoom + 4 / zoom } ?? 24 / zoom
            let lowest = water.bottom + room + L + R * 0.65 + pocketGap(radius: r, zoom: zoom) + r
            var highest = min(high - T.plannerPocketHeadroom / zoom,
                              water.top - headroom - pocketGap(radius: r, zoom: zoom) - r)
            if let next = meetings.firstIndex(where: { $0.bounceFrom == meeting.key }) {
                // The climb has to fit between this meal and the top of the water.
                let player = timeline.radius[step]
                let elapsed = Double(times[next] - times[i])
                let nextR = meetings[next].size * T.baseRadius
                let climb = EncounterAnalyzer.verticalReach(seconds: elapsed) / zoom
                    + (player + nextR) * EncounterAnalyzer.catchTolerance + T.plannerBounceMargin / zoom
                highest = min(highest, water.top - nextR - climb)
            }
            guard lowest <= highest else {
                issues.append("no room for pocket meal \(meeting.key)")
                return lowest
            }
            return current.clamped(lowest, highest)
        case .sting:
            let highest = water.top - headroom - R * 0.65 - L - CGFloat(spec.stingGap) / zoom - r
            return current.clamped(low, max(low, highest))
        case .wall:
            let highest = water.top - headroom - R * 0.65 - L - T.plannerWallGap / zoom - r
            return min(current, max(low, highest))
        default:
            return nil
        }
    }

    /// Jellies beside their meals, passing you at those meals' meetings, then a few in open water clear of
    /// the swim between two meals. Bells keep far enough apart that their drifts never overlap.
    fileprivate static func placeJellies(_ meetings: [DesignedMeeting], times: [CGFloat], spec: MeetingSpec, jellySpec: JellySpec,
                                         timeline: PlayerTimeline, rng: inout SeededGenerator, issues: inout [String]) -> [PlannedJelly] {
        let R = CGFloat(jellySpec.radius), L = CGFloat(jellySpec.tentacleLength)
        let world = WrappedWorld(width: T.playfieldSize.width * CGFloat(spec.worldScreens))
        var placed: [DesignedJelly] = []
        for (i, meeting) in meetings.enumerated() {
            guard let role = meeting.jelly, let rim = jellyRim(meeting, spec: jellySpec, timeline: timeline) else { continue }
            placed.append(DesignedJelly(role: role, time: times[i], position: CGPoint(x: world.wrap(meeting.distance), y: rim),
                                        phase: centeredPhase(at: times[i], rng: &rng), fishID: i + 1))
        }
        let spacing = minimumJellySpacing(R)
        let meals = meetings.indices.filter { meetings[$0].role != .threat }
        let demo = meals.firstIndex { meetings[$0].demo }
        var gaps = zip(meals, meals.dropFirst()).enumerated().filter { position, pair in
            let quiet = [pair.0, pair.1].allSatisfy { meetings[$0].jelly == nil && meetings[$0].fork == nil
                && meetings[$0].bounceFrom == nil && meetings[$0].under == nil && !meetings[$0].demo }
            return quiet && demo.map { position > $0 + 1 } ?? (position > 0)
        }.map(\.element)
        gaps.shuffle(using: &rng)
        var open = 0
        for (a, b) in gaps where open < jellySpec.open {
            let time = (times[a] + times[b]) / 2
            let step = min(timeline.lastStep, Int((time / T.simulationStep).rounded()))
            let x = world.wrap(timeline.distance[step])
            guard placed.allSatisfy({ abs(world.delta(from: $0.position.x, to: x)) >= spacing }) else { continue }
            let zoom = timeline.zoom[step]
            let water = PlayerTimeline.waterBounds(zoom: zoom)
            let body = timeline.radius[step] * T.plannerJellyPlayerAllowance * T.hazardHitboxScale
            let pathY = (worldY(meetings[a], timeline: timeline) + worldY(meetings[b], timeline: timeline)) / 2
            let clearance = CGFloat(jellySpec.openClearance) / zoom + body
            let rims = [pathY - clearance - R * 0.65, pathY + clearance + L].filter { rim in
                rim - L >= water.bottom - 10 / zoom && rim >= water.bottom + 10 / zoom
                    && rim + R * 0.65 <= water.top - domeHeadroom(zoom: zoom)
            }
            guard let rim = rims.randomElement(using: &rng) else { continue }
            placed.append(DesignedJelly(role: .open, time: time, position: CGPoint(x: x, y: rim),
                                        phase: centeredPhase(at: time, rng: &rng), fishID: nil))
            open += 1
        }
        if jellySpec.scattered == true && open < jellySpec.open && meals.count > 1 {
            // Every way you might be swimming at `time`: any two meals close enough in time that you could
            // go straight from one to the other, skipping the meals between.
            let mealYs = meals.map { worldY(meetings[$0], timeline: timeline) }
            var time = times[meals[0]] + T.simulationStep
            while time < times[meals[meals.count - 1]] && open < jellySpec.open {
                defer { time += T.plannerScatterStep }
                let step = min(timeline.lastStep, Int((time / T.simulationStep).rounded()))
                let x = world.wrap(timeline.distance[step])
                guard placed.allSatisfy({ abs(world.delta(from: $0.position.x, to: x)) >= spacing }) else { continue }
                var swims: [CGFloat] = []
                for (i, a) in meals.enumerated() where times[a] <= time {
                    for (j, b) in meals.enumerated().dropFirst(i + 1)
                    where times[b] >= time && times[b] - times[a] <= T.plannerScatterSwimSeconds {
                        let share = (time - times[a]) / max(times[b] - times[a], T.simulationStep)
                        swims.append(mealYs[i] + (mealYs[j] - mealYs[i]) * share)
                    }
                }
                guard !swims.isEmpty else { continue }
                let zoom = timeline.zoom[step]
                let water = PlayerTimeline.waterBounds(zoom: zoom)
                let body = timeline.radius[step] * T.plannerJellyPlayerAllowance * T.hazardHitboxScale
                let clearance = CGFloat(jellySpec.openClearance) / zoom + body
                // A bell above a swim keeps its tentacles clear of it; one below keeps its dome clear.
                let rims = ([water.bottom] + swims.sorted()).map { $0 + clearance + L }.filter { rim in
                    swims.allSatisfy { rim - L - clearance >= $0 || rim + R * 0.65 + clearance <= $0 }
                        && rim - L >= water.bottom - 10 / zoom && rim >= water.bottom + 10 / zoom
                        && rim + R * 0.65 <= water.top - domeHeadroom(zoom: zoom)
                }
                guard let rim = rims.randomElement(using: &rng) else { continue }
                placed.append(DesignedJelly(role: .open, time: time, position: CGPoint(x: x, y: rim),
                                            phase: centeredPhase(at: time, rng: &rng), fishID: nil))
                open += 1
            }
        }
        if open < jellySpec.open { issues.append("only \(open) of \(jellySpec.open) open-water jellies fit") }
        let jellies = placed.map { jelly in
            PlannedJelly(role: jelly.role, origin: JellyDrift.origin(for: jelly.position, phase: jelly.phase, time: jelly.time,
                screenWidth: T.playfieldSize.width, world: world), phase: jelly.phase, fishID: jelly.fishID)
        }
        if let crowded = crowdedJellies(jellies, radius: R, world: world) { issues.append(crowded) }
        return jellies
    }

    /// A drift phase that has the bell in the middle of its wander, heading either way, when you pass it at
    /// `time`, so its home is where you meet it and nearby bells' homes keep their spacing.
    static func centeredPhase(at time: CGFloat, rng: inout SeededGenerator) -> CGFloat {
        let phase = -time * 2 * .pi / T.jellyDriftSeconds + (Bool.random(using: &rng) ? 0 : .pi)
        return phase - (phase / (2 * .pi)).rounded(.down) * 2 * .pi
    }

    /// Water kept clear above a dome, bob included. (A fish too big to fit slides over it: JellySwim.)
    static func domeHeadroom(zoom: CGFloat) -> CGFloat { T.plannerDomeHeadroom / zoom + T.jellyBobPoints }

    /// Homes this far apart keep two bells' drifts from ever overlapping.
    static func minimumJellySpacing(_ radius: CGFloat) -> CGFloat {
        2 * T.playfieldSize.width * T.jellyDriftScreens + radius * 2.2
    }

    static func crowdedJellies(_ jellies: [PlannedJelly], radius: CGFloat, world: WrappedWorld) -> String? {
        let spacing = minimumJellySpacing(radius)
        for a in jellies.indices {
            for b in jellies.indices where b > a && abs(world.delta(from: jellies[a].origin.x, to: jellies[b].origin.x)) < spacing {
                return "jellies \(a) and \(b) drift into each other"
            }
        }
        return nil
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
    /// About how long FreeSwim's easing takes to reverse a fish's swim.
    static let turnSeconds: CGFloat = 1.6
    private static let unwrapped = WrappedWorld(width: 10_000_000)

    static func solve(_ meetings: [DesignedMeeting], spec: MeetingSpec, seed: UInt64, timeline: PlayerTimeline,
                      jellies designed: [PlannedJelly] = [])
        -> (fish: [PlannedFish], crossings: [EncounterCrossing], jellies: [PlannedJelly], issues: [String]) {
        let width = T.playfieldSize.width
        let worldWidth = width * CGFloat(spec.worldScreens)
        let meetSteps = meetings.map { timeline.step(reaching: $0.distance) }
        let releaseSteps = meetings.map { timeline.step(reaching: $0.distance + width * T.freeEncounterReleaseScreens) }
        let horizon = releaseSteps.max() ?? 0
        var placed: [(fish: PlannedFish, path: [CGPoint], release: Int)] = []
        var crossings: [EncounterCrossing] = []
        var issues: [String] = []
        var jellies = designed
        var track = spec.jellies.map { JellyTrack(jellies, spec: $0, worldWidth: worldWidth, steps: horizon) }

        // The demo fish goes first: its bounce places the first jelly, which everyone else then swims around.
        let demo = meetings.firstIndex(where: \.demo)
        let order = demo.map { [$0] + meetings.indices.filter { $0 != demo } } ?? Array(meetings.indices)
        for index in order {
            let meeting = meetings[index]
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
            var chosenDemoJelly: PlannedJelly?
            // A swim never replayed around the jellies: only if nothing else turns up, since jellies may move its meeting.
            var lastResort: (fish: PlannedFish, path: [CGPoint], error: CGFloat)?
            let world = WrappedWorld(width: worldWidth)
            let tolerance = (meeting.demo ? T.plannerDemoHeightTolerance : heightTolerance) / zoom
            /// How far a meeting at `y` misses: signed, so moving the start height by minus it helps.
            func miss(_ y: CGFloat) -> CGFloat {
                guard let clear = meeting.clearOf else { return y - targetY }
                let gap = abs(y - clear.y)
                return gap >= clear.by ? 0 : (y >= clear.y ? gap - clear.by : clear.by - gap)
            }
            // With jellies, a second pass replays every swim around them before settling for one that wasn't.
            for search in 0..<(track == nil ? 1 : 2) where chosen == nil && (search == 0 || fallback == nil) {
            for attempt in 0..<attempts {
                var draw = SeededGenerator(seed: seed &+ UInt64(id) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(attempt) &* 0xBF58_476D_1CE4_E5B9)
                let headOn = attempt < attempts / 2 ? meeting.headOn : !meeting.headOn
                // A fish swimming your way near your speed creeps toward you for seconds, as if fleeing;
                // slow ones are quick, lazy overtakes.
                let speeds = headOn ? spec.aiSpeed
                    : spec.aiSpeed.lowerBound...(spec.aiSpeed.lowerBound + (spec.aiSpeed.upperBound - spec.aiSpeed.lowerBound) * T.plannerSameDirectionSpeedShare)
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
                    referenceMeal: meeting.onReferenceRoute,
                    bounceFrom: meeting.bounceFrom.flatMap { key in meetings.firstIndex { $0.key == key } }.map { $0 + 1 })
                guard var early = path(candidate, seed: seed, vertical: CGFloat(spec.aiVertical), steps: meetStep, timeline: timeline) else { continue }
                var error = miss(early[meetStep].y)
                // Starting height carries through until the fish settles on its own targets: nudge it toward the meeting.
                for _ in 0..<2 where abs(error) > tolerance && abs(error) < 150 {
                    let nudged = (startY - error).clamped(start.bottom + radius, start.top - radius)
                    guard nudged != startY else { break }
                    let retry = candidate.moved(to: CGPoint(x: 0, y: nudged))
                    guard let path = path(retry, seed: seed, vertical: CGFloat(spec.aiVertical), steps: meetStep, timeline: timeline),
                          abs(miss(path[meetStep].y)) < abs(error) else { break }
                    startY = nudged; candidate = retry; early = path; error = miss(path[meetStep].y)
                }
                var fish = candidate.moved(to: CGPoint(x: timeline.distance[meetStep] - early[meetStep].x, y: startY))
                // Around the jellies: the same swim, steered and bounced as the game will. Steering that changes
                // where it meets you would move its spawn, so those swims are rejected.
                var attemptJelly: PlannedJelly?
                // Jellies only nudge a swim (the demo's bounce aside), so a swim far off its height isn't worth replaying.
                if search == 0 && track != nil && !meeting.demo && abs(error) > tolerance + T.plannerJellyReplayMargin / zoom {
                    if lastResort.map({ abs(error) < $0.error }) ?? true { lastResort = (fish, early, abs(error)) }
                    continue
                }
                if var current = track, let jellySpec = spec.jellies {
                    if meeting.demo {
                        guard let jelly = demoJelly(for: fish, path: early, meetStep: meetStep, spec: jellySpec, timeline: timeline,
                                                    world: world, draw: &draw),
                              MeetingDesigner.crowdedJellies([jelly] + jellies, radius: CGFloat(jellySpec.radius), world: world) == nil
                        else { continue }
                        current = JellyTrack([jelly] + jellies, spec: jellySpec, worldWidth: worldWidth, steps: horizon)
                        attemptJelly = jelly
                    }
                    var bounces: [(step: Int, jelly: Int)] = []
                    func replay(_ candidate: PlannedFish) -> [CGPoint]? {
                        bounces = []
                        return path(candidate, seed: seed, vertical: CGFloat(spec.aiVertical), steps: meetStep, timeline: timeline,
                                    jellies: current, release: releaseSteps[index], events: { step, event in
                                        if case .bounced(let jelly) = event { bounces.append((step, jelly)) } })
                    }
                    guard var swim = replay(fish) else { continue }
                    // Steering around a bell on screen moves where it meets you: start it where the steered swim
                    // meets you instead, a few times over, since the new start changes the steering a little.
                    // (Not the demo: its jelly sits under the swim as first drawn.)
                    var settled = abs(timeline.distance[meetStep] - fish.spawn.x - swim[meetStep].x) < 0.5
                    for _ in 0..<(meeting.demo ? 0 : T.plannerSteeredRespawns) where !settled {
                        let moved = fish.moved(to: CGPoint(x: timeline.distance[meetStep] - swim[meetStep].x, y: startY))
                        guard moved.spawn.x >= clearAhead, moved.spawn.x <= worldWidth - width * T.spawnClearBehind,
                              let again = replay(moved) else { break }
                        fish = moved
                        swim = again
                        settled = abs(timeline.distance[meetStep] - fish.spawn.x - swim[meetStep].x) < 0.5
                    }
                    guard settled else { continue }
                    if meeting.demo {
                        // It must land on the demo jelly while you can see it ahead of you.
                        guard bounces.contains(where: { $0.jelly == 0 && demoVisible(fish.spawn.x + swim[$0.step].x, step: $0.step,
                                                                                     timeline: timeline, world: world) })
                        else { continue }
                    }
                    early = swim
                    error = miss(early[meetStep].y)
                }
                if turns {
                    // Nobody sees it swim away or turn: it's off screen until it's well into its approach.
                    let settled = min(meetStep, Int((turnTimer + turnSeconds) / T.simulationStep))
                    guard !(0...settled).contains(where: { visible(fish.spawn.x + early[$0].x, step: $0, timeline: timeline, world: world) }) else { continue }
                }
                if abs(error) > tolerance {
                    if fallback.map({ abs(error) < $0.error }) ?? true { fallback = (fish, early, abs(error)) }
                    continue
                }
                let attemptTrack = attemptJelly.flatMap { jelly in spec.jellies.map { JellyTrack([jelly] + jellies, spec: $0, worldWidth: worldWidth, steps: horizon) } } ?? track
                guard let full = path(fish, seed: seed, vertical: CGFloat(spec.aiVertical), steps: horizon, timeline: timeline,
                                      jellies: attemptTrack, release: releaseSteps[index]) else { continue }
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
                if clear { chosen = (fish, route, abs(error)); chosenDemoJelly = attemptJelly; break }
                // Brushing past another fish before you meet it nudges both paths: worse than a small height miss.
                if fallback.map({ abs(error) + contactPenalty < $0.error }) ?? true { fallback = (fish, early, abs(error) + contactPenalty) }
            }
            }
            if meeting.demo {
                if let chosenDemoJelly, let jellySpec = spec.jellies {
                    jellies.insert(chosenDemoJelly, at: 0)
                    track = JellyTrack(jellies, spec: jellySpec, worldWidth: worldWidth, steps: horizon)
                } else {
                    issues.append("fish \(id) found no demo bounce")
                }
            }
            if fallback == nil { fallback = lastResort }
            let result: (fish: PlannedFish, path: [CGPoint], error: CGFloat)
            if let chosen {
                result = chosen
            } else if let fallback, let full = path(fallback.fish, seed: seed, vertical: CGFloat(spec.aiVertical), steps: horizon,
                                                    timeline: timeline, jellies: track, release: releaseSteps[index]) {
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
        placed.sort { $0.fish.id < $1.fish.id }
        return (styled(placed.map(\.fish), seed: seed), crossings.sorted { $0.fishID < $1.fishID }, jellies, issues)
    }

    /// A jelly under the demo fish's swim: where it's heading down, ahead of you on screen, the bell's top
    /// meets its belly. The fish's swim with the jelly decides whether it really bounces.
    private static func demoJelly(for fish: PlannedFish, path: [CGPoint], meetStep: Int, spec: JellySpec, timeline: PlayerTimeline,
                                  world: WrappedWorld, draw: inout SeededGenerator) -> PlannedJelly? {
        let R = CGFloat(spec.radius), L = CGFloat(spec.tentacleLength)
        let lead = Int(T.plannerDemoLeadSeconds / T.simulationStep)
        guard meetStep - lead > lead else { return nil }
        let water = PlayerTimeline.waterBounds(zoom: 1)
        let landings = (lead..<(meetStep - lead)).filter { step in
            let x = fish.spawn.x + path[step].x
            let rim = path[step].y - fish.radius * T.hazardHitboxScale - R * 0.65
            return path[step].y < path[step - 1].y - 0.3 && demoVisible(x, step: step, timeline: timeline, world: world)
                && rim - L >= water.bottom + 12 && rim + R * 0.65 <= water.top - MeetingDesigner.domeHeadroom(zoom: 1)
        }
        guard let step = landings.randomElement(using: &draw) else { return nil }
        let phase = CGFloat.random(in: 0..<(2 * .pi), using: &draw)
        let landing = CGPoint(x: world.wrap(fish.spawn.x + path[step].x),
                              y: path[step].y - fish.radius * T.hazardHitboxScale - R * 0.65)
        return PlannedJelly(role: .demo, origin: JellyDrift.origin(for: landing, phase: phase, time: CGFloat(step) * T.simulationStep,
            screenWidth: T.playfieldSize.width, world: world), phase: phase, fishID: fish.id)
    }

    /// Well inside the screen, ahead of the player.
    private static func demoVisible(_ x: CGFloat, step: Int, timeline: PlayerTimeline, world: WrappedWorld) -> Bool {
        let screen = T.playerScreenX + world.delta(from: timeline.distance[step], to: x) * timeline.zoom[step] / T.playfieldSize.width
        return T.plannerDemoScreen.contains(screen)
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

    enum JellyEvent { case steered, bounced(Int), stung }

    /// The fish's free swim, relative to its spawn x. Without jellies it's simulated in isolation; with them
    /// it starts from its real spawn and steers around and bounces off them exactly as GameScene's AI does.
    /// Nil if it can't be simulated.
    static func path(_ fish: PlannedFish, seed: UInt64, vertical: CGFloat, steps: Int, timeline: PlayerTimeline,
                     jellies: JellyTrack? = nil, release: Int = 0, events: ((Int, JellyEvent) -> Void)? = nil) -> [CGPoint]? {
        guard steps <= timeline.lastStep else { return nil }
        if let jellies {
            return jellyPath(fish, seed: seed, vertical: vertical, steps: steps, timeline: timeline, jellies: jellies,
                             release: release, events: events)
        }
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

    /// Before `release` (you've passed it), the fish meets jellies only on screen, as GameScene has it.
    private static func jellyPath(_ fish: PlannedFish, seed: UInt64, vertical: CGFloat, steps: Int, timeline: PlayerTimeline,
                                  jellies: JellyTrack, release: Int, events: ((Int, JellyEvent) -> Void)?) -> [CGPoint]? {
        guard steps < jellies.positions.count else { return nil }
        let world = jellies.world
        let dt = T.simulationStep
        let f = Fish(id: fish.id, isPlayer: false, position: CGPoint(x: world.wrap(fish.spawn.x), y: fish.spawn.y), radius: fish.radius)
        f.heading = fish.startHeading
        f.cruiseSpeed = fish.cruiseSpeed
        f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
        f.facing = f.heading
        f.targetY = fish.spawn.y
        f.retargetTimer = fish.retargetTimer
        f.turnTimer = fish.turnTimer
        f.phase = fish.phase
        var rng = FreeSwim.movementGenerator(ecosystemSeed: seed, id: fish.id, variant: fish.variant)
        var travel: CGFloat = 0
        var points = [CGPoint(x: 0, y: fish.spawn.y)]
        points.reserveCapacity(steps + 1)
        for step in stride(from: 1, through: steps, by: 1) {
            let zoom = timeline.zoom[step]
            let bounds = PlayerTimeline.waterBounds(zoom: zoom)
            let minY = bounds.bottom + fish.radius
            let maxY = max(minY, bounds.top - fish.radius)
            let old = f.position
            var velocity = FreeSwim.steer(f, dt: dt, clock: CGFloat(step) * dt, minY: minY, maxY: maxY,
                                          verticalSpeed: vertical, leash: nil, rng: &rng)
            let before = jellies.positions[step - 1], now = jellies.positions[step]
            let player = WrappedWorld(width: world.width).wrap(timeline.distance[step])
            func meetsJellies() -> Bool {
                let dx = world.delta(from: player, to: f.position.x)
                return step >= release || (dx > -T.playfieldSize.width * T.playerScreenX / zoom - T.plannedContactScreenMargin
                    && dx < T.playfieldSize.width * (1 - T.playerScreenX) / zoom + T.plannedContactScreenMargin)
            }
            if meetsJellies(), let avoidance = JellySwim.avoidance(for: f, velocity: velocity, jellies: before, layout: jellies.layout, world: world,
                                                   waterBottom: bounds.bottom, waterTop: bounds.top, zoom: zoom) {
                velocity = JellySwim.steer(f, velocity: velocity, toward: avoidance, dt: dt, minY: minY, maxY: maxY)
                events?(step, .steered)
            }
            FreeSwim.integrate(f, velocity: velocity, dt: dt, minY: minY, maxY: maxY, world: world)
            travel += f.velocity.dx * dt
            guard meetsJellies() else {
                points.append(CGPoint(x: travel, y: f.position.y))
                continue
            }
            let reach = jellies.layout.radius + fish.radius * T.hazardHitboxScale + abs(f.velocity.dx * dt) + 2
            for jelly in now.indices {
                // Out of reach before and after the step: no contact, as JellyRules would also find.
                guard abs(world.delta(from: now[jelly].x, to: f.position.x)) <= reach
                        || abs(world.delta(from: before[jelly].x, to: old.x)) <= reach else { continue }
                let touch = JellySwim.contact(f, old: old, jelly: now[jelly], previousJelly: before[jelly], layout: jellies.layout, world: world)
                switch touch.contact {
                case .none: break
                case .bounce:
                    if JellySwim.slideIfCramped(f, at: touch.at, jellyY: now[jelly].y, layout: jellies.layout,
                                                ceiling: bounds.top - fish.radius) { continue }
                    JellySwim.bounce(f, at: touch.at, previous: touch.previous, jellyY: now[jelly].y, layout: jellies.layout,
                                     speed: T.jellyBounceSpeed / zoom, dt: dt, ceiling: bounds.top - fish.radius)
                    events?(step, .bounced(jelly))
                case .tentacles:
                    // GameScene updates bells in order, so the later ones haven't moved yet.
                    let mixed = Array(now[...jelly]) + Array(before[(jelly + 1)...])
                    if let avoidance = JellySwim.avoidance(for: f, velocity: f.velocity, jellies: mixed, layout: jellies.layout,
                                                           world: world, waterBottom: bounds.bottom, waterTop: bounds.top, zoom: zoom) {
                        f.velocity = avoidance
                    }
                    events?(step, .stung)
                }
            }
            points.append(CGPoint(x: travel, y: f.position.y))
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
            retargetTimer: retargetTimer, variant: variant, styleSeed: styleSeed, referenceMeal: referenceMeal,
            bounceFrom: bounceFrom, appearsAt: appearsAt, approach: approach)
    }
    func styled(_ seed: UInt64) -> PlannedFish {
        PlannedFish(id: id, role: role, segment: segment, fork: fork, lane: lane, radius: radius,
            meetingDistance: meetingDistance, headOn: headOn,
            startHeading: startHeading, spawn: spawn, cruiseSpeed: cruiseSpeed, phase: phase, turnTimer: turnTimer,
            retargetTimer: retargetTimer, variant: variant, styleSeed: seed, referenceMeal: referenceMeal,
            bounceFrom: bounceFrom, appearsAt: appearsAt, approach: approach)
    }
}

extension MeetingSolver {
    /// Kelp Forest: each fish appears as late as it can while still just beyond the edge of the screen it comes
    /// from, swimming straight at its meeting height, so it meets the reference route exactly as designed. It
    /// only exists for those last seconds, so nothing it passes on the way can knock it off schedule.
    static func justInTime(_ meetings: [DesignedMeeting], spec: MeetingSpec, seed: UInt64, timeline: PlayerTimeline)
        -> (fish: [PlannedFish], crossings: [EncounterCrossing]) {
        let width = T.playfieldSize.width, dt = T.simulationStep
        let world = WrappedWorld(width: width * CGFloat(spec.worldScreens))
        var fish: [PlannedFish] = []
        var crossings: [EncounterCrossing] = []
        for (index, meeting) in meetings.enumerated() {
            let id = index + 1
            var draw = SeededGenerator(seed: seed &+ UInt64(id) &* 0x9E37_79B9_7F4A_7C15)
            let meetStep = timeline.step(reaching: meeting.distance)
            let zoom = timeline.zoom[meetStep]
            let radius = meeting.size * T.baseRadius
            let bounds = PlayerTimeline.waterBounds(zoom: zoom)
            let y = bounds.bottom + radius + (bounds.top - bounds.bottom - 2 * radius) * meeting.height
            let heading: CGFloat = meeting.headOn ? -1 : 1
            let meetingPoint = CGPoint(x: world.wrap(meeting.distance), y: y)
            // A fish turned to swim at you so it stops walling you in comes straight, to pass in a moment.
            var approach = (T.kelpSwimsAtYou[spec.name] ?? []).contains(id)
                ? Approach(style: .straight, meeting: meetingPoint, seconds: 0)
                : pickApproach(meeting, meetingPoint: meetingPoint, zoom: zoom, spec: spec, rng: &draw)
            /// How far ahead of you (negative: behind) the fish is at `step`.
            func lead(_ step: Int) -> CGFloat {
                meeting.distance - timeline.distance[step] + Approach.dx(beforeMeeting: CGFloat(meetStep - step) * dt,
                    style: approach.style, heading: heading, speed: meeting.speed,
                    awaySpeed: approach.awaySpeed, turnBefore: approach.turnBefore)
            }
            func offScreen(_ step: Int) -> Bool {
                let z = timeline.zoom[step], margin = radius + T.kelpAppearMargin / z
                return lead(step) > width * (1 - T.playerScreenX) / z + margin || lead(step) < -(width * T.playerScreenX / z + margin)
            }
            var step = meetStep
            while step > 0 && !offScreen(step) { step -= 1 }
            // A fish that has to be there from the start just swims in: shown swimming away first, it would
            // be in view the whole time.
            if step == 0 && approach.style == .turn {
                approach.style = .straight
                step = meetStep
                while step > 0 && !offScreen(step) { step -= 1 }
            }
            approach.seconds = CGFloat(meetStep - step) * dt
            // Keep a glide or weave in the water it appears in.
            let start = PlayerTimeline.waterBounds(zoom: timeline.zoom[step])
            let room = min(start.top - radius - y, y - start.bottom - radius)
            if approach.style == .glide, !(start.bottom + radius...start.top - radius).contains(y + approach.height) {
                approach.height = -approach.height
                if !(start.bottom + radius...start.top - radius).contains(y + approach.height) { approach.style = .straight }
            }
            if approach.style == .weave { approach.height = min(approach.height, max(0, room)) }
            let opening = approach.offset(at: 0, heading: heading, speed: meeting.speed)
            fish.append(PlannedFish(id: id, role: meeting.role, segment: meeting.segment, fork: meeting.fork,
                lane: meeting.lane, radius: radius, meetingDistance: meeting.distance, headOn: meeting.headOn,
                startHeading: approach.style == .turn && approach.seconds > approach.turnBefore ? -heading : heading,
                spawn: CGPoint(x: world.wrap(approach.meeting.x + opening.dx), y: y + opening.dy),
                cruiseSpeed: meeting.speed, phase: CGFloat.random(in: 0..<(2 * .pi), using: &draw),
                turnTimer: CGFloat.random(in: T.aiTurnIntervalRange, using: &draw),
                retargetTimer: CGFloat.random(in: T.aiRetargetRange, using: &draw), variant: 0, styleSeed: 0,
                referenceMeal: meeting.onReferenceRoute, appearsAt: timeline.distance[step],
                approach: approach.style == .straight ? nil : approach))
            crossings.append(EncounterCrossing(fishID: id, time: Double(CGFloat(meetStep) * dt), distance: Double(meeting.distance),
                y: Double(y), radius: Double(radius), headOn: meeting.headOn, zoom: Double(zoom)))
        }
        return (styled(fish, seed: seed), crossings)
    }

    /// A Kelp Forest fish's way in, so no two arrive alike: meals glide, weave, or turn toward you; big fish
    /// do the same more gently, so they don't sweep across lanes before their meeting; gate walls only turn.
    private static func pickApproach(_ meeting: DesignedMeeting, meetingPoint: CGPoint, zoom: CGFloat, spec: MeetingSpec,
                                     rng: inout SeededGenerator) -> Approach {
        let big = meeting.role == .threat
        var styles: [(Approach.Style, Double)] = meeting.wall != nil ? [(.straight, 0.6), (.turn, 0.4)]
            : big ? [(.straight, 0.25), (.weave, 0.3), (.glide, 0.25), (.turn, 0.2)]
            : [(.straight, 0.15), (.weave, 0.3), (.glide, 0.35), (.turn, 0.2)]
        if !meeting.headOn { styles.removeAll { $0.0 == .turn } }
        var pick = Double.random(in: 0..<styles.reduce(0) { $0 + $1.1 }, using: &rng)
        let style = styles.first { pick -= $0.1; return pick < 0 }?.0 ?? .straight
        let gentle: CGFloat = big ? T.kelpBigFishApproachShare : 1
        var approach = Approach(style: style, meeting: meetingPoint, seconds: 0)
        switch style {
        case .straight: break
        case .glide:
            approach.height = CGFloat.random(in: T.kelpGlideHeight, using: &rng) * gentle / zoom
                * (Bool.random(using: &rng) ? 1 : -1)
        case .weave:
            approach.height = CGFloat.random(in: T.kelpWeaveHeight, using: &rng) * gentle / zoom
            approach.waves = CGFloat.random(in: T.kelpWeaves, using: &rng)
            approach.phase = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
        case .turn:
            // Your speed at the start, the slowest you go: grown and zoomed out you're faster, so a fish
            // swimming away at a share of this never outruns you.
            let yourSpeed = T.playfieldSize.width / CGFloat(spec.crossSeconds)
            approach.awaySpeed = yourSpeed * CGFloat.random(in: T.kelpTurnAwaySpeed, using: &rng)
            approach.turnBefore = CGFloat.random(in: T.kelpTurnBefore, using: &rng)
        }
        return approach
    }
}

/// Where Kelp Forest's kelp grows: columns along the lap after open water at the start, each a little wider or
/// narrower, and a little closer or further from the last, than the level's spacing.
enum KelpLayout {
    typealias T = GameTuning
    static func columns(_ spec: MeetingSpec, seed: UInt64) -> [PlannedKelp] {
        guard let kelp = spec.kelp else { return [] }
        let width = T.playfieldSize.width, worldWidth = width * CGFloat(spec.worldScreens)
        var rng = SeededGenerator(seed: seed &+ 0x6B656C70)
        var columns: [PlannedKelp] = []
        var left = width * T.kelpFirstColumnScreens
        while left < worldWidth - width * T.kelpFirstColumnScreens {
            let right = min(left + width * CGFloat(kelp.columns) * CGFloat.random(in: 0.85...1.15, using: &rng),
                            worldWidth - width * T.kelpFirstColumnScreens / 2)
            columns.append(PlannedKelp(x: (left + right) / 2, halfWidth: (right - left) / 2))
            left = right + width * CGFloat(kelp.gap) * CGFloat.random(in: 0.8...1.2, using: &rng)
        }
        return columns
    }
}
