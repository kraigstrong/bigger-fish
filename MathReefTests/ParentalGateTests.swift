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

    @Test func asksManageableMentalMathInWords() {
        for seed in 1...200 {
            let g = gate(seed: UInt64(seed))
            #expect(ParentalGate.numberRange.contains(g.a) && ParentalGate.numberRange.contains(g.b))
            #expect((20...198).contains(g.answer))
            #expect(g.question == "What is \(ParentalGate.words(g.a)) plus \(ParentalGate.words(g.b))?")
            #expect(g.question.allSatisfy { !$0.isNumber })
        }
    }

    @Test func passesOnTheRightAnswer() {
        for seed in 1...200 {
            var g = gate(seed: UInt64(seed))
            let digits = String(g.answer).compactMap(\.wholeNumberValue)
            for digit in digits.dropLast() { #expect(g.type(digit) == .typing) }
            #expect(g.type(digits.last!) == .passed)
        }
    }

    @Test func failsOnceAWrongAnswerIsComplete() {
        for seed in 1...200 {
            var g = gate(seed: UInt64(seed))
            let wrong = String(g.answer == 99 ? 98 : g.answer + 1).compactMap(\.wholeNumberValue)
            for digit in wrong.dropLast() { #expect(g.type(digit) == .typing) }
            #expect(g.type(wrong.last!) == .failed)
        }
    }

    @Test func deleteTakesBackADigit() {
        for seed in 1...200 {
            var g = gate(seed: UInt64(seed))
            let digits = String(g.answer).compactMap(\.wholeNumberValue)
            _ = g.type((digits[0] + 1) % 10)  // a slip...
            g.deleteDigit()                    // ...taken back before the answer is complete
            #expect(g.entry.isEmpty)
            _ = g.type(digits[0])
            #expect(g.entry == String(digits[0]))
            for digit in digits.dropFirst().dropLast() { #expect(g.type(digit) == .typing) }
            #expect(g.type(digits.last!) == .passed)
        }
    }

    @Test func linksGoToMathReefPagesOnBrightBench() {
        #expect(ParentLinks.privacy.absoluteString == "https://brightbench.app/math-reef/privacy")
        #expect(ParentLinks.support.absoluteString == "https://brightbench.app/math-reef/support")
    }
}
