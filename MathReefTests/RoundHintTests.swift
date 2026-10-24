import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import MathReef

/// The round's control hint: which rounds start with it, when it goes, and that it stays clear of the question.
struct RoundHintTests {
    private typealias L = ReefTuning

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "RoundHintTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// A round the kid holds in, `framesFirst` frames after it starts.
    private func playRound(_ hint: RoundHint, framesFirst: Int = 30) {
        guard hint.roundStarted() else { return }
        for _ in 0..<framesFirst { _ = hint.update(holding: false) }
        _ = hint.update(holding: true)
    }

    @Test func aFreshInstallsRoundStartsWithItUntilTheKidHolds() {
        withDefaults { defaults in
            let hint = RoundHint(defaults: defaults)
            #expect(hint.roundStarted())
            // However long the kid waits.
            for _ in 0..<(60 * 60) { #expect(!hint.update(holding: false)) }
            #expect(hint.isShowing)
            #expect(hint.update(holding: true))
            #expect(!hint.isShowing)
            // Gone for the rest of the round, and counted once.
            #expect(!hint.update(holding: true))
            #expect(!hint.update(holding: false))
            #expect(hint.roundsHeld == 1)
        }
    }

    @Test func onlyTheFirstFewRoundsStartWithIt() {
        withDefaults { defaults in
            let hint = RoundHint(defaults: defaults)
            for round in 0..<L.roundHintRounds {
                #expect(hint.roundStarted(), "Round \(round + 1)")
                playRound(hint)
            }
            #expect(hint.roundsHeld == L.roundHintRounds)
            #expect(!hint.roundStarted())
            #expect(!hint.update(holding: true))
            // Saved: it stays away after the app is closed and opened again.
            #expect(!RoundHint(defaults: defaults).roundStarted())
        }
    }

    /// A kid who leaves a round, or finishes one, without holding hasn't found the control: the next round shows it
    /// again, and the round doesn't count.
    @Test func aRoundWithoutAHoldDoesntCount() {
        withDefaults { defaults in
            let hint = RoundHint(defaults: defaults)
            for _ in 0..<(L.roundHintRounds + 2) {
                #expect(hint.roundStarted())
                for _ in 0..<120 { _ = hint.update(holding: false) }
                hint.roundEnded()
                #expect(!hint.isShowing)
                // A touch on the results or the map isn't a hold in the round.
                #expect(!hint.update(holding: true))
            }
            #expect(hint.roundsHeld == 0)
            #expect(RoundHint(defaults: defaults).roundStarted())
        }
    }

    /// Saved state from before the hint (Math Reef 1.0) has no count, which reads as no rounds yet: players updating
    /// with progress see it for their first few rounds too, and it goes at their first hold.
    @Test func anOlderSaveReadsAsNoRoundsYet() {
        withDefaults { defaults in
            let old = #"{"add.plus12":{"passed":true,"bestPercent":92}}"#
            defaults.set(Data(old.utf8), forKey: "mathReef.progress.v2")
            defaults.set(true, forKey: TutorialRecord.key)
            #expect(defaults.object(forKey: RoundHint.key) == nil)
            let hint = RoundHint(defaults: defaults)
            #expect(hint.roundsHeld == 0)
            #expect(hint.roundStarted())
        }
    }

    @Test func storeCapturesNeverShowIt() {
        #expect(!RoundHint(defaults: StoreCapture.defaults).roundStarted())
    }

    /// The words sit above the tutorial's finger, in the water a round plays in, and clear of the question beside the
    /// fish on every screen, whatever the question and however high the fish, even at the top of their pop-in.
    @MainActor @Test func itStaysClearOfEveryQuestion() {
        let screens: [(name: String, size: CGSize)] = DrawOrderTests.screens
        let prompts = Set(Curriculum.worlds.flatMap { $0.levels.flatMap(\.facts) }.map(\.prompt))
        let widest = prompts.max { pillWidth($0) < pillWidth($1) }!
        let caption = reefLabel(RoundHint.caption, fontSize: L.roundHintCaptionFontSize, heavy: true).frame
        let pop: CGFloat = 1.15
        for (name, size) in screens {
            let field = ReefScreen.playfield(in: size)
            let overlay = TutorialOverlay(size: size, field: field, skippable: false)
            let words = CGRect(x: overlay.captionSpot.x - caption.width * pop / 2,
                               y: overlay.captionSpot.y - caption.height * pop / 2,
                               width: caption.width * pop, height: caption.height * pop)
            #expect(field.contains(words), "\(name): \(words) leaves the water \(field)")
            let questionRight = size.width * L.playerScreenX + pillWidth(widest) / 2
            #expect(questionRight < words.minX, "\(name): \"\(widest)\" reaches \(questionRight), the words \(words.minX)")
        }
    }

    /// The question's pill, as the scene draws it around the words (`setPrompt`).
    private func pillWidth(_ prompt: String) -> CGFloat {
        reefLabel(prompt, fontSize: L.promptFontSize, heavy: true).frame.width + 1.5 + 28
    }
}
