import SpriteKit
import SwiftUI

struct ContentView: View {
    #if DEBUG
    @StateObject private var progress = ArcadeProgress(defaults: ArcadePlaytest.defaults)
    #else
    @StateObject private var progress = ArcadeProgress()
    #endif
    @StateObject private var purchases = ArcadePurchases()
    @State private var analytics = ArcadeAnalytics()
    @State private var metricsLaunched = false
    @State private var selectedWorld: ArcadeWorld?
    @State private var scene: GameScene?
    /// The level last played in `selectedWorld`, so its map opens there; nil on first entry.
    @State private var returnedFrom: Int?
    /// A world whose tenth level was just beaten for the first time; its unlock screen shows back on the map.
    @State private var conquered: ArcadeWorld?
    @State private var celebrating: ArcadeWorld?
    /// The conquered screen is the unlock's offer (beating Shallow Reef without it), decided as it opens so a purchase
    /// made on it shows its thanks rather than switching screens.
    @State private var celebrationOffersUnlock = false
    /// The unlock's screen, featuring the world the player was trying to get into.
    @State private var offer: UnlockOffer?
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
                .transition(.opacity)
            } else if let world = selectedWorld {
                ArcadeLevelMap(world: world, progress: progress, unlocked: unlocked, returnedFrom: returnedFrom,
                               onBack: { selectedWorld = nil; returnedFrom = nil }, onPlay: { play(world, index: $0) })
            } else {
                ArcadeWorldMap(progress: progress, unlocked: unlocked, onSelect: { selectedWorld = $0; returnedFrom = nil },
                               onUnlock: { world in withAnimation { offer = UnlockOffer(featured: world) } })
            }
        }
        .overlay {
            if scene == nil, let world = celebrating {
                if celebrationOffersUnlock {
                    UnlockView(purchases: purchases, conquered: world, onClose: { withAnimation { celebrating = nil } })
                        .transition(.opacity)
                } else {
                    WorldConqueredView(world: world,
                        onDeepEnd: { celebrating = nil; play(world, index: ArcadeWorld.mainLevelCount) },
                        onLater: { celebrating = nil })
                        .transition(.opacity)
                }
            }
        }
        .overlay {
            if scene == nil, let offer {
                UnlockView(purchases: purchases, featured: offer.featured, onClose: { withAnimation { self.offer = nil } })
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            // Small, for players who've played before and reinstalled.
            if let scene, scene.isTutorial {
                Button("Skip") { scene.skipTutorial() }
                    .font(.custom("AvenirNext-DemiBold", size: 14)).foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black.opacity(0.25), in: Capsule())
                    .buttonStyle(.plain)
                    .padding(.leading, 24).padding(.top, 14)
                    .accessibilityLabel("Skip the tutorial")
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
                offer = nil
                selectedWorld = world
                celebrate(world)
            }
            .replayingTutorial { playTutorial() }
            .previewingUnlock {
                scene = nil
                withAnimation { offer = UnlockOffer(featured: nil) }
            }
        }
        #endif
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await warmUp() }
        .onChange(of: music, initial: true) { _, music in ArcadeAudio.shared.playMusic(music) }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            purchases.start()
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

    /// Shows a world's conquered screen. Without the unlock, beating Shallow Reef is the moment to show what it opens,
    /// its Deep End included.
    private func celebrate(_ world: ArcadeWorld) {
        celebrationOffersUnlock = ArcadeUnlock.needsUnlock(world, ArcadeWorld.mainLevelCount, unlocked: purchases.isUnlocked)
        withAnimation { celebrating = world }
    }

    /// The unlock is bought, or isn't on sale yet: nothing past the free levels is locked.
    private var unlocked: Bool { !ArcadeUnlock.isSelling || purchases.isUnlocked }

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
        // A new player starts with the tutorial, then lands on Shallow Reef.
        if progress.needsTutorial {
            playTutorial()
            return
        }
        // Players who beat a tenth level before its unlock screen existed see it once, on the world map.
        if let world = progress.unseenUnlock {
            try? await Task.sleep(for: .seconds(0.5))
            progress.sawUnlock(world)
            celebrate(world)
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

    /// The first-launch tutorial (`ArcadeTutorial`): seen once however it ends, then on to Shallow Reef's levels.
    private func playTutorial() {
        let game = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        game.analytics = analytics
        // Seen once it's finished, skipped or left; closing the app partway through plays it again next time.
        game.onTutorialFinished = { progress.sawTutorial() }
        game.onExit = {
            progress.sawTutorial()
            // A gentle fade to Shallow Reef's map, not a cut.
            withAnimation(.easeInOut(duration: 0.7)) {
                scene = nil
                selectedWorld = .shallowReef
                returnedFrom = nil
            }
        }
        scene = game
    }

    /// `seeded` (Debug, from the tuner) plays the world's original seeded level instead of its planned one.
    private func play(_ world: ArcadeWorld, index: Int, practice: Bool = false, seeded: Bool = false) {
        // Past the free levels: show what the unlock opens instead.
        var offersUnlock = !practice
        #if DEBUG
        offersUnlock = offersUnlock && ArcadePlaytest.selection == nil
        #endif
        if offersUnlock && ArcadeUnlock.needsUnlock(world, index, unlocked: purchases.isUnlocked) {
            withAnimation { offer = UnlockOffer(featured: world) }
            return
        }
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
        if offersUnlock {
            game.levelNeedsUnlock = { [purchases] index in
                ArcadeUnlock.needsUnlock(world, index, unlocked: purchases.isUnlocked)
            }
        }
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
            if game?.leftForUnlock == true {
                // Next level was past the free ones: the map waits on it, under what the unlock opens.
                returnedFrom = game.map { $0.currentLevelIndex + 1 }
                withAnimation { offer = UnlockOffer(featured: world) }
            }
            if let world = conquered {
                conquered = nil
                // Only a real unlock is remembered; the tuner's preview leaves progress alone.
                progress.sawUnlock(world)
                celebrate(world)
            }
        }
        scene = game
    }
}

/// What the unlock's screen was opened for.
private struct UnlockOffer {
    /// The world the player was trying to get into, if any.
    var featured: ArcadeWorld?
}
