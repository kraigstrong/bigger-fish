import SpriteKit
import SwiftUI

struct ContentView: View {
    #if DEBUG
    @StateObject private var progress = ArcadeProgress(defaults: ArcadePlaytest.defaults)
    #else
    @StateObject private var progress = ArcadeProgress()
    #endif
    @State private var selectedWorld: ArcadeWorld?
    @State private var scene: GameScene?

    var body: some View {
        Group {
            if let scene {
                SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
            } else if let world = selectedWorld {
                ArcadeLevelMap(world: world, progress: progress,
                               onBack: { selectedWorld = nil }, onPlay: { play(world, index: $0) })
            } else {
                ArcadeWorldMap(progress: progress, onSelect: { selectedWorld = $0 })
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            #if DEBUG
            if scene == nil && selectedWorld == nil, let selection = ArcadePlaytest.selection {
                selectedWorld = selection.world
                play(selection.world, index: selection.index)
            }
            #endif
        }
    }

    private func play(_ world: ArcadeWorld, index: Int) {
        #if DEBUG
        guard progress.isOpen(world, index) || ArcadePlaytest.selection != nil else { return }
        #else
        guard progress.isOpen(world, index) else { return }
        #endif
        let game = GameScene(size: CGSize(width: 852, height: 393), world: world, levelIndex: index,
                             showsJellyLesson: !progress.save.hasSeenJellyLesson)
        game.scaleMode = .resizeFill
        game.onClear = { index, seconds in progress.clear(world, index, seconds: seconds) }
        game.onJellyLesson = { progress.sawJellyLesson() }
        game.onExit = { scene = nil }
        scene = game
    }
}
