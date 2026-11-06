import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

/// The wall report (`WallReport.swift`): the sweep's own checks, and the marker-activated reports over the campaign and
/// over history. A report, never a gate: no level's squeeze fails a test here (the route bot loses some of Kraig's best
/// levels, and Heavyweights is 5.7% and a favorite).
struct WallReportTests {
    private static let water = PlayerTimeline.waterBounds(zoom: 1)

    private static func frame(step: Int, radius: CGFloat = 16, fish: [WallFrame.Swimmer] = [], hooks: [WallFrame.Hook] = [],
                              bells: [WallFrame.Bell] = [], zoom: CGFloat = 1, verticalScale: CGFloat = 1) -> WallFrame {
        let bounds = PlayerTimeline.waterBounds(zoom: zoom)
        return WallFrame(time: CGFloat(step) * GameTuning.simulationStep, distance: CGFloat(step) * 5, x: 1000, zoom: zoom,
                         waterBottom: bounds.bottom, waterTop: bounds.top, radius: radius, verticalScale: verticalScale,
                         fish: fish, hooks: hooks, bells: bells, worldWidth: 4000)
    }

    @Test func sweepMeasuresTheGapTwoGiantsLeave() throws {
        // Two giants (r 80) alongside you, one low and one high: the water between their reaches is what's left.
        let giants = [WallFrame.Swimmer(id: 1, x: 1000, y: 60, radius: 80), WallFrame.Swimmer(id: 2, x: 1000, y: 340, radius: 80)]
        let frames = (0..<30).map { Self.frame(step: $0, fish: $0 == 15 ? giants : []) }
        let result = WallSweep.sweep(frames)
        let reach = (16 + 80) * GameTuning.collisionScale
        let expected = ((340 - reach) - (60 + reach)) / (Self.water.top - Self.water.bottom)
        let tightest = try #require(result.tightest)
        #expect(result.closed == nil && tightest.step == 15)
        #expect(abs(tightest.share - expected) < 0.001)
        #expect(tightest.below.kind == .fish(1) && tightest.above.kind == .fish(2))
        // Open water: everything but the 0.95 radii your center keeps off the floor and the surface. Once the giants
        // have gone the water opens up again as fast as you can swim.
        let openWater = (Self.water.top - Self.water.bottom - 2 * 0.95 * 16) / (Self.water.top - Self.water.bottom)
        #expect(abs(result.shares[0] - openWater) < 0.001 && result.shares[29] > result.shares[16] && result.shares[29] < openWater)
        // Overlapping reaches close the water.
        let wall = [WallFrame.Swimmer(id: 1, x: 1000, y: 100, radius: 80), WallFrame.Swimmer(id: 2, x: 1000, y: 300, radius: 80)]
        let closed = WallSweep.sweep((0..<30).map { Self.frame(step: $0, fish: $0 == 15 ? wall : []) })
        #expect(closed.closed?.step == 15 && closed.closed?.reason.contains("fish 1") == true && closed.closed?.reason.contains("fish 2") == true)
    }

    @Test func sweepSweepsHeightsForwardAsFastAsYouCanSwim() {
        // A giant filling the lower water for a while (its reach up to 203), then one filling the upper water a moment
        // later (its reach down to 157): between them you have to dive 46 points, which takes 11 steps at 250 points a
        // second, 17 in kelp.
        func frames(scale: CGFloat, gap: Int) -> [WallFrame] {
            (0..<80).map { step in
                let low = (10..<30).contains(step) ? [WallFrame.Swimmer(id: 1, x: 1000, y: 60, radius: 120)] : []
                let high = ((30 + gap)..<(50 + gap)).contains(step) ? [WallFrame.Swimmer(id: 2, x: 1000, y: 300, radius: 120)] : []
                return Self.frame(step: step, fish: low + high, verticalScale: scale)
            }
        }
        #expect(WallSweep.sweep(frames(scale: 1, gap: 14)).closed == nil)
        #expect(WallSweep.sweep(frames(scale: 1, gap: 6)).closed != nil)
        #expect(WallSweep.sweep(frames(scale: GameTuning.kelpDrag, gap: 14)).closed != nil)
    }

