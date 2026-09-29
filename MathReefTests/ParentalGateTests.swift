import FishKit
import Foundation
import Testing
@testable import MathReef

struct ParentalGateTests {
    private func gate(seed: UInt64 = 1) -> ParentalGate {
        var rng = SeededGenerator(seed: seed)
        return ParentalGate(using: &rng)
    }

    @Test func writesNumbersInWords() {
        #expect(ParentalGate.words(0) == "zero")
        #expect(ParentalGate.words(13) == "thirteen")
        #expect(ParentalGate.words(19) == "nineteen")
        #expect(ParentalGate.words(20) == "twenty")
        #expect(ParentalGate.words(42) == "forty-two")
        #expect(ParentalGate.words(99) == "ninety-nine")
    }

    /// Factors are past anything in the game, and the product always has three digits.
    @Test func asksAThreeDigitProductInWords() {
        for seed in 1...200 {
            let g = gate(seed: UInt64(seed))
            #expect(ParentalGate.factorRange.contains(g.a) && ParentalGate.factorRange.contains(g.b))
            #expect((100...999).contains(g.answer))
            #expect(g.question == "What is \(ParentalGate.words(g.a)) times \(ParentalGate.words(g.b))?")
            #expect(g.question.allSatisfy { !$0.isNumber })
        }
    }

    @Test func passesOnTheRightAnswer() {
        var g = gate()
        let digits = String(g.answer).compactMap(\.wholeNumberValue)
        #expect(g.type(digits[0]) == .typing)
        #expect(g.type(digits[1]) == .typing)
        #expect(g.type(digits[2]) == .passed)
    }

    @Test func failsOnceAWrongAnswerIsComplete() {
        var g = gate()
        let wrong = String(g.answer == 999 ? 998 : g.answer + 1).compactMap(\.wholeNumberValue)
        #expect(g.type(wrong[0]) == .typing)
        #expect(g.type(wrong[1]) == .typing)
        #expect(g.type(wrong[2]) == .failed)
    }

    @Test func deleteTakesBackADigit() {
        var g = gate()
        let digits = String(g.answer).compactMap(\.wholeNumberValue)
        _ = g.type(digits[0])
        _ = g.type((digits[1] + 1) % 10)  // a slip...
        g.deleteDigit()                    // ...taken back before the answer is complete
        #expect(g.entry == String(digits[0]))
        #expect(g.type(digits[1]) == .typing)
        #expect(g.type(digits[2]) == .passed)
    }

    @Test func linksGoToMathReefPagesOnBrightBench() {
        #expect(ParentLinks.privacy.absoluteString == "https://brightbench.app/math-reef/privacy")
        #expect(ParentLinks.support.absoluteString == "https://brightbench.app/math-reef/support")
    }
}
