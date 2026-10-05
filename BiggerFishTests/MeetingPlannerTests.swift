import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

private final class BundleToken {}

extension GameScene {
    static func plannerScene(_ spec: MeetingSpec, variation: Int = 0) -> GameScene {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        scene.debugUsePlanner(spec, variation: variation)
        return scene
    }
}

struct MeetingPlannerTests {
    private static func crossing(_ id: Int, at time: Double, y: Double = 200, radius: Double) -> EncounterCrossing {
        EncounterCrossing(fishID: id, time: time, distance: time * 300, y: y, radius: radius, headOn: true, zoom: 1)
    }

    @Test func analyzerFindsFewestMealsRoutesAndMissesSurvived() {
        // Three level foods, then a gate any one of them makes edible.
        let analysis = EncounterAnalyzer.analyze([
            Self.crossing(1, at: 1, radius: 10), Self.crossing(2, at: 1.6, radius: 10),
            Self.crossing(3, at: 2.2, radius: 10), Self.crossing(4, at: 3, radius: 17),
        ])
        let gate = analysis.meeting(fishID: 4)!
        #expect(analysis.meeting(fishID: 1)?.minimumMeals == 0)
        #expect(gate.minimumMeals == 1 && gate.maximumMeals == 3 && gate.routes == 3)
        // You'd have to miss all three foods.
        #expect(gate.robustSlack == 2)
        #expect(analysis.maximumMeals == 4 && analysis.fullestRoute == [1, 2, 3, 4])
    }

    @Test func analyzerRespectsSwallowTimeReachAndCrowdedCrossings() {
        // A near-equal swallow (about 0.7 s) blocks a meal 0.3 s later.
        let swallow = EncounterAnalyzer.analyze([Self.crossing(1, at: 1, radius: 15), Self.crossing(2, at: 1.3, radius: 8)])
        #expect(swallow.maximumMeals == 1)
        // Two foods at the same moment, top and bottom of the water: one or the other.
        let split = EncounterAnalyzer.analyze([Self.crossing(1, at: 1.5, y: 40, radius: 9), Self.crossing(2, at: 1.5, y: 360, radius: 9)])
        #expect(split.maximumMeals == 1 && split.meeting(fishID: 1)?.routes == 1)
        // A bigger fish crossing on top of a food makes it uneatable; slightly off, it's a danger meal.
        let blocked = EncounterAnalyzer.analyze([Self.crossing(1, at: 1.5, radius: 9), Self.crossing(2, at: 1.52, radius: 30)])
        #expect(blocked.meeting(fishID: 1)?.minimumMeals == nil)
        let danger = EncounterAnalyzer.analyze([Self.crossing(1, at: 1.5, radius: 9), Self.crossing(2, at: 1.7, y: 300, radius: 30)])
        #expect(danger.meeting(fishID: 1)?.danger == true)
    }

    @Test func reefLabPlansCleanlyAndGetsHarderLevelByLevel() {
        let specs = GameTuning.reefLabSpecs
        let plans = specs.map { MeetingPlanner.plan($0) }
        for plan in plans {
            #expect(plan.issues.isEmpty, "\(plan.spec.name): \(plan.issues)")
            #expect(plan.fish.map(\.id) == Array(1...plan.fish.count))
            // Level 1 introduces gates alone; big fish to dodge come from level 2.
            #expect(plan.fish.contains { $0.role == .threat } == (plan.spec.extraThreats > 0 || plan.spec.segments.contains { $0.dangerFoods > 0 }))
        }
        let tightest = plans.map { plan in
            plan.fish.filter { $0.role == .gate }.compactMap { plan.analysis.meeting(fishID: $0.id)?.robustSlack }.min() ?? -1
        }
        // Levels 2, 6, and 10 are the playtested Easy, Medium, and Hard.
        #expect(tightest[1] >= tightest[5] && tightest[5] >= tightest[9] && tightest[1] > tightest[9])
        #expect([specs[1].name, specs[5].name, specs[9].name] == ["Easy", "Medium", "Hard"])
        for (previous, next) in zip(specs, specs.dropFirst()) {
            #expect(next.aiSpeed.upperBound > previous.aiSpeed.upperBound && next.crossSeconds < previous.crossSeconds)
            #expect(next.gateMargin < previous.gateMargin && next.dangerGap < previous.dangerGap)
            #expect(next.lapTwoSize.upperBound > previous.lapTwoSize.upperBound)
        }
        #expect(MeetingPlanner.plan(specs[0]).seed == plans[0].seed)
    }

