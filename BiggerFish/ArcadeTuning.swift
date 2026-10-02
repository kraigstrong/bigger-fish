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
        return result
    }

    func applying(to base: Level) -> Level {
        let value = sanitized
        var result = Level(spawnGroups: value.groups.map { ($0.count, CGFloat($0.minimum)...CGFloat($0.maximum)) },
            aiSpeedRange: CGFloat(value.aiMinimum)...CGFloat(value.aiMaximum), aiVerticalSpeed: CGFloat(value.aiVertical),
            screenCrossSeconds: CGFloat(value.crossingSeconds), absorptionEfficiency: CGFloat(value.absorption))
        if let layout = base.jellies, value.jellyCount > 0 {
            result.jellies = JellyLayout(count: value.jellyCount, radius: CGFloat(value.jellyRadius),
                tentacleLength: CGFloat(value.tentacleLength), sway: layout.sway, night: layout.night,
                maintainsFloorLane: true, heights: layout.heights)
        }
        result.aiCanEat = base.aiCanEat
        result.requiredMeals = base.requiredMeals
        result.bounceFoodPockets = base.bounceFoodPockets && result.jellies != nil
        result.sidePocketExperiment = base.sidePocketExperiment && value.jellyCount > GameTuning.bloomSidePocketJellyIndex
        result.roamingFoodChain = value.roam
        result.ecosystemSeedOffset = UInt64(value.seedOffset)
        result.compactAISpeedScale = base.compactAISpeedScale
        result.mediumAISpeedMultiplier = base.mediumAISpeedMultiplier
        return result
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

    init(defaults: UserDefaults = ArcadePlaytest.defaults) {
        self.defaults = defaults
        presets = defaults.data(forKey: Self.presetsKey).flatMap { try? JSONDecoder().decode([ArcadeTuningPreset].self, from: $0) } ?? []
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
    let onPlay: (ArcadeWorld, Int) -> Void

    init(store: ArcadeTuningStore, world: ArcadeWorld, index: Int, onPlay: @escaping (ArcadeWorld, Int) -> Void) {
        self.store = store
        _world = State(initialValue: world)
        _index = State(initialValue: index)
        _draft = State(initialValue: store.override(world, index) ?? ArcadeTuning(level: world.levels[index]))
        self.onPlay = onPlay
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("World", selection: $world) {
                        ForEach(ArcadeWorld.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Level", selection: $index) {
                        ForEach(0..<5) { Text("Level \($0 + 1)").tag($0) }
                    }.pickerStyle(.segmented)
                    Text("Apply starts a fresh practice run. Practice runs don't change campaign progress. Closing leaves your current run paused.")
                        .font(.footnote)
                }
                Section("Fish — size is relative to your starting radius") {
                    ForEach(draft.groups.indices, id: \.self) { i in
                        VStack(alignment: .leading) {
                            Stepper("Group \(i + 1): \(draft.groups[i].count) fish", value: $draft.groups[i].count, in: 0...12)
                            slider("Group \(i + 1) minimum size", value: $draft.groups[i].minimum, range: 0.25...3, step: 0.05)
                            slider("Group \(i + 1) maximum size", value: $draft.groups[i].maximum, range: 0.25...3, step: 0.05)
                        }
                    }
                    slider("Growth per meal", value: $draft.absorption, range: 0.5...1, step: 0.01)
                }
                Section("Movement and competition") {
                    slider("AI minimum speed", value: $draft.aiMinimum, range: 10...200, step: 5)
                    slider("AI maximum speed", value: $draft.aiMaximum, range: 10...200, step: 5)
                    slider("AI vertical speed", value: $draft.aiVertical, range: 10...120, step: 5)
                    slider("Seconds across screen", value: $draft.crossingSeconds, range: 2...4, step: 0.1)
                    if world == .jellyBloom {
                        Toggle("Fish leave opening pockets", isOn: $draft.roam)
                        slider("Pocket release seconds", value: $draft.releaseSeconds, range: 0...12, step: 0.5)
                    }
                }
                if world == .jellyBloom {
                    Section("Jellyfish") {
                        Stepper("Jellyfish: \(draft.jellyCount)", value: $draft.jellyCount, in: 0...7)
                        Toggle("Uneven layout", isOn: $draft.unevenJellies)
                        slider("Layout variation", value: $draft.layoutVariation, range: 0...1, step: 0.1)
                        slider("Bell radius", value: $draft.jellyRadius, range: 30...55, step: 1)
                        slider("Tentacle length", value: $draft.tentacleLength, range: 40...100, step: 5)
                        slider("Bounce strength", value: $draft.bounceSpeed, range: 300...600, step: 10)
                        Stepper("Seed variation: \(draft.seedOffset)", value: $draft.seedOffset, in: 0...999)
                    }
                }
                Section("Presets") {
                    Button("Load shipped settings") { draft = ArcadeTuning(level: world.levels[index]) }
                    if world == .jellyBloom && index > 0 {
                        Button("Load before-roaming experiment") {
                            draft = ArcadeTuning(level: world.levels[index])
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
        }
    }
    private func loadSelection() { draft = store.override(world, index) ?? ArcadeTuning(level: world.levels[index]) }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(value.wrappedValue, specifier: "%.2f")")
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }
}
#endif
