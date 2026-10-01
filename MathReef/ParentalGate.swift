import Foundation

// Kids-category apps must put links that leave the app behind a parental gate (App Review
// Guideline 1.3). The gate asks addition written in words, answered on a number pad.
// Keep the mental arithmetic manageable for parents; a wrong answer ends the attempt.

/// Pages for grown-ups on brightbench.app, opened in Safari once the gate is passed.
enum ParentLinks {
    static let privacy = URL(string: "https://brightbench.app/math-reef/privacy")!
    static let support = URL(string: "https://brightbench.app/math-reef/support")!
}

struct ParentalGate {
    /// Two-digit addition: parents shouldn't need a calculator.
    static let numberRange = 10...99

    let a: Int
    let b: Int
    private(set) var entry = ""

    init<G: RandomNumberGenerator>(using rng: inout G) {
        a = Int.random(in: Self.numberRange, using: &rng)
        b = Int.random(in: Self.numberRange, using: &rng)
    }

    init() {
        var rng = SystemRandomNumberGenerator()
        self.init(using: &rng)
    }

    var answer: Int { a + b }

    /// "What is forty-two plus thirty-seven?"
    var question: String { "What is \(Self.words(a)) plus \(Self.words(b))?" }

    enum Result { case typing, passed, failed }

    /// Adds a digit. Once the entry has as many digits as the answer it's checked: a wrong answer
    /// fails the gate rather than allowing another try.
    mutating func type(_ digit: Int) -> Result {
        guard (0...9).contains(digit) else { return .typing }
        entry += String(digit)
        guard entry.count == String(answer).count else { return .typing }
        return Int(entry) == answer ? .passed : .failed
    }

    mutating func deleteDigit() {
        if !entry.isEmpty { entry.removeLast() }
    }

    /// 0...99 in words: "seventeen", "forty-two".
    static func words(_ n: Int) -> String {
        let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
                    "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        precondition((0...99).contains(n), "words(_:) covers 0...99")
        if n < 20 { return ones[n] }
        return n % 10 == 0 ? tens[n / 10] : "\(tens[n / 10])-\(ones[n % 10])"
    }
}
