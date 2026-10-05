#if DEBUG
import Combine
import Foundation
import SwiftUI

struct ArcadeTuning: Codable, Equatable {
    struct Group: Codable, Equatable {
        var count: Int
        var minimum: Double
        var maximum: Double
    }
    var groups: [Group]
    var aiMinimum: Double
    var aiMaximum: Double
    var aiVertical: Double
    var crossingSeconds: Double
    var absorption: Double
    var jellyCount: Int
    var jellyRadius: Double
    var tentacleLength: Double
    var bounceSpeed: Double
    var releaseSeconds: Double
    var roam: Bool
    var unevenJellies: Bool
    var layoutVariation: Double
    var seedOffset: Int
    var difficulty: Double?

    init(level: Level) {
        groups = level.spawnGroups.map { Group(count: $0.count, minimum: Double($0.radii.lowerBound), maximum: Double($0.radii.upperBound)) }
        aiMinimum = Double(level.aiSpeedRange.lowerBound)
        aiMaximum = Double(level.aiSpeedRange.upperBound)
        aiVertical = Double(level.aiVerticalSpeed)
        crossingSeconds = Double(level.screenCrossSeconds)
        absorption = Double(level.absorptionEfficiency)
        jellyCount = level.jellies?.count ?? 0
        jellyRadius = Double(level.jellies?.radius ?? 44)
        tentacleLength = Double(level.jellies?.tentacleLength ?? 70)
        bounceSpeed = Double(GameTuning.jellyBounceSpeed)
        releaseSeconds = Double(GameTuning.bloomFoodPocketReleaseSeconds)
        roam = level.roamingFoodChain
        unevenJellies = level.roamingFoodChain
        layoutVariation = 1
        seedOffset = Int(level.ecosystemSeedOffset)
        difficulty = level.encounterDifficulty?.bounded
    }

    mutating func setEncounterDifficultyEnabled(_ enabled: Bool, for level: Level) {
        difficulty = enabled ? (level.encounterDifficulty?.bounded ?? 0) : nil
    }

    func displayedSpawnSeed(world: ArcadeWorld, index: Int) -> UInt64 {
        var base = world.levels[index]
        if difficulty == nil {
            if world == .shallowReef, index < GameTuning.shallowReferenceLevels.count {
                base = GameTuning.shallowReferenceLevels[index]
                base.ecosystemSeedIndex = index
            } else if world == .jellyBloom {
                let source = base.ecosystemSeedIndex ?? index
                if source < GameTuning.bloomReferenceLevels.count {
                    base = GameTuning.bloomReferenceLevels[source]
                    base.ecosystemSeedIndex = source
                }
            }
        }
        return base.spawnSeed(index: index, bloom: world == .jellyBloom, offset: UInt64(sanitized.seedOffset))
    }

    func encounterWaveBudgets(for level: Level, index: Int, bloom: Bool) -> [(count: Int, edible: Int)] {
        GameTuning.freeEncounterWaveBudgets(
            seed: level.spawnSeed(index: index, bloom: bloom, offset: UInt64(sanitized.seedOffset)),
            difficulty: sanitized.difficulty ?? 0, preserveLevelTwo: bloom && index == 1, shallow: !bloom)
    }

