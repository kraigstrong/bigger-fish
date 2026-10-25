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
        // Drawn bigger on an iPad (ReefScreen.swift).
        ReefView(scene: scene)
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }
}
