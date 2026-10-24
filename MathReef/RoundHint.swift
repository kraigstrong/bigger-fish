import Foundation

// A brief control hint at the start of a round (GitHub issue #65), for a kid who skipped the first-launch tutorial, or
// a sibling who never saw it: the tutorial's "Hold" step (`TutorialOverlay`, without its Skip), with the finger
// pressing on open water, the words, and arrows above the fish and its question. It goes the moment the kid holds.
// A kid's first few rounds after install start with it (`ReefTuning.roundHintRounds`), counted in saved state.
// The rule is here and tested; the scene draws it (PracticeScene.swift) under the answer fish, so it never covers them.

/// When a round starts with the hint, and when it goes. A round counts once the kid holds while the hint shows; a round
/// left or finished before that doesn't, so a kid who hasn't found the control yet keeps seeing it.
final class RoundHint {
    /// How many rounds the kid has held through the hint, on this device. Saves from before the hint don't have it,
    /// which reads as none.
    static let key = "mathReef.roundHintRounds"
    /// The tutorial's word, and what it does, for early readers.
    static let caption = "Hold to swim up"

    private let defaults: UserDefaults
    /// Whether the round being played still shows the hint.
    private(set) var isShowing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var roundsHeld: Int { defaults.integer(forKey: Self.key) }

    /// A round is starting: whether it opens with the hint.
    @discardableResult
    func roundStarted() -> Bool {
        isShowing = roundsHeld < ReefTuning.roundHintRounds
        return isShowing
    }

    /// A frame of the round. True on the frame the hint goes: the kid's first hold, which counts the round.
    func update(holding: Bool) -> Bool {
        guard isShowing, holding else { return false }
        isShowing = false
        defaults.set(roundsHeld + 1, forKey: Self.key)
        return true
    }

    /// The round is over, or was left, before a hold: the hint goes, and the round doesn't count.
    func roundEnded() {
        isShowing = false
    }
}
