import Foundation
import SpriteKit
import Testing
import UIKit
@testable import BiggerFish

struct ArcadeSettingsTests {
    @Test func soundSwitchesStartOnAndAreRemembered() {
        let suite = "biggerFish.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = ArcadeSettings(defaults: defaults)
        #expect(settings.soundEffectsOn && settings.musicOn)
        settings.soundEffectsOn = false
        settings.musicOn = false
        let relaunched = ArcadeSettings(defaults: defaults)
        #expect(!relaunched.soundEffectsOn && !relaunched.musicOn)
        relaunched.musicOn = true
        #expect(ArcadeSettings(defaults: defaults).musicOn && !ArcadeSettings(defaults: defaults).soundEffectsOn)
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor @Test func voiceOverReachesThePauseMenuAndItsSoundSwitches() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        scene.debugPauseForTuning()
        let elements = (scene.accessibilityElements as? [UIAccessibilityElement]) ?? []
        #expect(elements.compactMap(\.accessibilityLabel) == ["Resume", "Restart", "Level map", "Sound effects", "Music"])
        let effects = elements.first { $0.accessibilityLabel == "Sound effects" }
        let was = ArcadeSettings.shared.soundEffectsOn
        #expect(effects?.accessibilityActivate() == true)
        #expect(ArcadeSettings.shared.soundEffectsOn == !was)
        ArcadeSettings.shared.soundEffectsOn = was
        withExtendedLifetime(view) {}
    }
}
