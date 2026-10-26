import CoreGraphics
import FishKit
import Foundation

// The wall report: how tight a level's tightest squeeze is, measured in the real scene rather than at the planner's
// meeting instants. A ghost run records where everything that could end your run is at every step (`WallFrame`), and
// `WallSweep` sweeps the heights you could be at forward through those frames, cutting out every bigger fish, hook and
// curtain of tentacles as it comes within reach. The narrowest stretch of water left open, as a share of the water, is
// the level's tightest squeeze. It's a report, never a gate: Kraig's play decides what's a wall (Heavyweights is 5.7%
// and one of his favorites; Riptide Reef 3's first layout was 7.3% and impassable). See `WallReportTests`.

#if DEBUG
/// One simulation step of a level as a ghost run sees it: everything that could end your run, where it is. World
/// points; x unwrapped only as far as `worldWidth` wraps it.
struct WallFrame {
    struct Swimmer { let id: Int; let x: CGFloat; let y: CGFloat; let radius: CGFloat }
    struct Hook { let index: Int; let x: CGFloat; let y: CGFloat; let bait: CGFloat }
    struct Bell { let index: Int; let x: CGFloat; let y: CGFloat }
    let time: CGFloat
    let distance: CGFloat
    /// Your x (wrapped), the zoom, and the water's bounds at that zoom.
    let x: CGFloat
    let zoom: CGFloat
    let waterBottom: CGFloat
    let waterTop: CGFloat
    /// Your radius on the route being recorded.
    let radius: CGFloat
    /// The share of your usual rising and falling you have here (kelp slows you).
    let verticalScale: CGFloat
    /// Every other fish still swimming.
    let fish: [Swimmer]
    /// Every hook that could catch you now (one not yet coming up can't).
    let hooks: [Hook]
    /// Every jellyfish: its bell's rim.
    let bells: [Bell]
    let worldWidth: CGFloat
}

/// Sweeps the heights you could be at through a recording, cutting out everything deadly as it comes within reach.
enum WallSweep {
    typealias T = GameTuning

    /// What cut a stretch of water out: the thing, and the heights (your center) it closed.
    struct Cut: Equatable {
        enum Kind: Equatable { case fish(Int), hook(Int), tentacles(Int), floor, surface }
        let kind: Kind
        let low: CGFloat
        let high: CGFloat

        var name: String {
            switch kind {
            case .fish(let id): "fish \(id)"
            case .hook(let index): "hook \(index + 1)"
            case .tentacles(let index): "jelly \(index + 1)"
            case .floor: "the floor"
            case .surface: "the surface"
            }
        }
    }

    /// The water open at one step: the widest stretch you could be in, as a share of the water, and what bounds it;
    /// and all the open stretches together (`total`).
    struct Squeeze {
        let step: Int
        let time: CGFloat
        let share: CGFloat
        let total: CGFloat
        let open: ClosedRange<CGFloat>
        let below: Cut
        let above: Cut
        /// Everything cutting the water at that step.
        let cuts: [Cut]
    }

    /// Where a route stopped being swimmable: the water closed, or a meal of the route was out of reach.
    struct Closure {
        let step: Int
        let time: CGFloat
        let reason: String
    }

    /// What can end a run and is swept for.
    struct Hazards: OptionSet {
        let rawValue: Int
        static let fish = Hazards(rawValue: 1)
        static let hooks = Hazards(rawValue: 2)
        static let tentacles = Hazards(rawValue: 4)
        static let all: Hazards = [.fish, .hooks, .tentacles]
    }

    struct Result {
        /// The tightest moment (the widest open stretch at its narrowest), or nil for an empty recording.
        let tightest: Squeeze?
        /// The moment with the least open water all told.
        let least: Squeeze?
        let closed: Closure?
        /// The open share at every step swept, for a timeline.
        let shares: [CGFloat]
        /// Each route meal as it was eaten: when, how far ahead (negative: behind) its center was, and your size then.
        let eats: [(id: Int, time: CGFloat, dx: CGFloat, radius: CGFloat)]
        /// Route foods that went by uneaten, and why.
        let skipped: [(id: Int, reason: String)]
    }

