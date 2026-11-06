import UIKit

/// Math Reef's haptics: a success tap for a right answer and a crown, and soft bumps for a wrong one
/// and the tutorial's let-go. Parents can turn them off in Settings (Vibration); remembered across
/// launches.
@MainActor
final class ReefHaptics {
    private static let vibrationOnKey = "mathReef.vibrationOn"
    private let defaults: UserDefaults
    private let positive = UINotificationFeedbackGenerator()
    private let gentle = UIImpactFeedbackGenerator(style: .soft)

    var isVibrationOn: Bool {
        didSet { defaults.set(isVibrationOn, forKey: Self.vibrationOnKey) }
    }

    /// - Parameter defaults: where the vibration setting is remembered.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVibrationOn = defaults.object(forKey: Self.vibrationOnKey) as? Bool ?? true
    }

    /// Readies both generators, so the first tap doesn't stall a frame.
    func prepare() {
        positive.prepare()
        gentle.prepare()
    }

    func success() {
        guard isVibrationOn else { return }
        positive.notificationOccurred(.success)
    }

    func bump(intensity: CGFloat) {
        guard isVibrationOn else { return }
        gentle.impactOccurred(intensity: intensity)
    }
}
