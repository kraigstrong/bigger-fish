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

    @Test func vibrationStartsOnAndIsRemembered() {
        let suite = "biggerFish.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ArcadeSettings(defaults: defaults).vibrationOn)
        ArcadeSettings(defaults: defaults).vibrationOn = false
        #expect(!ArcadeSettings(defaults: defaults).vibrationOn)
    }

    /// Settings: the privacy policy and support are on biggerfish.app, restoring shows only while the unlock is on sale
    /// and not bought, and the version reads from Info.plist.
    @Test func settingsLinksRestoreAndVersion() {
        #expect(ArcadeLinks.privacy.absoluteString == "https://biggerfish.app/privacy")
        #expect(ArcadeLinks.support.absoluteString == "https://biggerfish.app/support")
        #expect(SettingsView.showsRestore(selling: true, unlocked: false))
        #expect(!SettingsView.showsRestore(selling: true, unlocked: true) && !SettingsView.showsRestore(selling: false, unlocked: false))
        #expect(SettingsView.versionLine(["CFBundleShortVersionString": "0.4", "CFBundleVersion": "7"]) == "Version 0.4 (7)")
        #expect(SettingsView.versionLine(Bundle.main.infoDictionary ?? [:]).hasPrefix("Version 1."))
    }

    /// The scenes ask for 120 frames a second; on a ProMotion iPhone, iOS only allows more than 60 with this key, and
    /// without it the credits stuttered until you touched the screen.
    @Test func theAppMayRunAt120FramesASecond() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone") as? Bool == true)
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

    /// The game's view hands it the scene before it's in a window, and iOS may ignore waking haptics for a view not on
    /// screen (the first death froze on the phone): they wait for the first frame on screen, then wake.
    @MainActor @Test func hapticsWakeOnlyOnceTheSceneIsOnScreen() {
        let was = ArcadeSettings.shared.vibrationOn
        defer { ArcadeSettings.shared.vibrationOn = was }
        ArcadeSettings.shared.vibrationOn = true
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        #expect(scene.debugHapticsWaitForWindow)
        let window = UIWindow(frame: view.frame)
        window.addSubview(view)
        scene.update(1)
        #expect(!scene.debugHapticsWaitForWindow)
        withExtendedLifetime(window) {}
    }

    /// Every meal is felt, and a win; the Vibration switch silences them all.
    @MainActor @Test func hapticsFollowTheVibrationSwitch() {
        let was = ArcadeSettings.shared.vibrationOn
        defer { ArcadeSettings.shared.vibrationOn = was }
        func play() -> [GameScene.Haptic] {
            let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            defer { withExtendedLifetime(view) {} }
            _ = scene.debugPlayTutorial(from: .eatEnough)
            return scene.debugHaptics
        }
        ArcadeSettings.shared.vibrationOn = true
        let felt = play()
        #expect(felt.filter { $0 == .meal || $0 == .closeCall }.count >= 4, "felt: \(felt)")
        #expect(felt.last == .win)
        ArcadeSettings.shared.vibrationOn = false
        #expect(play().isEmpty)
    }

    /// Pausing again and again draws the menu once, with switches that follow Settings' changes in between.
    @MainActor @Test func pausingDrawsTheMenuOnce() {
        let was = ArcadeSettings.shared.musicOn
        defer { ArcadeSettings.shared.musicOn = was }
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        defer { withExtendedLifetime(view) {} }
        scene.debugStart()
        for round in 0..<3 {
            ArcadeSettings.shared.musicOn = round.isMultiple(of: 2)
            scene.debugPauseForTuning()
            #expect(scene.debugPauseBackdrops == 1)
            #expect(scene.debugSoundSwitches[1] == ArcadeSettings.shared.musicOn)
            scene.debugResume()
        }
    }

    /// The scene draws with `ignoresSiblingOrder`, so only depth decides what's on top: the backdrop under everything,
    /// and each control's words and icons over its own background. (Siblings at one depth drew in any order on a phone:
    /// the backdrop came out over the controls.)
    @MainActor @Test func thePauseMenuDrawsInOrderByDepthAlone() throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        defer { withExtendedLifetime(view) {} }
        scene.debugStart()
        scene.debugPauseForTuning()
        let menu = scene.debugPauseMenu
        func descendants(_ node: SKNode) -> [SKNode] { node.children.flatMap { [$0] + descendants($0) } }
        func depth(_ node: SKNode) -> CGFloat {
            var z: CGFloat = 0, current: SKNode? = node
            while let at = current, at !== menu { z += at.zPosition; current = at.parent }
            return z
        }
        let all = descendants(menu)
        let backdrop = try #require(all.first { $0.name == "pauseBackdrop" })
        #expect(all.filter { $0 !== backdrop }.allSatisfy { depth($0) > depth(backdrop) })
        let words = all.filter { $0 is SKLabelNode || ($0 is SKSpriteNode && $0 !== backdrop) }
        let backgrounds = all.filter { $0 is SKShapeNode && $0.name != "knob" }
        let knobs = all.filter { $0.name == "knob" }
        #expect(!words.isEmpty && !backgrounds.isEmpty && knobs.count == 3)
        #expect(words.map(depth).min()! > backgrounds.map(depth).max()!)
        #expect(knobs.map(depth).min()! > backgrounds.map(depth).max()!)
    }

    @MainActor @Test func voiceOverReachesThePauseMenuAndItsSoundSwitches() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        scene.debugPauseForTuning()
        let elements = (scene.accessibilityElements as? [UIAccessibilityElement]) ?? []
        #expect(elements.compactMap(\.accessibilityLabel) == ["Resume", "Restart level", "Level map", "Sound effects", "Music", "Vibration"])
        let effects = elements.first { $0.accessibilityLabel == "Sound effects" }
        let was = ArcadeSettings.shared.soundEffectsOn
        let shown = scene.debugSoundSwitches
        #expect(shown == [ArcadeSettings.shared.soundEffectsOn, ArcadeSettings.shared.musicOn, ArcadeSettings.shared.vibrationOn])
        #expect(effects?.accessibilityActivate() == true)
        #expect(ArcadeSettings.shared.soundEffectsOn == !was)
        // Its switch flips with it; the others stay as they were.
        #expect(scene.debugSoundSwitches == [!was, shown[1], shown[2]])
        ArcadeSettings.shared.soundEffectsOn = was
        withExtendedLifetime(view) {}
    }
}
