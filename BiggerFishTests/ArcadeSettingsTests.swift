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

    @Test func everySoundShipsInTheApp() {
        for effect in ArcadeAudio.Effect.allCases {
            #expect(Bundle.main.url(forResource: effect.rawValue, withExtension: "caf") != nil, "\(effect) is missing")
        }
        for music in ArcadeAudio.Music.allCases {
            #expect(Bundle.main.url(forResource: music.rawValue, withExtension: "m4a") != nil, "\(music) is missing")
        }
    }

    /// The screen stays awake only while you're playing: the card before a level, pausing, the result, and the maps
    /// sleep as the phone normally would.
    @MainActor @Test func theScreenStaysAwakeOnlyWhilePlaying() {
        #expect(GameScene.keepsScreenAwake(.playing))
        #expect(![GameScene.Phase.ready, .paused, .won, .lost].contains(where: GameScene.keepsScreenAwake))
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        #expect(UIApplication.shared.isIdleTimerDisabled)
        scene.debugPauseForTuning()
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        view.presentScene(nil)
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        // A scene that's never shown (a simulation) leaves the setting alone.
        let headless = GameScene(world: .shallowReef, levelIndex: 0)
        headless.debugStart()
        #expect(!UIApplication.shared.isIdleTimerDisabled)
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