    /// Bound saved and edited settings before they reach physics or spawn ranges.
    var sanitized: Self {
        var result = self
        func bound(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        result.groups = Array(groups.prefix(5)).map {
            let lo = bound($0.minimum, 0.25...3, fallback: 0.5)
            return Group(count: min(12, max(0, $0.count)), minimum: lo,
                         maximum: bound($0.maximum, lo...3, fallback: lo))
        }
        result.aiMinimum = bound(aiMinimum, 10...200, fallback: 65)
        result.aiMaximum = bound(aiMaximum, result.aiMinimum...200, fallback: result.aiMinimum)
        result.aiVertical = bound(aiVertical, 10...120, fallback: 80)
        result.crossingSeconds = bound(crossingSeconds, 2...4, fallback: 3)
        result.absorption = bound(absorption, 0.5...1, fallback: 0.78)
        result.jellyCount = min(7, max(0, jellyCount))
        result.jellyRadius = bound(jellyRadius, 30...55, fallback: 44)
        result.tentacleLength = bound(tentacleLength, 40...100, fallback: 70)
        result.bounceSpeed = bound(bounceSpeed, 300...600, fallback: 460)
        result.releaseSeconds = bound(releaseSeconds, 0...12, fallback: 4)
        result.layoutVariation = bound(layoutVariation, 0...1, fallback: 1)
        result.seedOffset = min(999, max(0, seedOffset))
        result.difficulty = difficulty.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        if result.difficulty != nil { result.jellyCount = GameTuning.encounterCount }
        return result
    }

    func applying(to base: Level) -> Level {
        let value = sanitized
        let difficulty = (base.freeEncounterMovement || base.jellies != nil)
            ? value.difficulty.map { EncounterDifficulty(value: $0) } : nil
        let groups: [(count: Int, radii: ClosedRange<CGFloat>)]
        if base.freeEncounterMovement && difficulty != nil {
            groups = base.spawnGroups
        } else if let difficulty {
            let food = GameTuning.encounterFoodRadius
            let target = difficulty.returnRadius(food: food, efficiency: CGFloat(value.absorption) * GameTuning.mealGrowthScale)
            groups = [(12, food...food), (4, target...target)]
        } else {
            groups = value.groups.map { ($0.count, CGFloat($0.minimum)...CGFloat($0.maximum)) }
        }
        var result = Level(spawnGroups: groups,
            aiSpeedRange: CGFloat(value.aiMinimum)...CGFloat(value.aiMaximum), aiVerticalSpeed: CGFloat(value.aiVertical),
            screenCrossSeconds: CGFloat(value.crossingSeconds), absorptionEfficiency: CGFloat(value.absorption))
        if let layout = base.jellies, value.jellyCount > 0 {
            result.jellies = JellyLayout(count: value.jellyCount, radius: CGFloat(value.jellyRadius),
                tentacleLength: CGFloat(value.tentacleLength), sway: layout.sway, night: layout.night,
                maintainsFloorLane: true, heights: layout.heights)
        }
        result.encounterDifficulty = difficulty
        result.freeEncounterMovement = base.freeEncounterMovement && difficulty != nil
        result.aiCanEat = base.aiCanEat
        result.requiredMeals = base.requiredMeals
        result.bounceFoodPockets = base.bounceFoodPockets && result.jellies != nil
        result.sidePocketExperiment = base.sidePocketExperiment && value.jellyCount > GameTuning.bloomSidePocketJellyIndex
        result.roamingFoodChain = value.roam
        result.ecosystemSeedOffset = UInt64(value.seedOffset)
        result.ecosystemSeedIndex = base.ecosystemSeedIndex
        result.compactAISpeedScale = base.compactAISpeedScale
        result.mediumAISpeedMultiplier = base.mediumAISpeedMultiplier
        return result
    }
}

enum MeetingPlannerSummary {
    /// "18 fish · gates after 2, 6, 10 meals · misses survived 1, 0, 0 · routes 3, 3, 3".
    static func text(_ plan: MeetingPlan) -> String {
        let gates = plan.fish.filter { $0.role == .gate }.compactMap { plan.analysis.meeting(fishID: $0.id) }
        func list(_ values: [String]) -> String { values.joined(separator: ", ") }
        var text = "\(plan.fish.count) fish · gates after \(list(gates.map { $0.minimumMeals.map(String.init) ?? "–" })) meals"
        text += " · misses survived \(list(gates.map { $0.robustSlack.map { $0 >= EncounterAnalysis.slackCap ? "\($0)+" : String($0) } ?? "–" }))"
        text += " · routes \(list(gates.map { String($0.routes) }))"
        return plan.issues.isEmpty ? text : text + " · ⚠︎ " + plan.issues.joined(separator: "; ")
    }
}

struct ArcadeTuningPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var tuning: ArcadeTuning
}