    @Test func sweepCountsHooksAndTentaclesButNotDomes() throws {
        // A hook's bait and bend cut the water; its line doesn't, and nor does a bell's dome.
        let hook = [WallFrame.Hook(index: 0, x: 1000, y: 200, bait: 10)]
        let frames = (0..<10).map { Self.frame(step: $0, hooks: $0 == 5 ? hook : []) }
        let all = WallSweep.sweep(frames), fishOnly = WallSweep.sweep(frames, hazards: .fish)
        #expect(all.tightest?.step == 5 && all.tightest?.cuts.contains { $0.kind == .hook(0) } == true)
        // Nothing cuts the water for fish alone: no squeeze at all.
        #expect(fishOnly.tightest == nil)
        let jelly = JellyLayout(count: 1, radius: 40, tentacleLength: 70, night: false)
        let bell = [WallFrame.Bell(index: 0, x: 1000, y: 250)]
        let stung = WallSweep.sweep((0..<10).map { Self.frame(step: $0, bells: $0 == 5 ? bell : []) }, jelly: jelly)
        let cut = try #require(stung.tightest?.cuts.first)
        #expect(cut.kind == .tentacles(0) && cut.low < 180 && cut.high > 250 && cut.high < 270)
    }

    @Test func sweepPinsARouteToItsMealsAndIsSafeFromFishWhileSwallowing() {
        // A meal low in the water, then a giant crossing on top of it a beat later: eating the meal puts you under the
        // giant, but a swallow keeps you safe from fish. Free, the giant cuts the water; on the route, it doesn't.
        func frames(mealY: CGFloat) -> [WallFrame] {
            (0..<60).map { step in
                let meal = (18...24).contains(step) ? [WallFrame.Swimmer(id: 7, x: 1000 + CGFloat(21 - step) * 4, y: mealY, radius: 13)] : []
                let giant = (26...32).contains(step) ? [WallFrame.Swimmer(id: 8, x: 1000, y: mealY, radius: 60)] : []
                return Self.frame(step: step, fish: meal + giant)
            }
        }
        let route = [WallSweep.Meal(id: 7, radius: 13, gate: true)]
        let free = WallSweep.sweep(frames(mealY: 100)), routed = WallSweep.sweep(frames(mealY: 100), route: route)
        #expect(free.tightest?.cuts.contains { $0.kind == .fish(8) } == true)
        #expect(routed.closed == nil && routed.tightest?.cuts.contains { $0.kind == .fish(8) } != true)
        // Eating the meal at first touch, the open water right after it is only as wide as your reach of it.
        #expect(routed.shares[19] < 0.25)
        // A meal you can't get to (a giant sitting on it as it passes) closes the route.
        let blocked = (0..<60).map { step in
            let meal = (18...24).contains(step) ? [WallFrame.Swimmer(id: 7, x: 1000 + CGFloat(21 - step) * 4, y: 100, radius: 13)] : []
            let giant = (14...26).contains(step) ? [WallFrame.Swimmer(id: 8, x: 1000, y: 100, radius: 60)] : []
            return Self.frame(step: step, fish: meal + giant)
        }
        let reason = WallSweep.sweep(blocked, route: route).closed?.reason ?? ""
        #expect(reason.hasPrefix("gate 7 is out of reach (at y 100") && reason.contains("cut off by fish 8"))
        // A food you can't get to is skipped instead, and the route goes on.
        let snack = WallSweep.sweep(blocked, route: [WallSweep.Meal(id: 7, radius: 13)])
        #expect(snack.closed == nil && snack.skipped.map(\.id) == [7] && snack.eats.isEmpty)
    }