    @MainActor @Test func plannedFishMeetThePlayerWherePlannedOnAnyRoute() {
        for spec in [GameTuning.reefLabSpecs[1], GameTuning.reefLabSpecs[5], GameTuning.reefLabSpecs[9]] {
            let plan = MeetingPlanner.plan(spec)
            let reference = Set(plan.fish.filter(\.referenceMeal).map(\.id))
            let scene = GameScene.plannerScene(spec)
            let actual = scene.debugEncounterCrossings(radii: plan.referenceRadii, eaten: reference)
            for predicted in plan.predicted {
                let real = actual.first { $0.fishID == predicted.fishID }
                #expect(real.map { abs($0.time - predicted.time) < 0.05 && abs($0.y - predicted.y) < 3 } == true,
                        "\(spec.name) fish \(predicted.fishID)")
            }
            #expect(scene.debugVisibleUnmetContacts == 0)
            // A player who eats only what each gate needs, or everything, still meets every fish.
            for route in [plan.fewestMealRoute, plan.fullestRoute] {
                let crossings = GameScene.plannerScene(spec).debugEncounterCrossings(radii: plan.radii(eating: route), eaten: route)
                #expect(Set(crossings.map(\.fishID)) == Set(plan.fish.map(\.id)), "\(spec.name)")
            }
        }
    }

    @MainActor @Test func reefLabIsATenLevelThirdWorldThatUnlocksAndResetsLikeACampaign() {
        #expect(ArcadeWorld.mapWorlds == [.shallowReef, .jellyBloom, .reefLab])
        let world = ArcadeWorld.reefLab
        #expect(world.levelCount == 10 && world.levelTitles == (1...10).map { "Level \($0)" })
        let progress = ArcadeProgress(defaults: UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!)
        #expect(progress.isOpen(world, 0) && !progress.isOpen(world, 1) && !progress.isOpen(world, 10))
        progress.clear(world, 0, seconds: 20)
        progress.clear(.shallowReef, 0, seconds: 30)
        #expect(progress.isOpen(world, 1) && progress.save.bestTimes["reef-lab.1"] == 20)
        progress.reset(world)
        #expect(!progress.isCleared(world, 0) && progress.save.bestTimes["reef-lab.1"] == nil)
        #expect(progress.isCleared(.shallowReef, 0))
        let scene = GameScene(world: world, levelIndex: 5)
        #expect(scene.debugEncounterCrossings(laps: 0.01).isEmpty)
        #expect(scene.debugFishCount == world.level(5).meetingPlan!.fish.count + 1)
        #expect(scene.debugMeetingPlan?.spec.name == "Medium")
    }

    /// The shipped plans must be what the planner makes today; regenerate them with the marker below.
    @Test func bundledReefLabPlansMatchThePlanner() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "ReefLabPlans", withExtension: "json")
            ?? Bundle.main.url(forResource: "ReefLabPlans", withExtension: "json"))
        let bundled = try JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: url))
        #expect(bundled.map(\.spec) == GameTuning.reefLabSpecs, "ReefLabPlans.json is out of date: regenerate it")
        for plan in bundled {
            #expect(plan.fish == MeetingPlanner.plan(plan.spec).fish, "\(plan.spec.name): regenerate ReefLabPlans.json")
        }
    }

    /// Writes BiggerFish/ReefLabPlans.json when build/arcade-development/reef-lab-plans.request exists.
    @Test func manualWriteReefLabPlans() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/reef-lab-plans.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plans = GameTuning.reefLabSpecs.map { MeetingPlanner.plan($0) }
        try encoder.encode(plans).write(to: Self.root.appendingPathComponent("BiggerFish/ReefLabPlans.json"))
    }

    @MainActor @Test func plannedLevelsSpawnEveryFishAndKeepPlannedFishOnTheirLine() {
        let scene = GameScene.plannerScene(GameTuning.reefLabSpecs[5])
        let plan = scene.debugMeetingPlan!
        #expect(scene.debugEncounterCrossings(laps: 0.01).isEmpty)
        #expect(scene.debugFishCount == plan.fish.count + 1)
        #expect(scene.debugPlannedFishHoldTheirLine())
    }

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Local-only report on the presets and the shipped campaign, activated by a marker under ignored build/.
    @MainActor @Test func manualMeetingStudy() throws {
        let folder = Self.root.appendingPathComponent("build/arcade-development")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("meeting-study.request").path) else { return }
        var lines: [String] = []
        for spec in GameTuning.reefLabSpecs {
            let started = Date()
            let plan = MeetingPlanner.plan(spec)
            lines.append("## \(spec.name): \(plan.fish.count) fish, seed \(plan.seed), planned in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            lines.append("issues: \(plan.issues)")
            // Forks are choices only if their lanes exclude each other: the most you can eat on lap one
            // should be every single, every gate, and one lane per fork.
            let designedMost = spec.segments.reduce(0) { $0 + $1.mostMeals + 1 }
            let forkMeals = plan.fish.filter { $0.fork != nil }
            let lanesEaten = Dictionary(grouping: forkMeals.filter { plan.fullestRoute.contains($0.id) }, by: { $0.fork! })
                .mapValues { Set($0.map(\.lane)).count }
            lines.append("most lap-one meals \(plan.analysis.maximumMeals), designed \(designedMost); forks with both lanes on the fullest route: \(lanesEaten.filter { $0.value > 1 }.count) of \(Set(forkMeals.compactMap(\.fork)).count)")
            let actual = GameScene.plannerScene(spec).debugEncounterCrossings(radii: plan.referenceRadii,
                eaten: Set(plan.fish.filter(\.referenceMeal).map(\.id)))
            lines.append(Self.table(plan: plan, actual: actual))
            for policy in ArcadeSimulation.Policy.allCases {
                let result = GameScene.plannerScene(spec).debugSimulate(candidate: spec.name, tuning: ArcadeTuning(level: plan.level),
                    policy: policy, seed: 0, limit: 90)
                lines.append("\nbot \(policy.rawValue): \(result.outcome) in \(String(format: "%.1f", result.seconds)) s, \(result.stats.playerMeals) meals, \(result.reason)")
            }
            // How close each gate and returning threat is for a player who eats everything on lap one.
            let full = plan.radii(eating: plan.fullestRoute)
            func size(at fish: PlannedFish) -> Double {
                let time = plan.predicted.first { $0.fishID == fish.id }!.time
                return Double(fish.radius / full[min(full.count - 1, Int(time / Double(GameTuning.simulationStep)))])
            }
            let gateRatios = plan.fish.filter { $0.role == .gate }.map { String(format: "%.2f", size(at: $0)) }
            let threatRatios = plan.fish.filter { $0.role == .threat }.map { String(format: "%.2f", Double($0.radius / full.last!)) }
            let guardedMeals = plan.analysis.meetings.filter(\.danger).count
            lines.append("\neating everything: gates at \(gateRatios.joined(separator: ", ")) of your size; lap-two fish at \(threatRatios.joined(separator: ", ")) of your end size; danger meals \(guardedMeals)")
            for (route, meals) in [("fewest meals", plan.fewestMealRoute), ("fullest", plan.fullestRoute)] {
                let crossings = GameScene.plannerScene(spec).debugEncounterCrossings(radii: plan.radii(eating: meals), eaten: meals)
                let drift = plan.predicted.compactMap { predicted -> (Int, Double, Double)? in
                    guard let real = crossings.first(where: { $0.fishID == predicted.fishID }) else { return (predicted.fishID, .infinity, .infinity) }
                    return (predicted.fishID, real.time - predicted.time, real.y - predicted.y)
                }
                let worst = drift.max { abs($0.1) < abs($1.1) }
                let analysis = EncounterAnalyzer.analyze(crossings)
                let gates = plan.fish.filter { $0.role == .gate }.map { gate -> String in
                    let m = analysis.meeting(fishID: gate.id)
                    return "gate \(gate.id): meals \(m?.minimumMeals.map(String.init) ?? "–") routes \(m?.routes ?? 0) slack \(m?.robustSlack.map(String.init) ?? "–")"
                }
                lines.append("\n\(route): worst time drift \(worst.map { "fish \($0.0) \(String(format: "%.2f", $0.1)) s" } ?? "–"), " +
                    "worst height drift \(String(format: "%.0f", drift.map { abs($0.2) }.max() ?? 0)) pt, missing \(drift.filter { $0.1.isInfinite }.map(\.0)) · " + gates.joined(separator: " · "))
            }
        }
        try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("meeting-study.md"), atomically: true, encoding: .utf8)
    }

    /// The shipped campaign through the same lens: a ghost run, then a replay eating the fullest route.
    @MainActor @Test func manualCampaignStudy() throws {
        let folder = Self.root.appendingPathComponent("build/arcade-development")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("campaign-study.request").path) else { return }
        var lines = ["| world | slot | met | max meals | gates (meals/routes/slack) | tightest slack | danger meals | head-on | mean gap s |",
                     "|---|---|---|---|---|---|---|---|---|"]
        var json: [[String: Any]] = []
        for world in ArcadeWorld.campaign {
            for index in world.levels.indices {
                let first = EncounterAnalyzer.analyze(GameScene(world: world, levelIndex: index).debugEncounterCrossings())
                let byID = Dictionary(uniqueKeysWithValues: first.meetings.map { ($0.crossing.fishID, $0.crossing) })
                let meals = first.fullestRoute.compactMap { byID[$0] }.map { (CGFloat($0.distance), CGFloat($0.radius)) }
                let radii = PlayerTimeline.reference(meals: meals, crossSeconds: world.levels[index].screenCrossSeconds,
                    until: GameTuning.playfieldSize.width * GameTuning.worldScreens * 1.05).radius
                let crossings = GameScene(world: world, levelIndex: index)
                    .debugEncounterCrossings(radii: radii, eaten: Set(first.fullestRoute))
                let analysis = EncounterAnalyzer.analyze(crossings)
                // A gate is a fish about your size that only becomes edible after earlier meals.
                let gates = analysis.meetings.filter { ($0.minimumMeals ?? 0) >= 1 && ($0.sizeRatio ?? 0) >= 0.9 }
                let gaps = zip(crossings.dropFirst(), crossings).map { $0.time - $1.time }
                let route = Set(analysis.fullestRoute)
                let danger = analysis.meetings.filter { route.contains($0.crossing.fishID) && $0.danger }.count
                lines.append("| \(world.rawValue) | \(index + 1) | \(crossings.count) | \(analysis.maximumMeals) | " +
                    gates.map { "\($0.minimumMeals!)/\($0.routes)/\($0.robustSlack.map(String.init) ?? "–")" }.joined(separator: ", ") +
                    " | \(gates.compactMap(\.robustSlack).min().map(String.init) ?? "–") | \(danger) | " +
                    String(format: "%.0f%%", 100 * Double(crossings.filter(\.headOn).count) / Double(max(1, crossings.count))) +
                    " | " + String(format: "%.2f", gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)) + " |")
                json.append(["world": world.rawValue, "slot": index + 1,
                             "analysis": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(analysis))) ?? [:]])
            }
        }
        try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("campaign-study.md"), atomically: true, encoding: .utf8)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("campaign-study.json"))
    }

    static func table(plan: MeetingPlan, actual: [EncounterCrossing]) -> String {
        var rows = ["| id | role | seg | t plan | t real | y plan | y real | size | head-on | min meals | max | routes | slack | ratio | danger |",
                    "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for fish in plan.fish {
            let predicted = plan.predicted.first { $0.fishID == fish.id }
            let real = actual.first { $0.fishID == fish.id }
            let meeting = plan.analysis.meeting(fishID: fish.id)
            func f(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }
            rows.append("| \(fish.id) | \(fish.role.rawValue) | \(fish.segment + 1) | \(f(predicted?.time)) | \(f(real?.time)) | \(f(predicted?.y)) | \(f(real?.y)) | \(f(Double(fish.radius / GameTuning.baseRadius))) | \(fish.headOn) | \(meeting?.minimumMeals.map(String.init) ?? "–") | \(meeting?.maximumMeals.map(String.init) ?? "–") | \(meeting?.routes ?? 0) | \(meeting?.robustSlack.map(String.init) ?? "–") | \(f(meeting?.sizeRatio)) | \(meeting?.danger == true ? "yes" : "") |")
        }
        return rows.joined(separator: "\n")
    }
}