final class ArcadeTuningStore: ObservableObject {
    @Published private(set) var presets: [ArcadeTuningPreset]
    private let defaults: UserDefaults
    private static let overridesKey = "biggerFish.debug.tuning.v1"
    private static let presetsKey = "biggerFish.debug.tuning.presets.v1"
    private static let reorderedOverridesKey = "biggerFish.debug.tuning.reordered-3-6-7.v1"
    private static let shallowCampaignOverridesKey = "biggerFish.debug.tuning.shallow-ten-level.v1"

    private static let shallowReorderedOverridesKey = "biggerFish.debug.tuning.shallow-move-3-to-8.v1"

    init(defaults: UserDefaults = ArcadePlaytest.defaults) {
        self.defaults = defaults
        presets = defaults.data(forKey: Self.presetsKey).flatMap { try? JSONDecoder().decode([ArcadeTuningPreset].self, from: $0) } ?? []
        if !defaults.bool(forKey: Self.reorderedOverridesKey) {
            let original = allOverrides
            var reordered = original
            for (destination, source) in GameTuning.bloomCampaignOrder.enumerated() where destination != source {
                reordered[ArcadeWorld.jellyBloom.levelID(destination)] = original[ArcadeWorld.jellyBloom.levelID(source)]
            }
            defaults.set(try? JSONEncoder().encode(reordered), forKey: Self.overridesKey)
            defaults.set(true, forKey: Self.reorderedOverridesKey)
        }
        if !defaults.bool(forKey: Self.shallowCampaignOverridesKey) {
            let original = allOverrides
            let oldShallow = original.filter { $0.key.hasPrefix("shallow-reef.") }
            if !oldShallow.isEmpty {
                defaults.set(try? JSONEncoder().encode(oldShallow), forKey: "biggerFish.debug.tuning.shallow-original-backup.v1")
                defaults.set(try? JSONEncoder().encode(original.filter { !$0.key.hasPrefix("shallow-reef.") }), forKey: Self.overridesKey)
            }
            defaults.set(true, forKey: Self.shallowCampaignOverridesKey)
        }
        if !defaults.bool(forKey: Self.shallowReorderedOverridesKey) {
            let original = allOverrides
            var reordered = original
            for (destination, source) in GameTuning.shallowCampaignOrder.enumerated() where destination != source {
                reordered[ArcadeWorld.shallowReef.levelID(destination)] = original[ArcadeWorld.shallowReef.levelID(source)]
            }
            defaults.set(try? JSONEncoder().encode(reordered), forKey: Self.overridesKey)
            defaults.set(true, forKey: Self.shallowReorderedOverridesKey)
        }
    }
    func override(_ world: ArcadeWorld, _ index: Int) -> ArcadeTuning? {
        allOverrides[world.levelID(index)]?.sanitized
    }
    private var allOverrides: [String: ArcadeTuning] {
        defaults.data(forKey: Self.overridesKey).flatMap { try? JSONDecoder().decode([String: ArcadeTuning].self, from: $0) } ?? [:]
    }
    func save(_ tuning: ArcadeTuning, world: ArcadeWorld, index: Int) {
        var values = allOverrides
        values[world.levelID(index)] = tuning.sanitized
        defaults.set(try? JSONEncoder().encode(values), forKey: Self.overridesKey)
    }
    func clear(world: ArcadeWorld, index: Int) {
        var values = allOverrides
        values[world.levelID(index)] = nil
        defaults.set(try? JSONEncoder().encode(values), forKey: Self.overridesKey)
    }
    func savePreset(name: String, tuning: ArcadeTuning) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets.removeAll { $0.name == trimmed }
        presets.insert(ArcadeTuningPreset(name: trimmed, tuning: tuning.sanitized), at: 0)
        presets = Array(presets.prefix(10))
        defaults.set(try? JSONEncoder().encode(presets), forKey: Self.presetsKey)
    }
    static func sceneOverride(world: ArcadeWorld, index: Int) -> ArcadeTuning? {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !ProcessInfo.processInfo.arguments.contains("-arcadeDisableTuning") else { return nil }
        return ArcadeTuningStore().override(world, index)
    }
}