    @Test func studySweepsTheRoutesAndTheirLaneMixes() {
        // Medium (Shallow Reef 4): three forks give eight lane mixes, besides the fewest, reference and fullest routes.
        let plan = GameTuning.reefLabLevels[5].meetingPlan!
        let routes = WallStudy.routes(plan)
        #expect(routes.count >= 2 + 4 && routes.count <= 2 + 16)
        #expect(routes.map(\.name).prefix(2) == ["reference", "fullest"])
        #expect(routes.contains { $0.name.hasPrefix("fewest") })
        #expect(Set(routes.map(\.meals)).count == routes.count)
        for route in routes where route.name.hasPrefix("lanes") {
            let forks = Dictionary(grouping: route.meals.compactMap { id in plan.fish.first { $0.id == id } }.filter { $0.fork != nil }, by: { $0.fork! })
            #expect(forks.values.allSatisfy { Set($0.map(\.lane)).count == 1 })
            #expect(plan.fish.filter { $0.role == .gate }.allSatisfy { route.meals.contains($0.id) })
        }
    }

    // MARK: - Reports (marker-activated, local only)

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let folder = root.appendingPathComponent("build/arcade-development")

    /// A ghost run of `plan` in `world`'s scene, eating `meals`, for `laps` laps: the frames the sweep reads.
    @MainActor static func frames(_ plan: MeetingPlan, world: ArcadeWorld, meals: Set<Int>, laps: CGFloat) -> [WallFrame] {
        let scene = GameScene(world: world, levelIndex: 0, showsJellyLesson: false)
        scene.debugUsePlan(plan)
        var frames: [WallFrame] = []
        _ = scene.debugEncounterCrossings(radii: plan.radii(eating: meals), eaten: meals, laps: laps) { frames.append(scene.debugWallFrame) }
        return frames
    }

    @MainActor static func study(_ plan: MeetingPlan, world: ArcadeWorld) -> WallStudy {
        WallStudy.study(plan) { meals, laps in frames(plan, world: world, meals: meals, laps: laps) }
    }

    /// The world a plan plays in, by its name, for plans from outside the campaign (history, other variations).
    static func world(named name: String) -> ArcadeWorld {
        if name.hasPrefix("Sunset") { return .sunsetCove }
        if name.hasPrefix("Kelp") { return .kelpForest }
        if name.hasPrefix("Midnight") { return .midnightZone }
        if name.hasPrefix("Riptide") { return .riptideReef }
        if name.hasPrefix("Jelly") || name.hasPrefix("Night") || ["Bell Field", "Curtain"].contains(name) { return .jellyBloom }
        return .shallowReef
    }

    /// The wall report over every level of the campaign and the prototypes, when
    /// build/arcade-development/wall-report.request exists. The marker may name worlds (`sunset-cove`) and level numbers
    /// to report only those. Writes wall-report.md and wall-report.json beside it.
    @MainActor @Test func manualWallReport() throws {
        let marker = Self.folder.appendingPathComponent("wall-report.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let words = ((try? String(contentsOf: marker, encoding: .utf8)) ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        let worlds = (ArcadeWorld.campaign + ArcadeWorld.prototypes).filter { words.isEmpty || words.contains($0.rawValue) || !words.contains { ArcadeWorld(rawValue: $0) != nil } }
        let numbers = Set(words.compactMap { Int($0) })
        var lines = [WallStudy.header], details: [String] = [], json: [[String: Any]] = []
        for world in worlds {
            for index in world.levels.indices where numbers.isEmpty || numbers.contains(index + 1) {
                let plan = world.level(index).meetingPlan!
                let study = Self.study(plan, world: world)
                lines.append(study.row(world: world.rawValue, level: index + 1))
                details.append("### \(world.rawValue) \(index + 1): \(plan.spec.name) (\(String(format: "%.1f", study.seconds)) s)\n" + study.detail)
                json.append(Self.json(study, world: world.rawValue, level: index + 1))
            }
        }
        let text = "# Wall report\n\nShares of the water open at the tightest moment: the water swept freely (the 2026-10-12 measure), " +
            "and pinned to each route's meals (safe from fish while swallowing). \"closed\" means no way through on that route.\n\n" +
            lines.joined(separator: "\n") + "\n\n## Routes\n\n" + details.joined(separator: "\n\n") + "\n"
        try text.write(to: Self.folder.appendingPathComponent("wall-report.md"), atomically: true, encoding: .utf8)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: Self.folder.appendingPathComponent("wall-report.json"))
    }

