import SpriteKit
import Testing
@testable import MathReef

/// The grown-ups' unlock screen (UnlockScreen.swift): what it says the purchase opens matches the curriculum and the free
/// sample, and it fits every screen from the smallest phone to an iPad, its buttons apart and where they're drawn. How
/// it draws is `DrawOrderTests`'s, and the purchase itself is checked by hand in Xcode (`ReefUnlockTests`).
@MainActor
struct UnlockScreenTests {
    /// Scenes from the smallest phone to the biggest, then iPads, which lay out as the biggest phone, only taller
    /// (`ReefScreen`).
    static let screens: [(name: String, size: CGSize)] = [
        ("iPhone SE", CGSize(width: 667, height: 375)), ("iPhone 13 mini", CGSize(width: 812, height: 375)),
        ("iPhone 8 Plus", CGSize(width: 736, height: 414)), ("iPhone 17", CGSize(width: 874, height: 402)),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440)),
    ] + [("iPad mini", CGSize(width: 1133, height: 744)), ("iPad Air 11-inch", CGSize(width: 1180, height: 820)),
         ("iPad Pro 13-inch", CGSize(width: 1376, height: 1032))].map { name, screen in
        let scale = ReefScreen.scale(for: screen)
        return (name, CGSize(width: screen.width / scale, height: screen.height / scale))
    }

    private func screen(_ size: CGSize, price: String? = "$4.99") -> UnlockScreen {
        UnlockScreen(size: size, price: price, featured: "multiplication", onBuy: {}, onRestore: {}, onClose: {})
    }

    // MARK: What it says

    @Test func everyWorldWithItsLevelsAndFreeOnes() {
        let worlds = Curriculum.worlds.filter { !$0.comingSoon }
        #expect(UnlockOffer.worlds.map(\.id) == worlds.map(\.id))
        for (summary, world) in zip(UnlockOffer.worlds, worlds) {
            #expect(summary.levels == world.levels.count, "\(world.id)")
            #expect(summary.freeLevels == FreeSample.freeLevels(in: world), "\(world.id)")
            #expect(summary.checkpoints == Set(world.levels.indices.filter { world.levels[$0].isCheckpoint }), "\(world.id)")
            #expect(!summary.grades.isEmpty, "\(world.id) has no grades")
            #expect(!summary.topics.isEmpty, "\(world.id) has no topics")
        }
        #expect(UnlockOffer.totalLevels == worlds.map(\.levels.count).reduce(0, +))
        #expect(UnlockOffer.totalFree == worlds.map { FreeSample.freeLevels(in: $0) }.reduce(0, +))
    }

    /// From the first question a world asks to the hardest it gets to, skip tests aside.
    @Test func eachWorldsFirstAndHardestQuestions() {
        let questions = Dictionary(uniqueKeysWithValues: UnlockOffer.worlds.map { ($0.id, ($0.firstQuestion, $0.hardestQuestion)) })
        #expect(questions["addition"]?.0 == "3 + 1")
        #expect(questions["subtraction"]?.0 == "4 − 1")
        #expect(questions["exponents"]?.0 == "3²")
        #expect(questions["exponents"]?.1 == "10³")
        for world in Curriculum.worlds where !world.comingSoon {
            let hardest = world.levels.filter { !$0.isCheckpoint }.last!.facts.map(\.answer).max()!
            let shown = world.levels.flatMap(\.facts).first { $0.prompt == questions[world.id]?.1 }
            #expect(shown?.answer == hardest, "\(world.id)")
        }
    }

    @Test func thePriceIsOnTheBuyButton() {
        let words = labels(in: screen(Self.screens[0].size))
        #expect(words.contains("Unlock for $4.99"))
        #expect(words.contains("Restore purchases"))
        #expect(words.contains("Not now"))
        // Until the App Store answers, there's no price to show.
        #expect(labels(in: screen(Self.screens[0].size, price: nil)).contains("Unlock"))
    }

    // MARK: Fitting the screen

    /// Everything but the backdrop on screen, clear of a Dynamic Island at the sides and of the home indicator at the
    /// bottom, give or take a stroke's width.
    @Test func itFitsTheScreen() {
        for (name, size) in Self.screens {
            let unlock = screen(size)
            let margin = UnlockScreen.sideMargin(for: size) - 3
            let safe = CGRect(x: margin, y: 10, width: size.width - margin * 2, height: size.height - 12)
            for (node, frame) in drawn(in: unlock) where node.parent !== unlock {
                #expect(safe.contains(frame), "\(name): \(node) at \(frame) is outside \(safe)")
            }
        }
    }

    @Test func itsButtonsAreApartAndWhereTheyreDrawn() {
        for (name, size) in Self.screens {
            buttonsAreApartAndWhereTheyreDrawn(screen(size), name: name, size: size)
        }
    }

    private func buttonsAreApartAndWhereTheyreDrawn(_ unlock: UnlockScreen, name: String, size: CGSize) {
        let buttons = unlock.buttons.dropLast().map(\.frame)
        #expect(buttons.count == 3, "\(name)")
        // The last is the whole screen, which takes taps off the buttons so they don't close it.
        #expect(unlock.buttons.last?.frame == CGRect(origin: .zero, size: size), "\(name)")
        for (i, a) in buttons.enumerated() {
            #expect(CGRect(origin: .zero, size: size).contains(a), "\(name): button \(i) is off screen")
            // The scene's touches reach 10 points past a button's frame.
            for b in buttons[(i + 1)...] { #expect(!a.insetBy(dx: -10, dy: -10).intersects(b), "\(name): \(a) meets \(b)") }
            // Its pill, as wide as it, give or take its outline.
            let drawn = unlock.nodes(at: CGPoint(x: a.midX, y: a.midY)).compactMap { $0 as? SKShapeNode }
            #expect(drawn.contains { abs(frame(of: $0, in: unlock).width - a.width) < 6 }, "\(name): no button drawn at \(a)")
        }
    }

    /// An iPad has the height for each world's topics; a phone doesn't.
    @Test func topicsWhereThereIsTheHeight() {
        for (name, size) in Self.screens {
            #expect(screen(size).showsTopics == name.hasPrefix("iPad"), "\(name)")
        }
    }

    // MARK: Helpers

    private func labels(in node: SKNode) -> [String] {
        var found: [String] = []
        node.enumerateChildNodes(withName: ".//*") { child, _ in
            if let label = child as? SKLabelNode, let text = label.attributedText?.string ?? label.text { found.append(text) }
        }
        return found
    }

    /// Every label and shape, with its frame in `root`'s coordinates.
    private func drawn(in root: SKNode) -> [(SKNode, CGRect)] {
        var found: [(SKNode, CGRect)] = []
        root.enumerateChildNodes(withName: ".//*") { child, _ in
            guard child is SKLabelNode || child is SKShapeNode || child is SKSpriteNode else { return }
            found.append((child, self.frame(of: child, in: root)))
        }
        return found
    }

    private func frame(of node: SKNode, in root: SKNode) -> CGRect {
        let own = node.frame
        guard let parent = node.parent else { return own }
        let a = parent.convert(CGPoint(x: own.minX, y: own.minY), to: root)
        let b = parent.convert(CGPoint(x: own.maxX, y: own.maxY), to: root)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
