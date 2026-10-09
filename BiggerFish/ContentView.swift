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
    /// The level last played in `selectedWorld`, so its map opens there; nil on first entry.
    @State private var returnedFrom: Int?
    /// A world whose tenth level was just beaten for the first time; its unlock screen shows back on the map.
    @State private var conquered: ArcadeWorld?
    @State private var celebrating: ArcadeWorld?
    /// The loading screen shows until both worlds' levels are decoded.
    @State private var loaded = false
    #if DEBUG
    @StateObject private var tuningStore = ArcadeTuningStore()
    @State private var showsTuning = false
    #endif

    var body: some View {
        Group {
            if !loaded {
                LaunchView().transition(.opacity)
            } else if let scene {
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
                ArcadeLevelMap(world: world, progress: progress, returnedFrom: returnedFrom,
                               onBack: { selectedWorld = nil; returnedFrom = nil }, onPlay: { play(world, index: $0) })
            } else {
                ArcadeWorldMap(progress: progress, onSelect: { selectedWorld = $0; returnedFrom = nil })
            }
        }
        .overlay {
            if scene == nil, let world = celebrating {
                WorldConqueredView(world: world,
                    onNextWorld: { next in celebrating = nil; selectedWorld = next; returnedFrom = nil },
                    onDeepEnd: { celebrating = nil; play(world, index: ArcadeWorld.mainLevelCount) },
                    onLater: { celebrating = nil })
                    .transition(.opacity)
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
            let campaign = ArcadeWorld.campaign.contains(current) && current.hasSeededOriginal
            // Bonus levels have no seeded original to tune; the tuner opens on the last one.
            let seededIndex = min(scene?.debugLevelIndex ?? 1, current.seededLevels.count - 1)
            ArcadeTuningPanel(store: tuningStore, world: campaign ? current : .shallowReef,
                              index: campaign ? seededIndex : 0, onPlanner: playPlanner,
                              onResetProgress: { progress.reset($0) }) { world, index in
                selectedWorld = world
                play(world, index: index, practice: true, seeded: true)
            }
            .previewingConquered { world in
                scene = nil
                selectedWorld = world
                withAnimation { celebrating = world }
            }
        }
        #endif
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await warmUp() }
        .onChange(of: music, initial: true) { _, music in ArcadeAudio.shared.playMusic(music) }
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

    /// Menu music under the maps, game music under a level, quiet while loading.
    private var music: ArcadeAudio.Music? {
        guard loaded else { return nil }
        return scene == nil ? .menu : .game
    }

    /// Readies every world's levels off the main thread (Kelp Forest's are planned, not decoded), keeping the
    /// loading screen up at least briefly so it doesn't flash.
    private func warmUp() async {
        guard !loaded else { return }
        let started = Date()
        await Task.detached(priority: .userInitiated) {
            _ = GameTuning.shallowReefLevels.count + GameTuning.jellyLabLevels.count + GameTuning.kelpLevels.count
            #if DEBUG
            _ = GameTuning.midnightLevels.count
            #endif
        }.value
        let remaining = GameTuning.launchMinimumSeconds - Date().timeIntervalSince(started)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        withAnimation(.easeOut(duration: 0.35)) { loaded = true }
        // Players who beat a tenth level before its unlock screen existed see it once, on the world map.
        if let world = progress.unseenUnlock {
            try? await Task.sleep(for: .seconds(0.5))
            progress.sawUnlock(world)
            withAnimation { celebrating = world }
        }
    }

    #if DEBUG
    /// A planned test level, always a practice run: no clears, progress, or analytics.
    private func playPlanner(_ spec: MeetingSpec, variation: Int) {
        let game = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        game.debugUsePlanner(spec, variation: variation)
        game.debugPracticeRun = true
        game.onExit = { [weak game] in
            game?.exitMetrics()
            returnedFrom = game?.currentLevelIndex
            scene = nil
        }
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
            guard let scene = game, !scene.debugPracticeRun, !scene.debugHasTuningOverride else { return }
            #endif
            if index == ArcadeWorld.mainLevelCount - 1 && !progress.isCleared(world, index) {
                // Straight to the conquered screen, with no result card first.
                conquered = world
                game?.leavesForConqueredScreen = true
            }
            progress.clear(world, index, seconds: seconds)
        }
        game.onJellyLesson = { [weak game] in
            #if DEBUG
            guard let game, !game.debugPracticeRun, !game.debugHasTuningOverride else { return }
            #endif
            progress.sawJellyLesson()
        }
        game.onExit = { [weak game] in
            game?.exitMetrics()
            returnedFrom = game?.currentLevelIndex
            scene = nil
            if let world = conquered {
                conquered = nil
                // Only a real unlock is remembered; the tuner's preview leaves progress alone.
                progress.sawUnlock(world)
                withAnimation { celebrating = world }
            }
        }
        scene = game
    }
}