    /// A route meal the sweep eats as it passes (pinned to its body, then safe from fish for the swallow). A food it
    /// can't get to is skipped, growth and all; a gate it can't get to closes the route.
    struct Meal { let id: Int; let radius: CGFloat; var gate = false }

    /// `route`: the meals to eat (pinned when met, and safe from fish while swallowing them, as the game is); nil
    /// sweeps the water freely, the 2026-10-12 measure. `jelly`: the bells' size, for their tentacles. `until`: the
    /// forward distance to stop at (lap two isn't designed).
    static func sweep(_ frames: [WallFrame], route: [Meal]? = nil, jelly: JellyLayout? = nil, hazards: Hazards = .all,
                      until: CGFloat = .infinity) -> Result {
        let dt = T.simulationStep
        // Where you could be: disjoint stretches of water, low to high. The lap's start is open water, so anywhere.
        var open: [ClosedRange<CGFloat>] = []
        var shares: [CGFloat] = []
        var tightest: Squeeze?, least: Squeeze?
        var closed: Closure?
        var eats: [(id: Int, time: CGFloat, dx: CGFloat, radius: CGFloat)] = []
        var skipped: [(id: Int, reason: String)] = []
        /// A route meal gone by uneaten: a food is skipped, a gate closes the route.
        func missedMeal(_ meal: Meal, step: Int, time: CGFloat, why: String) {
            if meal.gate {
                closed = closed ?? Closure(step: step, time: time, reason: "gate \(meal.id) is out of reach" + why)
            } else {
                skipped.append((meal.id, "meal \(meal.id)" + why))
            }
            pending[meal.id] = nil
        }
        // On a route, your size follows your own meals: a swallow from the moment you touch one, then growth, as GameScene
        // has it. Swept freely, it follows the recording's.
        var you = (radius: frames.first?.radius ?? T.baseRadius, target: frames.first?.radius ?? T.baseRadius, growFrom: CGFloat(0),
                   growElapsed: CGFloat.greatestFiniteMagnitude, swallow: (elapsed: CGFloat, duration: CGFloat, prey: CGFloat)?.none)
        var pending = Dictionary(uniqueKeysWithValues: (route ?? []).map { ($0.id, $0) })
        /// Fish that have been ahead of you: a route meal among them that's behind you, or gone, was missed.
        var ahead: Set<Int> = []
        /// Why a route meal within reach wasn't eaten, step by step (each reason once, in order).
        var missed: [Int: [String]] = [:]
        func miss(_ id: Int, _ reason: String) { if missed[id]?.last != reason { missed[id, default: []].append(reason) } }
        func missedWhy(_ id: Int) -> String {
            guard let reasons = missed[id] else { return "" }
            return " (" + (reasons.count > 2 ? [reasons[0], "…", reasons[reasons.count - 1]] : reasons).joined(separator: "; then ") + ")"
        }
        /// Each route meal's last position and course, carried on once the recording drops it.
        var lastSeen: [Int: (x: CGFloat, y: CGFloat, radius: CGFloat, dx: CGFloat, dy: CGFloat)] = [:]
        var safeUntil: CGFloat = -1
        var bounceUntil: CGFloat = -1
        for (step, frame) in frames.enumerated() where frame.distance < until {
            if route != nil {
                if var current = you.swallow {
                    current.elapsed += dt
                    if current.elapsed >= current.duration {
                        you.target = GameRules.grownRadius(predator: you.target, prey: current.prey,
                                                           efficiency: T.freeEncounterAbsorption * T.mealGrowthScale)
                        you.growFrom = you.radius
                        you.growElapsed = 0
                        you.swallow = nil
                    } else {
                        you.swallow = current
                    }
                }
                if you.growElapsed < T.growDuration {
                    you.growElapsed += dt
                    let t = min(1, you.growElapsed / T.growDuration)
                    you.radius = you.growFrom + (you.target - you.growFrom) * (1 - pow(1 - t, 3))
                }
            }
            let r = route == nil ? frame.radius : you.radius
            let world = WrappedWorld(width: frame.worldWidth)
            let floor = frame.waterBottom + r * 0.95, surface = max(frame.waterBottom + r * 0.95, frame.waterTop - r * 0.95)
            let waterHeight = max(1, frame.waterTop - frame.waterBottom)
            if open.isEmpty && step == 0 { open = [floor...surface] }
            // Rising and falling as fast as you can (a bounce lifts you faster for a moment).
            let rise = (frame.time < bounceUntil ? T.jellyBounceSpeed : T.motion.maxRiseSpeed * frame.verticalScale) / frame.zoom * dt
            let fall = T.motion.maxFallSpeed * frame.verticalScale / frame.zoom * dt
            open = merged(open.map { max(floor, $0.lowerBound - fall)...min(surface, max(floor, $0.upperBound + rise)) })
            var cuts: [Cut] = []
            let safe = frame.time < safeUntil
            if hazards.contains(.fish) && !safe {
                for f in frame.fish where GameRules.playerEncounter(r, f.radius) != .firstEatsSecond {
                    let reach = (r + f.radius) * T.collisionScale
                    let dx = world.delta(from: frame.x, to: f.x)
                    guard abs(dx) < reach else { continue }
                    let h = (reach * reach - dx * dx).squareRoot()
                    cuts.append(Cut(kind: .fish(f.id), low: f.y - h, high: f.y + h))
                }
            }
            let body = r * T.hazardHitboxScale
            if hazards.contains(.hooks) {
                for hook in frame.hooks {
                    let dx = world.delta(from: frame.x, to: hook.x)
                    // The bait, and the hook's bend under it (`HookRules.catches`).
                    for (center, reach) in [(CGPoint(x: dx, y: hook.y), body + hook.bait * T.sunsetBaitHitScale),
                                            (CGPoint(x: dx + HookRules.bend.x * hook.bait, y: hook.y + HookRules.bend.y * hook.bait),
                                             body + hook.bait * T.sunsetHookHitShare)] where abs(center.x) < reach {
                        let h = (reach * reach - center.x * center.x).squareRoot()
                        cuts.append(Cut(kind: .hook(hook.index), low: center.y - h, high: center.y + h))
                    }
                }
            }
            if let jelly {
                for bell in frame.bells {
                    let dx = world.delta(from: frame.x, to: bell.x)
                    if hazards.contains(.tentacles) && abs(dx) < jelly.radius * 0.72 + body {
                        cuts.append(Cut(kind: .tentacles(bell.index), low: bell.y - jelly.tentacleLength - body, high: bell.y + body))
                    }
                    // Resting on its dome, you're launched up for a moment: a bounce.
                    let across = min(1, abs(dx) / (jelly.radius + body))
                    let landing = bell.y + jelly.radius * 0.65 * (1 - across * across).squareRoot() + body + 2
                    if abs(dx) < jelly.radius + body, open.contains(where: { ($0.lowerBound - 3...$0.upperBound + 3).contains(landing) }) {
                        bounceUntil = frame.time + T.jellyBounceSeconds
                    }
                }
            }
            for cut in cuts { open = open.flatMap { subtract(cut.low...cut.high, from: $0) } }
            guard let widest = open.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound }) else {
                let by = cuts.map { String(format: "%@ %.0f–%.0f", $0.name, $0.low, $0.high) }.joined(separator: ", ")
                    + String(format: "; water %.0f–%.0f, you r %.0f", floor, surface, r)
                closed = Closure(step: step, time: frame.time, reason: "the water closed" + (by.isEmpty ? "" : " (\(by))"))
                shares.append(0)
                break
            }
            let share = (widest.upperBound - widest.lowerBound) / waterHeight
            let total = open.reduce(0) { $0 + $1.upperBound - $1.lowerBound } / waterHeight
            shares.append(share)
            // A squeeze is water something deadly has cut: the start's open water and a meal you're reaching for don't count.
            if tightest.map({ share < $0.share }) ?? true || least.map({ total < $0.total }) ?? true {
                let below = cuts.filter { $0.high >= widest.lowerBound - 0.01 && $0.high <= widest.lowerBound + 0.01 }.max { $0.high < $1.high }
                let above = cuts.filter { $0.low >= widest.upperBound - 0.01 && $0.low <= widest.upperBound + 0.01 }.min { $0.low < $1.low }
                if below != nil || above != nil {
                    let squeeze = Squeeze(step: step, time: frame.time, share: share, total: total, open: widest,
                                          below: below ?? Cut(kind: .floor, low: -.infinity, high: floor),
                                          above: above ?? Cut(kind: .surface, low: surface, high: .infinity), cuts: cuts)
                    if tightest.map({ share < $0.share }) ?? true { tightest = squeeze }
                    if least.map({ total < $0.total }) ?? true { least = squeeze }
                }
            }
            // A route's meal: the first moment it's edible and you could be touching it, you eat it (anywhere within
            // reach of its body: being there isn't a squeeze, the water around a meal is as open as it is), then you're
            // safe from fish for the swallow. One that passes you first, or is gone, closes the route.
            // (The recording drops a route meal as its center passes yours; it swims on for the rest of its contact
            // window, so its last course is carried on.)
            var meals: [WallFrame.Swimmer] = frame.fish
            for id in pending.keys.sorted() where ahead.contains(id) && !frame.fish.contains(where: { $0.id == id }) {
                guard let last = lastSeen[id] else { continue }
                meals.append(WallFrame.Swimmer(id: id, x: last.x + last.dx, y: last.y + last.dy, radius: last.radius))
            }
            for f in meals {
                let dx = world.delta(from: frame.x, to: f.x)
                if dx > 0 && dx < frame.worldWidth / 4 { ahead.insert(f.id) }
                guard let meal = pending[f.id], ahead.contains(f.id) else { continue }
                let reach = (r + meal.radius) * T.collisionScale
                if dx <= -reach {
                    missedMeal(meal, step: step, time: frame.time, why: missedWhy(f.id))
                    if closed != nil { break }
                    continue
                }
                guard abs(dx) < reach else { continue }
                guard you.swallow == nil else {
                    miss(f.id, "you were still swallowing")
                    continue
                }
                guard GameRules.playerEncounter(r, f.radius) == .firstEatsSecond else {
                    miss(f.id, String(format: "bigger than you: r %.1f vs %.1f", f.radius, r))
                    continue
                }
                let h = (reach * reach - dx * dx).squareRoot()
                guard open.contains(where: { intersection($0, f.y - h...f.y + h) != nil }) else {
                    let by = cuts.filter { $0.low < f.y + h && $0.high > f.y - h }.map(\.name)
                    let places = open.map { String(format: "%.0f–%.0f", $0.lowerBound, $0.upperBound) }.joined(separator: ", ")
                    miss(f.id, String(format: "at y %.0f you could be at %@%@", f.y, places,
                                      by.isEmpty ? "" : ", cut off by " + by.joined(separator: ", ")))
                    continue
                }
                open = open.compactMap { intersection($0, f.y - reach...f.y + reach) }
                pending[f.id] = nil
                eats.append((f.id, frame.time, dx, r))
                let duration = SwallowTiming.duration(sizeRatio: meal.radius / r, curve: T.swallowDurationCurve)
                safeUntil = frame.time + duration
                you.swallow = (0, duration, meal.radius)
            }
            for f in frame.fish where pending[f.id] != nil {
                let was = lastSeen[f.id]
                lastSeen[f.id] = (f.x, f.y, f.radius, was.map { world.delta(from: $0.x, to: f.x) } ?? 0, was.map { f.y - $0.y } ?? 0)
            }
            for id in pending.keys where lastSeen[id] != nil && !frame.fish.contains(where: { $0.id == id }) {
                lastSeen[id]!.x += lastSeen[id]!.dx
                lastSeen[id]!.y += lastSeen[id]!.dy
            }
            if closed != nil { break }
        }
        return Result(tightest: tightest, least: least, closed: closed, shares: shares, eats: eats, skipped: skipped)
    }

    private static func merged(_ ranges: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var result: [ClosedRange<CGFloat>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func intersection(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> ClosedRange<CGFloat>? {
        let low = max(a.lowerBound, b.lowerBound), high = min(a.upperBound, b.upperBound)
        return low <= high ? low...high : nil
    }

    /// `range` with `cut` taken out of it: what's left below and above the cut.
    private static func subtract(_ cut: ClosedRange<CGFloat>, from range: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        guard cut.upperBound > range.lowerBound, cut.lowerBound < range.upperBound else { return [range] }
        var pieces: [ClosedRange<CGFloat>] = []
        if cut.lowerBound > range.lowerBound { pieces.append(range.lowerBound...cut.lowerBound) }
        if cut.upperBound < range.upperBound { pieces.append(cut.upperBound...range.upperBound) }
        return pieces
    }
}

/// A level's wall report: every route swept, the worst of them, and the fish that outgrow you.
struct WallStudy {
    typealias T = GameTuning

    /// One route through the level: the meals eaten, and what the sweep made of it.
    struct Route {
        let name: String
        let meals: Set<Int>
        /// The sweep pinned to the route's meals, everything deadly counted.
        let result: WallSweep.Result
        /// The same with bigger fish only.
        let fishOnly: WallSweep.Result

        /// 0 for a route that closed.
        var share: CGFloat { result.closed == nil ? result.tightest?.share ?? 1 : 0 }
    }

    /// A fish that grew, eating what you passed, past what the fullest route could eat by the time you met it.
    struct Outgrown {
        let id: Int
        let planned: CGFloat
        let grown: CGFloat
        let yours: CGFloat
        let time: CGFloat
        let lap: Int
    }

    let plan: MeetingPlan
    let routes: [Route]
    /// The water swept freely, no route: the 2026-10-12 measure, with and without hooks and tentacles.
    let free: WallSweep.Result
    let freeFishOnly: WallSweep.Result
    let outgrown: [Outgrown]
    let seconds: Double

    /// The route whose tightest squeeze is tightest (a closed route counts as 0).
    var worst: Route? { routes.min { ($0.share, $0.name) < ($1.share, $1.name) } }
    var fishCount: Int { plan.fish.count }
    /// Meals on the fullest route with a bigger fish crossing close by (the planner's own count).
    var dangerMeals: Int {
        let route = plan.fullestRoute
        return plan.analysis.meetings.filter { route.contains($0.crossing.fishID) && $0.danger }.count
    }

    /// The routes worth sweeping: the reference route the meetings were timed against, the fullest, every mix of lanes
    /// (every single and gate, one lane per fork), and each mix's fewest-meal route (each segment's `needed` smallest
    /// meals of the mix, then its gate), where the mix has that many.
    static func routes(_ plan: MeetingPlan) -> [(name: String, meals: Set<Int>)] {
        var routes: [(name: String, meals: Set<Int>)] = [
            ("reference", Set(plan.fish.filter(\.referenceMeal).map(\.id))), ("fullest", plan.fullestRoute),
        ]
        let forks = Set(plan.fish.compactMap(\.fork)).sorted()
        let gates = plan.fish.filter { $0.role == .gate }.map(\.id)
        let plain = plan.fish.filter { $0.role == .food && $0.fork == nil }
        var lean: [(name: String, meals: Set<Int>)] = []
        for choice in 0..<(1 << forks.count) {
            let lanes = forks.enumerated().map { index, fork in (fork, choice >> index & 1) }
            let foods = plain + plan.fish.filter { f in f.fork.map { fork in lanes.contains { $0 == (fork, f.lane) } } ?? false }
            let name = lanes.map { $0.1 == 0 ? "L" : "S" }.joined()
            routes.append(("lanes " + name, Set(foods.map(\.id) + gates)))
            var fewest = Set(gates)
            for (index, segment) in plan.spec.segments.enumerated() {
                let own = foods.filter { $0.segment == index }.sorted { $0.radius < $1.radius }
                guard own.count >= segment.needed else { fewest = []; break }
                fewest.formUnion(own.prefix(segment.needed).map(\.id))
            }
            if !fewest.isEmpty { lean.append(("fewest " + name, fewest)) }
        }
        var seen: Set<Set<Int>> = []
        return (routes + lean).filter { seen.insert($0.meals).inserted }
    }

    /// Studies `plan` with `record`, which plays a ghost run eating the given meals for this many laps and returns its
    /// frames. The squeeze is measured over the first lap (the planned one); the fish's growth over both.
    static func study(_ plan: MeetingPlan, record: (_ meals: Set<Int>, _ laps: CGFloat) -> [WallFrame]) -> WallStudy {
        let started = Date()
        let lap = T.playfieldSize.width * CGFloat(plan.spec.worldScreens)
        let jelly = plan.spec.jellies.map { JellySpec.layout($0, count: plan.jellies?.count ?? 0) }
        let byID = Dictionary(uniqueKeysWithValues: plan.fish.map { ($0.id, $0) })
        var routes: [Route] = []
        var fullestFrames: [WallFrame] = []
        for (name, meals) in Self.routes(plan) {
            let frames = record(meals, name == "fullest" ? 2.1 : 1.05)
            if name == "fullest" { fullestFrames = frames }
            let route = meals.compactMap { byID[$0] }.map { WallSweep.Meal(id: $0.id, radius: $0.radius, gate: $0.role == .gate) }
            routes.append(Route(name: name, meals: meals,
                                result: WallSweep.sweep(frames, route: route, jelly: jelly, until: lap * 1.05),
                                fishOnly: WallSweep.sweep(frames, route: route, jelly: jelly, hazards: .fish, until: lap * 1.05)))
        }
        let reference = routes.first { $0.name == "reference" }.map(\.meals) ?? []
        let referenceFrames = record(reference, 1.05)
        let free = WallSweep.sweep(referenceFrames, jelly: jelly, until: lap * 1.05)
        let freeFishOnly = WallSweep.sweep(referenceFrames, jelly: jelly, hazards: .fish, until: lap * 1.05)
        return WallStudy(plan: plan, routes: routes, free: free, freeFishOnly: freeFishOnly,
                         outgrown: outgrown(plan, frames: fullestFrames), seconds: Date().timeIntervalSince(started))
    }

    /// Fish bigger than the fullest route's player when they cross it, having grown past their planned size.
    static func outgrown(_ plan: MeetingPlan, frames: [WallFrame]) -> [Outgrown] {
        let byID = Dictionary(uniqueKeysWithValues: plan.fish.map { ($0.id, $0) })
        var previous: [Int: CGFloat] = [:]
        var flags: [Outgrown] = []
        for frame in frames {
            let world = WrappedWorld(width: frame.worldWidth)
            for f in frame.fish {
                let dx = world.delta(from: frame.x, to: f.x)
                defer { previous[f.id] = dx }
                guard let last = previous[f.id], last > 0, dx <= 0, last < frame.worldWidth / 4, let planned = byID[f.id] else { continue }
                let grew = f.radius > planned.radius + 0.5
                let edible = GameRules.playerEncounter(frame.radius, f.radius) == .firstEatsSecond
                let wasEdible = GameRules.playerEncounter(frame.radius, planned.radius) == .firstEatsSecond
                if grew && !edible && wasEdible {
                    flags.append(Outgrown(id: f.id, planned: planned.radius, grown: f.radius, yours: frame.radius, time: frame.time,
                                          lap: Int(frame.distance / frame.worldWidth) + 1))
                }
            }
        }
        return flags
    }

    /// The routes with a way through, and of those the one with the widest lane at its tightest.
    var open: [Route] { routes.filter { $0.result.closed == nil } }
    var best: Route? { open.max { ($0.share, $0.name) < ($1.share, $1.name) } }
    var reference: Route? { routes.first { $0.name == "reference" } }

    /// The level's line of the report's table.
    func row(world: String, level: Int) -> String {
        func pct(_ result: WallSweep.Result) -> String {
            result.closed != nil ? "closed" : result.tightest.map { String(format: "%.1f%%", $0.share * 100) } ?? "open"
        }
        /// The widest lane, and all the open water, at their narrowest.
        func both(_ result: WallSweep.Result) -> String {
            guard result.closed == nil, let tightest = result.tightest, let least = result.least else { return pct(result) }
            return String(format: "%.1f%% / %.1f%%", tightest.share * 100, least.total * 100)
        }
        func at(_ result: WallSweep.Result) -> String {
            if let closed = result.closed { return String(format: "closed at %.1f s: %@", closed.time, closed.reason) }
            guard let squeeze = result.tightest else { return "open" }
            return String(format: "%.1f%% at %.1f s: %@ / %@", squeeze.share * 100, squeeze.time, describe(squeeze.below), describe(squeeze.above))
        }
        let grown = outgrown.map { String(format: "fish %d %.0f→%.0f (you %.0f, lap %d)", $0.id, $0.planned, $0.grown, $0.yours, $0.lap) }
        return "| \(world) | \(level) | \(plan.spec.name) | \(fishCount) | \(dangerMeals) | " +
            "\(both(freeFishOnly)) | \(both(free)) | \(open.count) / \(routes.count) | " +
            "\(best.map { "\($0.name): \(pct($0.result))" + ($0.result.skipped.isEmpty ? "" : " (−\($0.result.skipped.count) meals)") } ?? "none") | " +
            "\(reference.map { at($0.result) + ($0.result.skipped.isEmpty ? "" : " (−\($0.result.skipped.count) meals)") } ?? "–") | " +
            (grown.isEmpty ? "" : grown.joined(separator: "; ")) + " |"
    }

    static let header = "| world | level | name | fish | danger | free (fish): lane / all water | free (all hazards) | routes open | best route | reference route | outgrown |\n" +
        "|---|---|---|---|---|---|---|---|---|---|---|"

    /// Every route's squeeze, for the level's detail, after the free sweep's.
    var detail: String {
        let freely = "- free (reference route's fish): " + (free.closed.map { String(format: "closed at %.1f s (%@)", $0.time, $0.reason) }
            ?? free.tightest.map { String(format: "%.1f%% at %.1f s between %@ and %@", $0.share * 100, $0.time, describe($0.below), describe($0.above)) } ?? "–")
            + "; fish only " + (freeFishOnly.closed.map { String(format: "closed at %.1f s (%@)", $0.time, $0.reason) }
            ?? freeFishOnly.tightest.map { String(format: "%.1f%% at %.1f s between %@ and %@", $0.share * 100, $0.time, describe($0.below), describe($0.above)) } ?? "–")
        return ([freely] + routes.map { route in
            let eaten = route.result.eats.map { String(format: "%d at %.2f s (dx %.0f, you %.1f)", $0.id, $0.time, $0.dx, $0.radius) }.joined(separator: ", ")
            let skips = route.result.skipped.isEmpty ? "" : "; skipped " + route.result.skipped.map(\.reason).joined(separator: ", ")
            let all = (route.result.closed.map { String(format: "closed at %.1f s (%@); ate %@", $0.time, $0.reason, eaten) }
                ?? route.result.tightest.map { String(format: "%.1f%% at %.1f s between %@ and %@", $0.share * 100, $0.time, describe($0.below), describe($0.above)) } ?? "open") + skips
            let fish = route.fishOnly.closed.map { _ in "closed" } ?? route.fishOnly.tightest.map { String(format: "%.1f%%", $0.share * 100) } ?? "–"
            return "- \(route.name) (\(route.meals.sorted().map(String.init).joined(separator: " "))): \(all); fish only \(fish)"
        }).joined(separator: "\n")
    }

    private func describe(_ cut: WallSweep.Cut) -> String {
        guard case .fish(let id) = cut.kind, let f = plan.fish.first(where: { $0.id == id }) else { return cut.name }
        return "fish \(id) (\(f.role.rawValue), r \(Int(f.radius.rounded())))"
    }
}

// MARK: - The opening from the plan alone

extension MeetingPlan {
    /// The level's tightest squeeze from the plan alone, in milliseconds: every fish held to its way in is where the
    /// plan puts it until it's let go, hooks and bells where their motions put them, and `WallSweep` sweeps the heights
    /// you could be at through them with the reference route's fish gone as they're eaten (the wall report's free
    /// measure, without the scene); `pinned` eats the route's meals as the report's route sweep does. Nil for a plan
    /// whose fish swim freely from the start (the searching planner's): their swims are only known by simulating them.
    func plannedOpening(pinned: Bool = false) -> WallSweep.Result? {
        guard !fish.isEmpty, fish.allSatisfy({ $0.appearsAt != nil }) else { return nil }
        typealias T = GameTuning
        let dt = T.simulationStep, width = T.playfieldSize.width, lap = width * CGFloat(spec.worldScreens)
        let world = WrappedWorld(width: lap)
        let reference = fish.filter(\.referenceMeal)
        let timeline = PlayerTimeline.reference(meals: reference.map { ($0.meetingDistance, $0.radius) },
            crossSeconds: CGFloat(spec.crossSeconds), until: lap * 1.05, currents: currents ?? [], lap: lap)
        let columns = kelp ?? []
        let bells = spec.jellies.map { JellySpec.layout($0, count: jellies?.count ?? 0) }
        var frames: [WallFrame] = []
        frames.reserveCapacity(timeline.lastStep + 1)
        for step in 0...timeline.lastStep {
            let distance = timeline.distance[step], zoom = timeline.zoom[step], time = CGFloat(step) * dt
            let x = world.wrap(distance)
            let bounds = PlayerTimeline.waterBounds(zoom: zoom)
            let swimmers = fish.compactMap { f -> WallFrame.Swimmer? in
                // A route meal is eaten as its center passes yours, as the report's ghost run has it.
                if !pinned, f.referenceMeal, f.meetingDistance <= distance { return nil }
                guard let at = MeetingSolver.wayInPosition(f, step: step, timeline: timeline) else { return nil }
                return WallFrame.Swimmer(id: f.id, x: world.wrap(at.x), y: at.y, radius: f.radius)
            }
            // A hook can catch you once it's less than half a lap ahead (`GameScene.isComingUp`).
            let rigs = (hooks ?? []).enumerated().compactMap { index, hook -> WallFrame.Hook? in
                let at = HookMotion.position(hook, time: time)
                guard at.x - distance < lap / 2 else { return nil }
                return WallFrame.Hook(index: index, x: world.wrap(at.x), y: at.y, bait: hook.baitRadius)
            }
            let drifting = (jellies ?? []).enumerated().map { index, jelly in
                let at = JellyDrift.position(origin: jelly.origin, phase: jelly.phase, time: time, screenWidth: width, world: world)
                return WallFrame.Bell(index: index, x: at.x, y: at.y)
            }
            let inKelp = columns.contains { abs(world.delta(from: $0.x, to: x)) <= $0.halfWidth }
            frames.append(WallFrame(time: time, distance: distance, x: x, zoom: zoom, waterBottom: bounds.bottom, waterTop: bounds.top,
                                    radius: timeline.radius[step], verticalScale: inKelp ? T.kelpDrag : 1,
                                    fish: swimmers, hooks: rigs, bells: drifting, worldWidth: lap))
        }
        let route = pinned ? reference.map { WallSweep.Meal(id: $0.id, radius: $0.radius, gate: $0.role == .gate) } : nil
        return WallSweep.sweep(frames, route: route, jelly: bells, until: lap * 1.05)
    }

    /// Whether the water shuts somewhere on the lap with every fish, hook and bell where the plan puts it, or its widest
    /// lane at its tightest is under `GameTuning.wallOpening` (`plannedOpening`): no way through for anyone, as Kelp
    /// Forest 13's first layout had. (A route of the plan's own that can't be swum isn't a wall by itself: players
    /// find another, as the wall report shows on levels Kraig likes.) The pickers that take the first clean layout pass
    /// one with a wall by, as they do a wall of giants. Always false for a plan whose fish swim freely from the start.
    var hasWall: Bool {
        guard let opening = plannedOpening() else { return false }
        return opening.closed != nil || (opening.tightest?.share ?? 1) < GameTuning.wallOpening
    }
}
#endif
