import SpriteKit
import StoreKit
import SwiftUI

struct ContentView: View {
    #if DEBUG
    @StateObject private var progress = ArcadeProgress(defaults: ArcadePlaytest.defaults)
    #else
    @StateObject private var progress = ArcadeProgress()
    #endif
    @StateObject private var purchases = ArcadePurchases()
    /// The day's free Open Water runs on this device, without the unlock.
    @StateObject private var openWaterRuns = OpenWaterRuns()
    @State private var analytics = ArcadeAnalytics()
    @State private var metricsLaunched = false
    /// Adventure's world map, from the home screen; without it (and no world chosen), the home screen.
    @State private var showsWorlds = false
    @State private var selectedWorld: ArcadeWorld?
    @State private var scene: GameScene?
    /// The level's pause menu is up (`GameScene.onPause`).
    @State private var scenePaused = false
    /// The world the level on screen is in, for the water around the playfield: the Open Water moves through them.
    @State private var sceneWorld: ArcadeWorld?
    /// The level last played in `selectedWorld`, so its map opens there; nil on first entry.
    @State private var returnedFrom: Int?
    /// A level just cleared for the first time, when coming back to its map: your fish swims on to the next.
    @State private var advancedFrom: Int?
    /// A world whose tenth level was just beaten for the first time; its unlock screen shows back on the map.
    @State private var conquered: ArcadeWorld?
    @State private var celebrating: ArcadeWorld?
    /// The conquered screen is the unlock's offer (beating Shallow Reef without it), decided as it opens so a purchase
    /// made on it shows its thanks rather than switching screens.
    @State private var celebrationOffer: UnlockOffer?
    /// Asking for an App Store review after a high point (see `ArcadeReview`), and whether the last level played was won.
    @State private var review = ArcadeReview()
    @State private var lastPlayWon = true
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    /// The unlock's screen, featuring the world the player was trying to get into.
    @State private var offer: UnlockOffer?
    /// Settings, from the gear on the home screen.
    @State private var showsSettings = false
    /// The credits game, from Settings (`CreditsScene`). Settings stays open underneath, so leaving goes back to it.
    @State private var credits: CreditsScene?
    /// The loading screen shows until every world's levels are ready.
    @State private var loaded = false
    /// `ScreenFit.menuScale` for the window: 1 on a phone.
    @State private var menuScale: CGFloat = 1
    #if DEBUG
    @State private var showsTuning = false
    #endif
    /// An Open Water run's first level is being planned (`playOpenWater`).
    @State private var startingOpenWater = false
    /// The pearl shop, from the home screen or an Open Water run's result card (which waits under it).
    @State private var showsShop = false
    /// The pearl shop's visit while it's open, for the stats (`ArcadeAnalytics.shopVisited`).
    @State private var shopVisit: ArcadeAnalytics.ShopVisit?
    /// The Shop's tutorial over it: the first time it's opened, or from Settings' How to play.
    @State private var showsShopHints = false

