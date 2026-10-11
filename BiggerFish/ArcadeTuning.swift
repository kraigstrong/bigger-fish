#if DEBUG
import Foundation
import SwiftUI

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

struct ArcadeTuningPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var plannerVariation = 0
    @State private var plannerSummaries: [String: String] = [:]
    @State private var resetWorld: ArcadeWorld = .shallowReef
    @State private var confirmsReset = false
    let onPlanner: (MeetingSpec, Int) -> Void
    let onResetProgress: (ArcadeWorld) -> Void
    /// Shows a world's "conquered" unlock screen without touching progress.
    var onPreviewConquered: (ArcadeWorld) -> Void = { _ in }
    var onReplayTutorial: () -> Void = {}
    var onReplayTutorialWall: () -> Void = {}
    var onPreviewUnlock: () -> Void = {}

    init(onPlanner: @escaping (MeetingSpec, Int) -> Void, onResetProgress: @escaping (ArcadeWorld) -> Void) {
        self.onPlanner = onPlanner
        self.onResetProgress = onResetProgress
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Players") {
                    Text("Start a world over from level 1 for a new player, for A/B testing. Its iCloud copy is reset too, but another device on this Apple ID that still has its clears brings them back.")
                        .font(.footnote)
                    Picker("World", selection: $resetWorld) {
                        ForEach(ArcadeWorld.mapWorlds) { Text($0.title).tag($0) }
                    }
                    Button("Reset \(resetWorld.title) progress", role: .destructive) { confirmsReset = true }
                        .confirmationDialog("Clear every \(resetWorld.title) clear and best time on this device and in iCloud?",
                                            isPresented: $confirmsReset, titleVisibility: .visible) {
                            Button("Reset \(resetWorld.title)", role: .destructive) { onResetProgress(resetWorld) }
                        }
                    Button("Preview \(resetWorld.title)'s conquered screen") {
                        dismiss()
                        onPreviewConquered(resetWorld)
                    }
                    Button("Replay the first-launch tutorial") {
                        dismiss()
                        onReplayTutorial()
                    }
                    Button("Play the tutorial's wall (its last beat)") {
                        dismiss()
                        onReplayTutorialWall()
                    }
                    Button("Preview the unlock screen") {
                        dismiss()
                        onPreviewUnlock()
                    }
                }
                Section("\(ArcadeWorld.shallowReef.title) variations") {
                    Text("Other layouts of the same \(ArcadeWorld.shallowReef.title) settings: every fish swims freely but is timed to cross your path at a planned height. Practice runs only.")
                        .font(.footnote)
                    Stepper("Variation: \(plannerVariation)", value: $plannerVariation, in: 0...99)
                    // In play order: Shallow Reef's level numbers, not Reef Lab's (see `shallowReefOrder`).
                    ForEach(Array(GameTuning.shallowReefOrder.map { GameTuning.reefLabSpecs[$0] }.enumerated()), id: \.offset) { index, spec in
                        Button("Play \(ArcadeWorld.shallowReef.title) level \(index + 1)") {
                            dismiss()
                            onPlanner(spec, plannerVariation)
                        }
                        Text(plannerSummaries[spec.name] ?? "Planning…").font(.footnote).monospacedDigit()
                    }
                }
                .task(id: plannerVariation) { await summarizePlans() }
            }
            .navigationTitle("Debug Tuning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
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
}

extension ArcadeTuningPanel {
    func previewingConquered(_ action: @escaping (ArcadeWorld) -> Void) -> Self {
        var panel = self
        panel.onPreviewConquered = action
        return panel
    }

    func replayingTutorial(_ action: @escaping () -> Void) -> Self {
        var panel = self
        panel.onReplayTutorial = action
        return panel
    }

    func replayingTutorialWall(_ action: @escaping () -> Void) -> Self {
        var panel = self
        panel.onReplayTutorialWall = action
        return panel
    }

    func previewingUnlock(_ action: @escaping () -> Void) -> Self {
        var panel = self
        panel.onPreviewUnlock = action
        return panel
    }
}
#endif
