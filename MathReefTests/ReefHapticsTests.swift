import Foundation
import Testing
@testable import MathReef

/// The Vibration switch in Settings.
@MainActor
struct ReefHapticsTests {
    private let defaults: UserDefaults

    init() {
        let name = "ReefHapticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test func vibrationIsOnByDefaultAndTheSettingIsRemembered() {
        let haptics = ReefHaptics(defaults: defaults)
        #expect(haptics.isVibrationOn)
        haptics.isVibrationOn = false
        #expect(!ReefHaptics(defaults: defaults).isVibrationOn)
        haptics.isVibrationOn = true
        #expect(ReefHaptics(defaults: defaults).isVibrationOn)
    }

    /// 1.0 had no switch, so its saves vibrate, whatever their sound setting.
    @Test func anOldSaveVibrates() {
        defaults.set(false, forKey: "mathReef.soundOn")
        #expect(ReefHaptics(defaults: defaults).isVibrationOn)
    }
}