    var body: some View {
        Group {
            if !loaded {
                LaunchView().transition(.opacity)
            } else if let credits {
                CreditsView(scene: credits).transition(.opacity)
            } else if let scene {
                PlayfieldScreen(scene: scene, water: .of(sceneWorld ?? scene.arcadeWorld), paused: scenePaused)
                    .transition(.opacity)
            } else if let world = selectedWorld {
                ArcadeLevelMap(world: world, progress: progress, unlocked: unlocked, returnedFrom: returnedFrom,
                               advancedFrom: advancedFrom,
                               onBack: { selectedWorld = nil; returnedFrom = nil; advancedFrom = nil; showsWorlds = true },
                               onPlay: { play(world, index: $0) })
            } else if showsWorlds {
                ArcadeWorldMap(progress: progress, unlocked: unlocked, onSelect: { selectedWorld = $0; returnedFrom = nil },
                               onUnlock: { world in
                                   withAnimation { offer = UnlockOffer(featured: world, source: world == nil ? .unlockAll : .lockedWorld) }
                               },
                               onBack: { showsWorlds = false })
            } else {
                ArcadeHome(progress: progress, unlocked: unlocked,
                           openWaterRunsLeft: limitsOpenWater ? openWaterRuns.left() : nil,
                           onAdventure: openAdventure, onOpenWater: { playOpenWater() }, onShop: { openShop(from: .map) },
                           onUnlock: { withAnimation { offer = UnlockOffer(featured: nil, source: .unlockAll, bothModes: true) } },
                           onSettings: { withAnimation { showsSettings = true } })
            }
        }
        .overlay {
            if scene == nil && credits == nil && showsSettings {
                SettingsView(purchases: purchases, analytics: analytics,
                             onHowToPlay: { course in
                                 showsSettings = false
                                 if course == .shop { openShop(from: .map, hints: true) } else { playTutorial(course) }
                             },
                             onPlayCredits: playCredits,
                             onClose: { withAnimation { showsSettings = false } })
                    .transition(.opacity)
            }
        }
        .overlay {
            if scene == nil, let world = celebrating {
                if let celebrationOffer {
                    UnlockView(purchases: purchases, conquered: world, source: celebrationOffer.source, analytics: analytics,
                               onClose: { withAnimation { celebrating = nil } })
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
                UnlockView(purchases: purchases, featured: offer.featured, source: offer.source, bothModes: offer.bothModes,
                           analytics: analytics, onClose: { withAnimation { self.offer = nil } })
                    .transition(.opacity)
            }
        }
        .overlay {
            if showsShop && credits == nil {
                PearlShopView(progress: progress, showsHints: showsShopHints, onBought: { shopVisit?.add($0.id) },
                              onHintsSeen: {
                                  progress.sawTutorial(.shop)
                                  withAnimation(.easeOut(duration: 0.2)) { showsShopHints = false }
                              },
                              onClose: closeShop)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            // Small, for players who've played before and reinstalled.
            if let scene, scene.isTutorial {
                SkipButton(accessibilityLabel: "Skip the tutorial") { scene.skipTutorial() }
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
            .opacity(StoreCapture.moment == nil && StoreFootage.request == nil && !StoreFootage.shopTour && ArcadePlaytest.screen == nil
                     && credits == nil ? 1 : 0)
        }
        .sheet(isPresented: $showsTuning) {
            ArcadeTuningPanel(onPlanner: playPlanner, onResetProgress: { progress.reset($0) })
            .previewingConquered { world in
                scene = nil
                offer = nil
                selectedWorld = world
                celebrate(world, preview: true)
            }
            .replayingTutorial { course in
                scene = nil
                if course == .shop { openShop(from: .map, hints: true) } else { playTutorial(course) }
            }
            .replayingTutorialWall { playTutorial(.adventure, from: .eatEnough) }
            .previewingUnlock {
                scene = nil
                withAnimation { offer = UnlockOffer(featured: nil, source: nil) }
            }
        }
        .onChange(of: hitchScreen, initial: true) { _, screen in HitchLog.shared?.show(screen) }
        #endif
        .onChange(of: quietOnMap) { _, quiet in if quiet { askForReviewIfDue() } }
        // Bought or put on in the shop over a result card: worn from the next try.
        .onChange(of: progress.look) { _, look in scene?.playerLook = look }
        // Taken in a run, or spent in the shop over its result card: the card's Shop button shows what's left.
        .onChange(of: progress.pearls) { _, pearls in scene?.pearlsToSpend = pearls }
        .onChange(of: offer == nil) { _, closed in
            guard !closed else { return }
            review.sawOffer()
            if let source = offer?.source { analytics.offerShown(source) }
        }
        // Each run says whether it was played with the unlock, while the unlock is on sale.
        .onChange(of: purchases.isUnlocked, initial: true) { _, owned in analytics.hasUnlock = ArcadeUnlock.isSelling ? owned : nil }
        // Runs say whether your fish wore any look, and a launch's first reports which.
        .onChange(of: progress.look, initial: true) { _, look in analytics.wearing = look.ids.values.sorted() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            // The shop's visit so far goes with everything else; coming back to it open starts another.
            if let visit = shopVisit {
                analytics.shopVisited(visit)
                shopVisit = ArcadeAnalytics.ShopVisit(source: visit.source, wallet: progress.pearls, hadBought: progress.hasBoughtALook)
            }
            analytics.backgrounded()
        }
        .onChange(of: scene == nil) { _, onMap in if onMap { reportEarnedLooks() } }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // Bigger on an iPad: the Skip buttons over the scenes (each menu screen sizes itself, `ScreenScaled`).
        .environment(\.menuScale, menuScale)
        .onGeometryChange(for: CGFloat.self) { ScreenFit.menuScale(for: $0.size) } action: { menuScale = $0 }
        .task { await warmUp() }
        .onChange(of: music, initial: true) { _, music in ArcadeAudio.shared.playMusic(music) }
        .onAppear {
            purchases.start()
            if !metricsLaunched {
                if analytics.enabled { ArcadeURLMetricSender.warmUp() }
                analytics.launched()
                reportEarnedLooks()
                analytics.flush(); metricsLaunched = true
            }
            #if DEBUG
            StoreCapture.begin()
            StoreFootage.begin()
            // App Store captures and footage open on the world map, as 1.0's did: never the home screen.
            if StoreCapture.moment != nil || StoreFootage.request != nil { showsWorlds = true }
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
            if scene == nil, let seed = ArcadePlaytest.openWaterSeed { playOpenWater(seed: seed, from: ArcadePlaytest.openWaterStart) }
            if StoreFootage.shopTour { openShop(from: .map) }
            if let screen = ArcadePlaytest.screen { open(screen) }
            #endif
        }
    }

    #if DEBUG
    /// A screen opened at launch to check its layout (`ArcadePlaytest.screen`).
    private func open(_ screen: ArcadePlaytest.Screen) {
        ArcadePlaytest.captureScreen()
        switch screen {
        case .home, .newPlayer: break
        case .worlds: showsWorlds = true
        case .settings: showsSettings = true
        case .unlock: offer = UnlockOffer(featured: .jellyBloom, source: nil)
        case .unlockAll: offer = UnlockOffer(featured: nil, source: nil, bothModes: true)
        case .conquered:
            selectedWorld = .shallowReef
            celebrate(.shallowReef, preview: true)
        case .credits:
            showsSettings = true
            playCredits()
        case .tutorial: playTutorial(.adventure)
        case .openWaterTutorial: playTutorial(.openWater)
        case .shop: openShop(from: .map)
        case .shopHints: openShop(from: .map, hints: true)
        case .pause:
            guard let scene else { return }
            Task { @MainActor in
                while scene.view == nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(0.5))
                scene.debugStart()
                scene.debugPauseForTuning()
            }
        }
    }
    #endif

    /// Shows a world's conquered screen. Without the unlock, beating Shallow Reef is the moment to show what it opens,
    /// its Deep End included. `preview` (Xcode builds, from the tuner) shows it without counting it.
    private func celebrate(_ world: ArcadeWorld, preview: Bool = false) {
        let offersUnlock = ArcadeUnlock.needsUnlock(world, ArcadeWorld.mainLevelCount, unlocked: purchases.isUnlocked)
        celebrationOffer = offersUnlock ? UnlockOffer(featured: nil, source: preview ? nil : .conquered) : nil
        if offersUnlock { review.sawOffer() }
        if let source = celebrationOffer?.source { analytics.offerShown(source) }
        withAnimation { celebrating = world }
    }

    /// On the home screen or a map with nothing else on screen (no unlock, conquered, or Settings screen), after a win, with the app in front: the moment to ask for a review, if
    /// one is due. (In the background or under Notification Center, a request may show nothing yet use up an ask.)
    private var quietOnMap: Bool {
        loaded && scenePhase == .active && scene == nil && celebrating == nil && offer == nil && !showsSettings && lastPlayWon
    }

    private func askForReviewIfDue() {
        guard quietOnMap, review.shouldRequest(channel: ArcadeAnalytics.channel) else { return }
        Task {
            try? await Task.sleep(for: .seconds(GameTuning.reviewRequestDelay))
            // Still on the map, with nothing come up meanwhile.
            guard quietOnMap, review.shouldRequest(channel: ArcadeAnalytics.channel) else { return }
            review.didRequest()
            requestReview()
        }
    }

    #if DEBUG
    /// The screen on top, for the hitch log (`HitchLog`). A level or the credits, while up, says more about itself.
    private var hitchScreen: HitchContext {
        if !loaded { return HitchContext(.launch) }
        if credits != nil { return HitchContext(.credits) }
        if let scene { return HitchContext(scene.isTutorial ? .tutorial : .level) }
        if showsTuning { return HitchContext(.tuning) }
        if let offer { return HitchContext(.unlock, detail: offer.featured?.rawValue ?? "") }
        if let celebrating { return HitchContext(celebrationOffer == nil ? .conquered : .unlock, detail: celebrating.rawValue) }
        if showsSettings { return HitchContext(.settings) }
        if let selectedWorld { return HitchContext(.levelMap, detail: selectedWorld.rawValue) }
        return HitchContext(showsWorlds ? .worldMap : .home)
    }
    #endif

    /// The unlock is bought, or isn't on sale yet: nothing past the free levels is locked.
    private var unlocked: Bool { !ArcadeUnlock.isSelling || purchases.isUnlocked }
    /// The Open Water has its free runs a day (`OpenWaterRuns`).
    private var limitsOpenWater: Bool { ArcadeUnlock.limitsOpenWater(unlocked: purchases.isUnlocked) }

    /// Menu music under the maps, game music under a level, the credits' own calm pick under the credits, quiet while
    /// loading.
    private var music: ArcadeAudio.Music? {
        guard loaded else { return nil }
        if credits != nil { return GameTuning.creditsMusic }
        return scene == nil ? .menu : .game
    }

    /// Readies every world's levels off the main thread (Kelp Forest's are planned, not decoded), keeping the
    /// loading screen up at least briefly so it doesn't flash.
    private func warmUp() async {
        guard !loaded else { return }
        let started = Date()
        await Task.detached(priority: .userInitiated) {
            _ = GameTuning.shallowReefLevels.count + GameTuning.jellyLabLevels.count + GameTuning.kelpLevels.count
                + GameTuning.sunsetLevels.count + GameTuning.midnightLevels.count
        }.value
        let remaining = GameTuning.launchMinimumSeconds - Date().timeIntervalSince(started)
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        withAnimation(.easeOut(duration: 0.35)) { loaded = true }
        #if DEBUG
        // The prototypes plan their levels in code; behind the map, so a level opens at once.
        Task.detached(priority: .utility) { _ = ArcadeWorld.prototypes.map(\.levels.count) }
        #endif
        // A new player starts on the home screen: each way to play has its tutorial the first time it's opened.
        // Players who beat a tenth level before its unlock screen existed see it once, over the home screen. It's only
        // counted as seen if it shows: someone who taps into a level in the moment before keeps it for next time.
        if let world = progress.unseenUnlock {
            try? await Task.sleep(for: .seconds(0.5))
            guard scene == nil else { return }
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
        show(game)
    }
    #endif

    /// The Open Water, the endless run (`OpenWater`): no campaign progress, but its runs are reported their own way
    /// (`ArcadeAnalytics.startOpenWater`).
    /// Its first level is planned off the main thread first (planning one takes a moment); leaving goes back to the
    /// home screen. The first time, its tutorial plays while it's planned, then the run starts.
    private func playOpenWater(seed: UInt64 = .random(in: 1...UInt64(UInt32.max)), from start: Int = 0) {
        guard !startingOpenWater else { return }
        // The day's free runs used up: what the unlock opens, and when more come.
        if limitsOpenWater && openWaterRuns.left() == 0 {
            withAnimation { offer = UnlockOffer(featured: nil, source: .openWaterLimit) }
            return
        }
        let planning = Task.detached(priority: .userInitiated) {
            let started = DispatchTime.now()
            let plan = OpenWater.plan(start, seed: seed)
            return (plan, Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9)
        }
        var tutorialFirst = progress.needsTutorial(.openWater)
        #if DEBUG
        tutorialFirst = tutorialFirst && ArcadePlaytest.openWaterSeed == nil
        #endif
        if tutorialFirst {
            playTutorial(.openWater) {
                Task {
                    let (plan, seconds) = await planning.value
                    withAnimation(.easeInOut(duration: 0.7)) { showOpenWater(seed: seed, from: start, plan: plan, seconds: seconds) }
                }
            }
            return
        }
        startingOpenWater = true
        Task {
            let (plan, seconds) = await planning.value
            startingOpenWater = false
            guard scene == nil else { return }
            showOpenWater(seed: seed, from: start, plan: plan, seconds: seconds)
        }
    }

    /// An Open Water run, its first level planned.
    private func showOpenWater(seed: UInt64, from start: Int, plan: MeetingPlan, seconds: Double) {
        let game = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        game.startOpenWater(seed: seed, firstLevel: plan, from: start, planSeconds: seconds)
        #if DEBUG
        StoreFootage.attach(game)
        #endif
        game.analytics = analytics
        // Each pearl's kept as it's taken, however the run ends.
        game.onPearl = { progress.earnPearls(1) }
        game.onShop = { openShop(from: .runCard) }
        game.pearlsToSpend = progress.pearls
        game.openWaterBest = progress.openWaterBest
        game.onOpenWaterRun = { progress.recordOpenWaterRun(fish: $0, furthest: $1) }
        game.openWaterRunsLeft = { limitsOpenWater ? openWaterRuns.left() : nil }
        game.onOpenWaterRunCounted = { if limitsOpenWater { openWaterRuns.use() } }
        game.onExit = { [weak game] in
            game?.exitMetrics()
            scene = nil
            if game?.leftForUnlock == true { withAnimation { offer = UnlockOffer(featured: nil, source: .openWaterLimit) } }
        }
        show(game)
    }

    /// Adventure, from the home screen: the world map, your fish over the world you're on. (Kraig, 2026-10-26, after
    /// it first opened that world's levels: "I think I'd want to see the world map".) The first time, its tutorial
    /// plays first, then fades to the map.
    private func openAdventure() {
        guard !progress.needsTutorial(.adventure) else {
            playTutorial(.adventure) { withAnimation(.easeInOut(duration: 0.7)) { openAdventure() } }
            return
        }
        scene = nil
        selectedWorld = nil
        returnedFrom = nil
        advancedFrom = nil
        showsWorlds = true
    }

    /// Opens the pearl shop, from the home screen or an Open Water run's card: a visit begins. `hints`: the Shop's
    /// tutorial over it; without it, only the first time.
    private func openShop(from source: ArcadeAnalytics.ShopSource, hints: Bool? = nil) {
        shopVisit = ArcadeAnalytics.ShopVisit(source: source, wallet: progress.pearls, hadBought: progress.hasBoughtALook)
        showsShopHints = hints ?? progress.needsTutorial(.shop)
        withAnimation { showsShop = true }
    }

    private func closeShop() {
        if let shopVisit { analytics.shopVisited(shopVisit) }
        shopVisit = nil
        withAnimation { showsShop = false }
    }

    /// Looks earned so far, each reported once: checked at launch and whenever a level or run ends.
    private func reportEarnedLooks() {
        analytics.earned(progress.earnedLooks.map(\.id))
    }

    /// Adventure's or the Open Water's tutorial (`ArcadeTutorial`), seen once however it ends. The first time its way to
    /// play is opened, finishing or skipping it goes on with `next` (Adventure's world map, an Open Water run), and it
    /// skips rising and falling if the other taught them. From Settings' How to play (no `next`), it's played whole,
    /// and it goes back home, as leaving from its pause menu (Home) does.
    /// `beat` (Xcode builds, from the tuner): start partway, to playtest one beat.
    private func playTutorial(_ course: ArcadeTutorial.Course, from beat: ArcadeTutorial.Beat? = nil, then next: (() -> Void)? = nil) {
        let game = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: course,
                             knowsControls: next != nil && progress.knowsControls)
        #if DEBUG
        if let beat { game.debugSetTutorialStart(beat) }
        #endif
        game.analytics = analytics
        // Seen once it's finished, skipped or left; closing the app partway through plays it again next time.
        game.onTutorialFinished = { progress.sawTutorial(course) }
        // Left once: Skip stays up through its closing line (and while an Open Water run's first level is still being
        // planned), and a second way out mustn't start a second run.
        var left = false
        game.onExit = { [weak game] in
            guard !left else { return }
            left = true
            progress.sawTutorial(course)
            if let next, game?.leftTutorialForHome != true {
                next()
                return
            }
            // A gentle fade to the home screen, not a cut.
            withAnimation(.easeInOut(duration: 0.7)) {
                scene = nil
                selectedWorld = nil
                showsWorlds = false
                returnedFrom = nil
            }
        }
        show(game)
    }

    /// Puts a level (or the tutorial) on screen, your fish in what it wears.
    private func show(_ game: GameScene) {
        game.playerLook = progress.look
        scenePaused = false
        game.onPause = { scenePaused = $0 }
        sceneWorld = game.arcadeWorld
        game.onWorldChange = { sceneWorld = $0 }
        scene = game
    }

    /// The credits game: given nothing of the player's but your fish's look (no progress, purchases, or analytics), so
    /// it can't record anything. Skip or its last card goes back to Settings.
    private func playCredits() {
        let game = CreditsScene(look: progress.look)
        game.onExit = { withAnimation(.easeInOut(duration: 0.5)) { credits = nil } }
        withAnimation(.easeInOut(duration: 0.5)) { credits = game }
    }

    private func play(_ world: ArcadeWorld, index: Int) {
        // Past the free levels: show what the unlock opens instead.
        var offersUnlock = true
        #if DEBUG
        offersUnlock = ArcadePlaytest.selection == nil
        #endif
        if offersUnlock && ArcadeUnlock.needsUnlock(world, index, unlocked: purchases.isUnlocked) {
            withAnimation { offer = UnlockOffer(featured: world, source: .padlockedLevel) }
            return
        }
        #if DEBUG
        guard progress.isOpen(world, index) || ArcadePlaytest.selection != nil else { return }
        #else
        guard progress.isOpen(world, index) else { return }
        #endif
        let game = GameScene(world: world, levelIndex: index, showsJellyLesson: !progress.save.hasSeenJellyLesson)
        #if DEBUG
        StoreCapture.attach(game)
        StoreFootage.attach(game)
        #endif
        game.analytics = analytics
        game.hasCleared = { index in progress.isCleared(world, index) }
        if offersUnlock {
            game.levelNeedsUnlock = { [purchases] index in
                ArcadeUnlock.needsUnlock(world, index, unlocked: purchases.isUnlocked)
            }
        }
        // The last level cleared for the first time this visit, so the map can show the step forward.
        var firstClear: Int?
        advancedFrom = nil
        lastPlayWon = false
        game.onClear = { [weak game] index, seconds in
            #if DEBUG
            guard let scene = game, !scene.debugPracticeRun else { return }
            #endif
            firstClear = progress.isCleared(world, index) ? nil : index
            lastPlayWon = true
            // A high point worth a review: a level hard won, or a first Deep End clear.
            if firstClear != nil { review.firstCleared(world.levelID(index), deepEnd: ArcadeWorld.isDeepEnd(index)) }
            if index == ArcadeWorld.mainLevelCount - 1 && !progress.isCleared(world, index) {
                // Straight to the conquered screen, with no result card first.
                conquered = world
                game?.leavesForConqueredScreen = true
            }
            progress.clear(world, index, seconds: seconds)
        }
        game.onDeath = { [weak game] index in
            #if DEBUG
            guard let game, !game.debugPracticeRun else { return }
            #endif
            if !progress.isCleared(world, index) { review.died(on: world.levelID(index)) }
        }
        game.onJellyLesson = { [weak game] in
            #if DEBUG
            guard let game, !game.debugPracticeRun else { return }
            #endif
            progress.sawJellyLesson()
        }
        game.onExit = { [weak game] in
            game?.exitMetrics()
            returnedFrom = game?.currentLevelIndex
            // Left from the card of a level just cleared for the first time: your fish swims on to the next stop.
            // (A world just conquered stays on its crowned tenth level.)
            if let firstClear, firstClear == returnedFrom, conquered == nil, firstClear + 1 < world.levelCount {
                advancedFrom = firstClear
                returnedFrom = firstClear + 1
                // Once: the map's fish has swum by then, and redrawing the map later shouldn't swim it again.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if advancedFrom == firstClear { advancedFrom = nil } }
            }
            scene = nil
            if game?.leftForUnlock == true {
                // Next level was past the free ones: the map waits on it, under what the unlock opens.
                returnedFrom = game.map { $0.currentLevelIndex + 1 }
                withAnimation { offer = UnlockOffer(featured: world, source: .nextLevel) }
            }
            if let world = conquered {
                conquered = nil
                // Only a real unlock is remembered; the tuner's preview leaves progress alone.
                progress.sawUnlock(world)
                celebrate(world)
            }
        }
        show(game)
    }
}

/// Skip, small in the screen's top corner, for the tutorial and the credits: for players who've seen them before.
struct SkipButton: View {
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.menuScale) private var scale

    var body: some View {
        Button("Skip", action: action)
            .font(.custom("AvenirNext-DemiBold", size: 14)).foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.black.opacity(0.25), in: Capsule())
            .buttonStyle(.plain)
            .padding(.leading, 24).padding(.top, 14)
            .scaleEffect(scale, anchor: .topLeading)
            .accessibilityLabel(accessibilityLabel)
    }
}

/// What the unlock's screen was opened for.
private struct UnlockOffer {
    /// The world the player was trying to get into, if any.
    var featured: ArcadeWorld?
    /// Where it was opened from, for the paywall funnel (`ArcadeAnalytics.offerShown`); nil for a tuner preview, which
    /// isn't counted.
    var source: ArcadeAnalytics.OfferSource?
    /// From the home screen's Unlock all: the screen says it opens both ways to play (`UnlockView.bothModes`).
    var bothModes = false
}
