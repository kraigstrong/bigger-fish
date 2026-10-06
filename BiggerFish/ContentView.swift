import SpriteKit
import SwiftUI

struct ContentView: View {
    #if DEBUG
    @StateObject private var progress = ArcadeProgress(defaults: ArcadePlaytest.defaults)
    #else
    @StateObject private var progress = ArcadeProgress()
    #endif
    @State private var analytics = ArcadeAnalytics()
    @State private var metricsLaunched = false
    @State private var selectedWorld: ArcadeWorld?
    @State private var scene: GameScene?
    #if DEBUG
    @StateObject private var tuningStore = ArcadeTuningStore()
    @State private var showsTuning = false
    #endif

    var body: some View {
        Group {
            if let scene {
                GeometryReader { geometry in
                    let fitted = GameTuning.fittedPlayfieldSize(in: geometry.size)
                    ZStack {
                        OceanBackdrop(bloom: scene.arcadeWorld.hasJellies)
                        SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                            .id(ObjectIdentifier(scene))
                            .frame(width: fitted.width, height: fitted.height)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
            } else if let world = selectedWorld {
                ArcadeLevelMap(world: world, progress: progress,
                               onBack: { selectedWorld = nil }, onPlay: { play(world, index: $0) })
            } else {
                ArcadeWorldMap(progress: progress, onSelect: { selectedWorld = $0 })
            }
        }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            Button("Tuning", systemImage: "slider.horizontal.3") {
                scene?.debugPauseForTuning()
                showsTuning = true
            }
            .font(.caption.bold()).buttonStyle(.borderedProminent)
            .padding(.trailing, 12).padding(.bottom, 4)
        }
        .sheet(isPresented: $showsTuning) {
            // Planned levels ignore the tuner's seeded settings; its Players and variations sections still apply.
            let current = scene?.arcadeWorld ?? selectedWorld ?? .jellyBloom
            let campaign = ArcadeWorld.campaign.contains(current)
            ArcadeTuningPanel(store: tuningStore, world: campaign ? current : .shallowReef,
                              index: campaign ? scene?.debugLevelIndex ?? 1 : 0, onPlanner: playPlanner,
                              onResetProgress: { progress.reset($0) }) { world, index in
                selectedWorld = world
                play(world, index: index, practice: true, seeded: true)
            }
        }
        #endif
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if !metricsLaunched { analytics.launched(); analytics.flush(); metricsLaunched = true }
            #if DEBUG
            if scene == nil, let world = ArcadePlaytest.mapSelection {
                selectedWorld = world
            }
            if scene == nil && selectedWorld == nil, let selection = ArcadePlaytest.selection {
                selectedWorld = selection.world
                play(selection.world, index: selection.index)
            }
            if scene == nil, let planner = ArcadePlaytest.planner {
                playPlanner(planner.spec, variation: planner.variation)
            }
            #endif
        }
    }

    #if DEBUG
    /// A planned test level, always a practice run: no clears, progress, or analytics.
    private func playPlanner(_ spec: MeetingSpec, variation: Int) {
        let game = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        game.debugUsePlanner(spec, variation: variation)
        game.debugPracticeRun = true
        game.onExit = { [weak game] in game?.exitMetrics(); scene = nil }
        selectedWorld = .shallowReef
        scene = game
    }
    #endif

    /// `seeded` (Debug, from the tuner) plays the world's original seeded level instead of its planned one.
    private func play(_ world: ArcadeWorld, index: Int, practice: Bool = false, seeded: Bool = false) {
        #if DEBUG
        guard practice || progress.isOpen(world, index) || ArcadePlaytest.selection != nil else { return }
        #else
        guard progress.isOpen(world, index) else { return }
        #endif
        let game = GameScene(world: world, levelIndex: index,
                             showsJellyLesson: !progress.save.hasSeenJellyLesson, seeded: seeded)
        #if DEBUG
        game.debugPracticeRun = practice
        #endif
        game.analytics = analytics
        game.metricsHasCleared = { index in progress.isCleared(world, index) }
        game.onClear = { [weak game] index, seconds in
            #if DEBUG
            guard let game, !game.debugPracticeRun, !game.debugHasTuningOverride else { return }
            #endif
            progress.clear(world, index, seconds: seconds)
        }
        game.onJellyLesson = { [weak game] in
            #if DEBUG
            guard let game, !game.debugPracticeRun, !game.debugHasTuningOverride else { return }
            #endif
            progress.sawJellyLesson()
        }
        game.onExit = { [weak game] in game?.exitMetrics(); scene = nil }
        scene = game
    }
}
