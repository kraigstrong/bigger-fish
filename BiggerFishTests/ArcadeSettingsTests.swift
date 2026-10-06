import Foundation
import Testing
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
}