    /// The report over the known walls as they were before their fixes and after, when
    /// build/arcade-development/wall-history.request exists. Layouts in code (Riptide Reef 3's first layout, Kelp Forest
    /// 13's) are planned here; plans from the past are read from build/arcade-development/wall-history/*.json, one
    /// `MeetingPlan` each, taken from the plans files' git history, for example:
    ///
    ///     git show 7a4b35b:BiggerFish/ReefLabPlans.json | python3 -c "import json,sys; p=json.load(sys.stdin);
    ///         json.dump([x for x in p if x['spec']['name']=='Gauntlet'][0], open('build/arcade-development/wall-history/gauntlet-7a4b35b.json','w'))"
    ///
    /// Writes wall-history.md beside the marker.
    @MainActor @Test func manualWallHistory() throws {
        let marker = Self.folder.appendingPathComponent("wall-history.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        var cases: [(label: String, plan: MeetingPlan, world: ArcadeWorld)] = []
        let riptide = GameTuning.riptideSpecs[2]
        cases.append(("Riptide Reef 3, layout 0 (impassable)", MeetingPlanner.kelpPlan(riptide, variation: 0), .riptideReef))
        cases.append(("Riptide Reef 3, layout 4 (shipped)", MeetingPlanner.kelpPlan(riptide, variation: 4), .riptideReef))
        cases.append(("Kelp Forest 13, layout 0 (giant wall)", MeetingPlanner.kelpPlan(GameTuning.kelpSpecs[12], variation: 0), .kelpForest))
        cases.append(("Kelp Forest 13, shipped", ArcadeWorld.kelpForest.level(12).meetingPlan!, .kelpForest))
        let history = Self.folder.appendingPathComponent("wall-history")
        let files = ((try? FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            let plan = try JSONDecoder().decode(MeetingPlan.self, from: Data(contentsOf: file))
            cases.append((file.deletingPathExtension().lastPathComponent + " (\(plan.spec.name))", plan, Self.world(named: plan.spec.name)))
        }
        var lines = [WallStudy.header], details: [String] = []
        for (label, plan, world) in cases {
            let study = Self.study(plan, world: world)
            lines.append(study.row(world: world.rawValue, level: 0).replacingOccurrences(of: "| \(plan.spec.name) |", with: "| \(label) |"))
            details.append("### \(label)\n" + study.detail)
        }
        let text = "# Wall history\n\n" + lines.joined(separator: "\n") + "\n\n## Routes\n\n" + details.joined(separator: "\n\n") + "\n"
        try text.write(to: Self.folder.appendingPathComponent("wall-history.md"), atomically: true, encoding: .utf8)
    }

    private static func json(_ study: WallStudy, world: String, level: Int) -> [String: Any] {
        func result(_ result: WallSweep.Result) -> [String: Any] {
            var json: [String: Any] = ["share": result.closed == nil ? Double(result.tightest?.share ?? 1) : 0]
            if let squeeze = result.tightest {
                json["time"] = Double(squeeze.time)
                json["below"] = squeeze.below.name
                json["above"] = squeeze.above.name
            }
            if let closed = result.closed { json["closed"] = ["time": Double(closed.time), "reason": closed.reason] }
            return json
        }
        return ["world": world, "level": level, "name": study.plan.spec.name, "fish": study.fishCount, "danger": study.dangerMeals,
                "free": result(study.free), "freeFishOnly": result(study.freeFishOnly),
                "routes": study.routes.map { ["name": $0.name, "meals": $0.meals.sorted(), "all": result($0.result), "fishOnly": result($0.fishOnly)] },
                "outgrown": study.outgrown.map { ["fish": $0.id, "planned": Double($0.planned), "grown": Double($0.grown), "yours": Double($0.yours), "lap": $0.lap] }]
    }
}
