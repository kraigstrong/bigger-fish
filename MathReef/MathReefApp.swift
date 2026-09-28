import SpriteKit
import SwiftUI

@main
struct MathReefApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var scene: PracticeScene = {
        let scene = PracticeScene(size: CGSize(width: 852, height: 393))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }
}