struct ArcadeTuningPanel: View {
    @ObservedObject var store: ArcadeTuningStore
    @Environment(\.dismiss) private var dismiss
    @State private var world: ArcadeWorld
    @State private var index: Int
    @State private var draft: ArcadeTuning
    @State private var presetName = ""
    @State private var validation: ArcadeCandidateValidation.Report?
    @State private var validationTask: Task<Void, Never>?
    @State private var isChecking = false
    @State private var plannerVariation = 0
    @State private var plannerSummaries: [String: String] = [:]
    @State private var resetWorld: ArcadeWorld = .reefLab
    @State private var confirmsReset = false
    let onPlanner: (MeetingSpec, Int) -> Void
    let onResetProgress: (ArcadeWorld) -> Void
    let onPlay: (ArcadeWorld, Int) -> Void

    init(store: ArcadeTuningStore, world: ArcadeWorld, index: Int, onPlanner: @escaping (MeetingSpec, Int) -> Void,
         onResetProgress: @escaping (ArcadeWorld) -> Void, onPlay: @escaping (ArcadeWorld, Int) -> Void) {
        self.store = store
        _world = State(initialValue: world)
        _index = State(initialValue: index)
        _draft = State(initialValue: store.override(world, index) ?? ArcadeTuning(level: world.levels[index]))
        self.onPlanner = onPlanner
        self.onResetProgress = onResetProgress
        self.onPlay = onPlay
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Players") {
                    Text("Start a world over from level 1 for a new player, for A/B testing.").font(.footnote)
                    Picker("World", selection: $resetWorld) {
                        ForEach(ArcadeWorld.mapWorlds) { Text($0.title).tag($0) }
                    }
                    Button("Reset \(resetWorld.title) progress", role: .destructive) { confirmsReset = true }
                        .confirmationDialog("Clear every \(resetWorld.title) clear and best time on this device?",
                                            isPresented: $confirmsReset, titleVisibility: .visible) {
                            Button("Reset \(resetWorld.title)", role: .destructive) { onResetProgress(resetWorld) }
                        }
                }
                Section("\(ArcadeWorld.reefLab.title) variations") {
                    Text("Other layouts of the same \(ArcadeWorld.reefLab.title) settings: every fish swims freely but is timed to cross your path at a planned height. Practice runs only.")
                        .font(.footnote)
                    Stepper("Variation: \(plannerVariation)", value: $plannerVariation, in: 0...99)
                    ForEach(Array(GameTuning.reefLabSpecs.enumerated()), id: \.offset) { index, spec in
                        Button("Play \(ArcadeWorld.reefLab.title) level \(index + 1)") {
                            dismiss()
                            onPlanner(spec, plannerVariation)
                        }
                        Text(plannerSummaries[spec.name] ?? "Planning…").font(.footnote).monospacedDigit()
                    }
                }
                .task(id: plannerVariation) { await summarizePlans() }
                Section {
                    Picker("World", selection: $world) {
                        ForEach(ArcadeWorld.campaign) { Text($0.title).tag($0) }
                    }
                    Picker("Level", selection: $index) {
                        ForEach(world.levels.indices, id: \.self) { Text("Level \($0 + 1)").tag($0) }
                    }
                    Text("Apply starts a fresh practice run. Practice runs don't change campaign progress. Closing leaves your current run paused.")
                        .font(.footnote)
                }
                if world.levels[index].encounterDifficulty != nil {
                    Section("Encounter difficulty") {
                        Toggle("Use encounter difficulty", isOn: Binding(
                            get: { draft.difficulty != nil },
                            set: { draft.setEncounterDifficultyEnabled($0, for: world.levels[index]) }))
                        if let value = draft.difficulty {
                            let target = EncounterDifficulty(value: value)
                            slider("Difficulty", value: Binding(get: { draft.difficulty ?? 0 },
                                set: { draft.difficulty = $0 }), range: 0...1, step: 0.01)
                            if world.levels[index].freeEncounterMovement {
                                let percentage = 100 * Double(GameTuning.freeEncounterExpectedCatchFraction(value, shallow: world == .shallowReef))
                                Text("Expected growth assumes catching \(percentage, specifier: "%.0f")% of edible fish in each starting wave.")
                                let budgets = draft.encounterWaveBudgets(for: world.levels[index], index: index, bloom: world == .jellyBloom)
                                Text("Edible at expected arrival size: " + budgets.map { "\($0.edible) of \($0.count)" }.joined(separator: ", ") + ". Fish roam freely; each unlocks after you pass its starting position.")
                                    .font(.footnote)
                            } else {
                            Text("Catch at least \(target.minimumCatches) of 12 opening fish to reach an unchanged return threat. \(target.spareCatches) spare catches.")
                            Text("Extra recovery: \(target.recoveryPasses, specifier: "%.2f") circuits · Clearance: \(target.clearance, specifier: "%.0f") points")
                            Text("Each area holds its fish until you pass, then allows this extra recovery time before competition starts. Targets describe the protected opening; later AI meals can change the growth requirement.")
                                .font(.footnote)
                            }
                        }
                    }
                }
                if draft.difficulty == nil {
                Section("Fish — size is relative to your starting radius") {
                    Text("Groups set starting fish counts and sizes, not encounter order. Fish can grow by eating other fish.")
                        .font(.footnote)
                    ForEach(draft.groups.indices, id: \.self) { i in
                        VStack(alignment: .leading) {
                            Stepper("Group \(i + 1): \(draft.groups[i].count) fish", value: $draft.groups[i].count, in: 0...12)
                            slider("Group \(i + 1) minimum size", value: $draft.groups[i].minimum, range: 0.25...3, step: 0.05)
                            slider("Group \(i + 1) maximum size", value: $draft.groups[i].maximum, range: 0.25...3, step: 0.05)
                        }
                    }
                    slider("Growth per meal", value: Binding(
                        get: { draft.absorption * Double(GameTuning.mealGrowthScale) },
                        set: { draft.absorption = $0 / Double(GameTuning.mealGrowthScale) }),
                        range: (0.5 * Double(GameTuning.mealGrowthScale))...Double(GameTuning.mealGrowthScale), step: 0.01)
                }
                }
                Section("Movement and competition") {
                    slider("AI minimum speed", value: $draft.aiMinimum, range: 10...200, step: 5)
                    slider("AI maximum speed", value: $draft.aiMaximum, range: 10...200, step: 5)
                    slider("AI vertical speed", value: $draft.aiVertical, range: 10...120, step: 5)
                    slider("Seconds across screen", value: $draft.crossingSeconds, range: 2...4, step: 0.1)
                    if world == .jellyBloom {
                        if draft.difficulty == nil {
                        Toggle("Fish leave opening pockets", isOn: $draft.roam)
                        slider("Pocket release seconds", value: $draft.releaseSeconds, range: 0...12, step: 0.5)
                        }
                    }
                }
                if world == .jellyBloom {
                    Section("Jellyfish") {
                        Stepper("Jellyfish: \(draft.jellyCount)", value: $draft.jellyCount, in: 0...7)
                            .disabled(draft.difficulty != nil)
                        Toggle("Uneven layout", isOn: $draft.unevenJellies)
                        slider("Layout variation", value: $draft.layoutVariation, range: 0...1, step: 0.1)
                        slider("Bell radius", value: $draft.jellyRadius, range: 30...55, step: 1)
                        slider("Tentacle length", value: $draft.tentacleLength, range: 40...100, step: 5)
                        slider("Bounce strength", value: $draft.bounceSpeed, range: 300...600, step: 10)
                    }
                }
                Section("Level seed") {
                    LabeledContent("Seed", value: String(draft.displayedSpawnSeed(world: world, index: index)))
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Text("\(world.title) · Level \(index + 1)")
                        .font(.footnote)
                    Stepper("Seed variation: \(draft.seedOffset)", value: $draft.seedOffset, in: 0...999)
                    if isChecking {
                        ProgressView("Checking winning routes…")
                    } else if let validation {
                        Text(validation.accepted ? "Winning route found."
                            : "No bot route found. This does not prove the level is impossible.")
                            .font(.footnote)
                    } else {
                        Text("Candidate has not been checked.").font(.footnote)
                    }
                    Button("Check winning routes") { checkCandidate() }
                        .disabled(isChecking)
                    Button("Re-roll seed") {
                        draft.seedOffset = (draft.seedOffset + Int.random(in: 1...999)) % 1_000
                    }
                    Text("Changes fish spawning and movement, plus uneven jellyfish layouts. Other tuning settings stay the same. Use Apply & Play to try it, or save a preset to keep this roll.")
                        .font(.footnote)
                }
                Section("Presets") {
                    Button("Load shipped settings") { draft = ArcadeTuning(level: world.levels[index]) }
                    if world == .jellyBloom && index < GameTuning.bloomReferenceLevels.count {
                        Button("Load original five-level reference") {
                            draft = ArcadeTuning(level: GameTuning.bloomReferenceLevels[index])
                        }
                    }
                    if world == .shallowReef && index < GameTuning.shallowReferenceLevels.count {
                        Button("Load original five-level reference") {
                            draft = ArcadeTuning(level: GameTuning.shallowReferenceLevels[index])
                        }
                    }
                    if world == .jellyBloom && index > 0 && index < GameTuning.bloomReferenceLevels.count {
                        Button("Load before-roaming experiment") {
                            draft = ArcadeTuning(level: GameTuning.bloomReferenceLevels[index])
                            draft.aiMinimum = 30
                            draft.aiMaximum = index == 1 ? 75 : (index == 4 ? 85 : 80)
                            draft.aiVertical = index == 1 ? 30 : (index == 4 ? 35 : 32)
                            draft.roam = false
                            draft.unevenJellies = false
                        }
                    }
                    TextField("Preset name", text: $presetName)
                    Button("Save preset") { store.savePreset(name: presetName, tuning: draft) }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(store.presets) { preset in
                        Button("Load \(preset.name)") { draft = preset.tuning }
                    }
                    Button("Remove override for this level") {
                        store.clear(world: world, index: index)
                        dismiss()
                        onPlay(world, index)
                    }
                }
            }
            .navigationTitle("Debug Tuning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply & Play") {
                        store.save(draft, world: world, index: index)
                        dismiss()
                        onPlay(world, index)
                    }
                }
            }
            .onChange(of: world) { _, _ in loadSelection() }
            .onChange(of: index) { _, _ in loadSelection() }
            .onChange(of: draft) { _, _ in clearValidation() }
            .onDisappear { validationTask?.cancel() }
        }
    }
    /// Plans off the main thread; the planner caches them, so Play starts instantly afterward.
    private func summarizePlans() async {
        plannerSummaries = [:]
        let variation = plannerVariation
        for spec in GameTuning.reefLabSpecs {
            let summary = await Task.detached(priority: .userInitiated) {
                MeetingPlannerSummary.text(MeetingPlanner.plan(spec, variation: variation))
            }.value
            guard !Task.isCancelled, variation == plannerVariation else { return }
            plannerSummaries[spec.name] = summary
        }
    }

    private func clearValidation() {
        validationTask?.cancel()
        validationTask = nil
        validation = nil
        isChecking = false
    }
    private func checkCandidate() {
        clearValidation()
        let tuning = draft.sanitized
        let selectedWorld = world, selectedIndex = index
        isChecking = true
        validationTask = Task { @MainActor in
            let report = await ArcadeCandidateValidation.check(world: selectedWorld, index: selectedIndex, tuning: tuning)
            guard !Task.isCancelled else { return }
            validation = report
            isChecking = false
        }
    }
    private func loadSelection() {
        clearValidation()
        index = min(max(0, index), world.levels.count - 1)
        draft = store.override(world, index) ?? ArcadeTuning(level: world.levels[index])
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(value.wrappedValue, specifier: "%.2f")")
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
}
#endif
