import CoreGraphics
import Foundation
import SpriteKit
import UIKit

// The first-launch tutorial: three short steps that teach Math Reef's one control by doing it.
//   1. "Hold": a finger presses on open water, away from the fish. Touching anywhere lifts the fish.
//   2. "Let go": the finger lifts off with a pop. Letting go sinks the fish.
//   3. "Eat the answer": 1 + 1, with a 2 and a 3 swimming by. Eating the 2 ends the tutorial; the 3 just
//      bounces off.
// It never fails and never moves on by itself: a kid who's stuck sees the step's hint again. After the
// catch, "Ready to play!" and a fade to the reef map (`TutorialEnding`). It plays once, on a fresh
// install, before the reef map; players with progress from before it existed skip it.
// The steps' logic is here and tested; the scene drives it (PracticeScene.swift) with the real
// movement, answer fish, and swallow. Tuning is in `ReefTuning`.

/// Whether the tutorial has been finished or skipped on this device: a flag saved beside progress and
/// settings. Saves from before the tutorial don't have it, which reads as not played yet.
final class TutorialRecord {
    static let key = "mathReef.tutorialDone"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isDone: Bool { defaults.bool(forKey: Self.key) }

    /// Finished or skipped. Leaving the app partway doesn't count, so it plays again next launch.
    func markDone() {
        defaults.set(true, forKey: Self.key)
    }

    /// Asked once at launch. Players with progress from before the tutorial existed already know the
    /// controls: they never see it, and are marked done so that clearing their progress later doesn't
    /// bring it back.
    func shouldPlayAtLaunch(hasProgress: Bool) -> Bool {
        guard !isDone else { return false }
        if hasProgress {
            markDone()
            return false
        }
        return true
    }
}

/// The tutorial's steps and when each one is done. One mechanic per step, and nothing on a clock but
/// the hint.
struct TutorialFlow {
    enum Step: Equatable { case hold, letGo, eat, done }

    enum Event: Equatable {
        /// The tutorial moved on to this step; `.done` means it's over.
        case began(Step)
        /// Show the current step's hint again.
        case hint
        /// "Eat the answer" with the wrong answer: it bounces off and the step stays.
        case tryAgain
    }

    /// The first catch: as easy a question as there is, and one wrong answer next to it.
    static let fact = Fact(op: .add, a: 1, b: 1)
    static let choices = [Choice(value: 2, isCorrect: true), Choice(value: 3, isCorrect: false)]

    /// Each step's word, for early readers: three short words at most.
    static func caption(for step: Step) -> String? {
        switch step {
        case .hold: "Hold"
        case .letGo: "Let go"
        case .eat: "Eat the answer"
        case .done: nil
        }
    }

    /// Where the 2 and the 3 swim on each pass, as fractions of the water the fish can reach. After
    /// "Let go" the fish rests on the bottom, so the first 2 swims near the top (`tutorialTopLane`, a
    /// little under the round's top lane and the caption): catching it takes a hold. The 3 always swims
    /// through the round's middle lane, so staying put never eats it. The 2 alternates with the round's
    /// bottom lane, so a kid who's stuck still makes the first catch next pass.
    static func lanes(onPass pass: Int) -> (right: CGFloat, wrong: CGFloat) {
        let lanes = ReefTuning.laneFractions
        return (right: pass.isMultiple(of: 2) ? ReefTuning.tutorialTopLane : lanes[0], wrong: lanes[1])
    }

    private(set) var step: Step = .hold
    /// "Hold": the lowest the fish has been during the current hold.
    private var holdLow: CGFloat?
    /// "Let go": the highest the fish has been since it was let go.
    private var releaseHigh: CGFloat?
    /// Seconds not doing what the step asks, since the step began or its hint last played.
    private var stuck: CGFloat = 0

    /// "Hold" and "Let go": one frame of the player fish, whose height runs `minY...maxY`.
    mutating func update(fishY y: CGFloat, holding: Bool, dt: CGFloat, minY: CGFloat, maxY: CGFloat) -> Event? {
        typealias L = ReefTuning
        let water = maxY - minY
        switch step {
        case .hold:
            guard holding else {
                holdLow = nil
                return tickStuck(dt)
            }
            let low = min(holdLow ?? y, y)
            holdLow = low
            if y - low >= water * L.tutorialRiseFraction || y >= maxY - 0.5 { return begin(.letGo) }
        case .letGo:
            guard !holding else {
                releaseHigh = nil
                return tickStuck(dt)
            }
            let high = max(releaseHigh ?? y, y)
            releaseHigh = high
            if high - y >= water * L.tutorialSinkFraction || y <= minY + 0.5 { return begin(.eat) }
        case .eat, .done:
            break
        }
        return nil
    }

    /// "Eat the answer": the fish caught an answer.
    mutating func ate(correct: Bool) -> Event? {
        guard step == .eat else { return nil }
        return correct ? begin(.done) : .tryAgain
    }

    /// "Eat the answer": both answers swam past without being caught. They come round again.
    func missed() -> Event? {
        step == .eat ? .hint : nil
    }

    private mutating func tickStuck(_ dt: CGFloat) -> Event? {
        stuck += dt
        guard stuck >= ReefTuning.tutorialHintSeconds else { return nil }
        stuck = 0
        return .hint
    }

    private mutating func begin(_ next: Step) -> Event {
        step = next
        holdLow = nil
        releaseHigh = nil
        stuck = 0
        return .began(next)
    }
}

/// How the tutorial ends, in beats the scene plays in order. After the first catch: the game's own
/// right-answer moment ("Yes!", the bell, sparkles), a closing line, then a gentle fade through the
/// deep-water color to the reef map, so it never just cuts away. Skip fades straight to the map. The
/// tutorial is saved as done when the ending starts, so closing the app during it doesn't replay it.
enum TutorialEnding {
    enum Beat: Hashable { case celebrate, closingLine, fadeOut, fadeIn }

    /// For early readers: three short words at most.
    static let closingLine = "Ready to play!"

    /// Each beat and how long it lasts (timings in `ReefTuning`).
    static func beats(skipped: Bool) -> [(beat: Beat, seconds: TimeInterval)] {
        typealias L = ReefTuning
        let fade: [(beat: Beat, seconds: TimeInterval)] = [
            (.fadeOut, L.tutorialFadeOutSeconds), (.fadeIn, L.tutorialFadeInSeconds),
        ]
        guard !skipped else { return fade }
        return [(.celebrate, L.tutorialCelebrationSeconds), (.closingLine, L.tutorialClosingLineSeconds)] + fade
    }
}

/// What the tutorial draws over the water: the demo finger, each step's word, arrows by the player
/// fish, and a small Skip button for grown-ups. Built from the game's own shapes, font, and SF Symbols.
final class TutorialOverlay: SKNode {
    private typealias L = ReefTuning
    static let answerRingName = "tutorialAnswerRing"

    private let fingerSpot: CGPoint
    private let captionSpot: CGPoint
    /// Where the "Yes!" card shows, right of the fish: the closing line takes its place.
    private let closingSpot: CGPoint
    private let eatCaptionSpot: CGPoint
    /// The finger, with its tip at the node's origin.
    private let hand = SKNode()
    /// Under the fingertip while it presses.
    private let touchSpot = SKShapeNode(circleOfRadius: 24)
    private let caption = SKNode()
    /// Chevrons above the fish for "Hold" and below it for "Let go".
    private let arrows = SKNode()
    private var arrowsPointUp = true
    private let skip = SKNode()
    /// Where a tap skips the tutorial, in scene coordinates (a little bigger than the button).
    private(set) var skipFrame = CGRect.zero

    init(size: CGSize) {
        fingerSpot = CGPoint(x: size.width * L.tutorialFingerSpot.x, y: size.height * L.tutorialFingerSpot.y)
        captionSpot = CGPoint(x: fingerSpot.x, y: fingerSpot.y + 74)
        // Along the top, above both answers' lanes.
        eatCaptionSpot = CGPoint(x: size.width / 2, y: size.height - L.tutorialEatCaptionInset)
        closingSpot = CGPoint(x: size.width * 0.6, y: size.height / 2)
        super.init()

        // The symbol's fingertip is near its top-left corner; anchor it there.
        let tip = CGPoint(x: 0.22, y: 0.92)
        if let finger = reefSymbol("hand.point.up.left.fill", pointSize: 88, weight: .regular),
           let shade = reefSymbol("hand.point.up.left.fill", pointSize: 88, weight: .regular, color: UIColor(white: 0, alpha: 0.35)) {
            finger.anchorPoint = tip
            shade.anchorPoint = tip
            shade.position = CGPoint(x: 3, y: -3)
            finger.zPosition = 0.5
            hand.addChild(shade)
            hand.addChild(finger)
        }
        hand.position = fingerSpot
        hand.zPosition = 2
        hand.alpha = 0
        addChild(hand)

        touchSpot.fillColor = SKColor(white: 1, alpha: 0.28)
        touchSpot.strokeColor = SKColor(white: 1, alpha: 0.85)
        touchSpot.lineWidth = 3
        touchSpot.position = fingerSpot
        touchSpot.zPosition = 1
        touchSpot.alpha = 0
        addChild(touchSpot)

        caption.zPosition = 3
        addChild(caption)

        let bob = SKNode()
        for i in 0..<2 {
            guard let chevron = reefSymbol("chevron.up", pointSize: 24, weight: .heavy) else { continue }
            chevron.position = CGPoint(x: 0, y: CGFloat(i) * 13)
            chevron.alpha = i == 0 ? 0.45 : 0.9
            bob.addChild(chevron)
        }
        let nudge = SKAction.moveBy(x: 0, y: 7, duration: 0.4)
        nudge.timingMode = .easeInEaseOut
        bob.run(.repeatForever(.sequence([nudge, nudge.reversed()])))
        arrows.addChild(bob)
        arrows.alpha = 0
        addChild(arrows)

        buildSkip(size: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// For grown-ups reinstalling: small and out of the way, where the settings button usually sits.
    private func buildSkip(size: CGSize) {
        let text = reefLabel("Skip", fontSize: 15, heavy: false)
        let pillSize = CGSize(width: text.frame.width + 28, height: 32)
        let pill = SKShapeNode(rectOf: pillSize, cornerRadius: pillSize.height / 2)
        pill.fillColor = SKColor(white: 0, alpha: 0.25)
        pill.strokeColor = SKColor(white: 1, alpha: 0.5)
        pill.lineWidth = 1.5
        text.zPosition = 1
        skip.addChild(pill)
        skip.addChild(text)
        skip.position = CGPoint(x: size.width - 64, y: size.height - 36)
        skip.alpha = 0.75
        skip.zPosition = 4
        addChild(skip)
        skipFrame = CGRect(
            x: skip.position.x - pillSize.width / 2, y: skip.position.y - pillSize.height / 2,
            width: pillSize.width, height: pillSize.height
        ).insetBy(dx: -12, dy: -10)
    }

    // MARK: Steps

    func show(_ step: TutorialFlow.Step) {
        let text = TutorialFlow.caption(for: step) ?? ""
        switch step {
        case .hold:
            setCaption(text, at: captionSpot)
            press()
            showArrows(up: true)
        case .letGo:
            setCaption(text, at: captionSpot)
            liftOff()
            showArrows(up: false)
        case .eat:
            hideHand()
            arrows.run(.fadeOut(withDuration: 0.2))
            setCaption(text, at: eatCaptionSpot)
        case .done:
            hideHand()
            arrows.run(.fadeOut(withDuration: 0.2))
            caption.run(.fadeOut(withDuration: 0.25))
            skip.run(.fadeOut(withDuration: 0.25))
        }
    }

    /// "Ready to play!", big, between two gold stars, where the "Yes!" card was. It pops in like the
    /// step words, then gently breathes until the fade.
    func showClosingLine() {
        setCaption(TutorialEnding.closingLine, at: closingSpot, fontSize: L.tutorialClosingLineFontSize)
        // The caption starts its pop-in small; measure it at full size.
        let halfWidth = caption.calculateAccumulatedFrame().width / caption.xScale / 2
        for side: CGFloat in [-1, 1] {
            let star = starShape(radius: 15, filled: true)
            star.position = CGPoint(x: side * (halfWidth + 26), y: 4)
            star.run(.repeatForever(.sequence([
                .rotate(byAngle: side * 0.25, duration: 0.5), .rotate(byAngle: -side * 0.25, duration: 0.5),
            ])))
            caption.addChild(star)
        }
        caption.run(.sequence([
            .wait(forDuration: 0.3),
            .repeatForever(.sequence([.scale(to: 1.05, duration: 0.5), .scale(to: 1, duration: 0.5)])),
        ]))
    }

    /// Plays the step's hint again, for a kid who hasn't done it yet.
    func replayHint(_ step: TutorialFlow.Step) {
        caption.run(.sequence([.scale(to: 1.25, duration: 0.15), .scale(to: 1, duration: 0.2)]))
        switch step {
        case .hold: press()
        case .letGo: liftOff()
        case .eat, .done: break
        }
    }

    /// Keeps the arrows by the player fish (its center on screen).
    func follow(fish: CGPoint) {
        arrows.position = CGPoint(x: fish.x, y: fish.y + (arrowsPointUp ? 1 : -1) * (L.playerRadius + 24))
    }

    /// A gold ring around the right answer, once a kid needs help finding it.
    static func answerRing() -> SKNode {
        let ring = SKShapeNode(circleOfRadius: L.answerRadius * 1.6)
        ring.name = answerRingName
        ring.strokeColor = ReefStyle.gold
        ring.fillColor = ReefStyle.gold.withAlphaComponent(0.15)
        ring.lineWidth = 3
        ring.zPosition = -1
        ring.setScale(0.2)
        ring.run(.sequence([
            .scale(to: 1, duration: 0.2),
            .repeatForever(.sequence([.scale(to: 1.15, duration: 0.45), .scale(to: 1, duration: 0.45)])),
        ]))
        return ring
    }

    // MARK: Drawing

    private func setCaption(_ text: String, at point: CGPoint, fontSize: CGFloat = L.tutorialCaptionFontSize) {
        caption.removeAllChildren()
        caption.removeAllActions()
        let shadow = reefLabel(text, fontSize: fontSize, heavy: true, color: SKColor(white: 0, alpha: 0.6))
        shadow.position = CGPoint(x: 2, y: -2)
        let front = reefLabel(text, fontSize: fontSize, heavy: true)
        front.zPosition = 0.5
        caption.addChild(shadow)
        caption.addChild(front)
        caption.position = point
        caption.alpha = 0
        caption.setScale(0.3)
        caption.run(.group([
            .fadeIn(withDuration: 0.15),
            .sequence([.scale(to: 1.15, duration: 0.18), .scale(to: 1, duration: 0.1)]),
        ]))
    }

    /// The finger comes down on the water and stays pressed, pulsing, with a touch ring under it.
    private func press() {
        hand.removeAllActions()
        touchSpot.removeAllActions()
        hand.position = fingerSpot
        hand.alpha = 0
        hand.setScale(1.25)
        touchSpot.alpha = 0
        touchSpot.setScale(0.4)
        let down = SKAction.group([.fadeIn(withDuration: 0.2), .scale(to: 0.92, duration: 0.3)])
        down.timingMode = .easeIn
        hand.run(.sequence([
            down,
            .run { [weak self] in self?.touchDown() },
            .repeatForever(.sequence([.scale(to: 0.84, duration: 0.45), .scale(to: 0.92, duration: 0.45)])),
        ]))
    }

    private func touchDown() {
        touchSpot.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), .scale(to: 1, duration: 0.12)]),
            .repeatForever(.sequence([.scale(to: 1.3, duration: 0.45), .scale(to: 1, duration: 0.45)])),
        ]))
        let ripple = SKShapeNode(circleOfRadius: 24)
        ripple.strokeColor = .white
        ripple.lineWidth = 3
        ripple.position = fingerSpot
        ripple.zPosition = 1
        addChild(ripple)
        ripple.run(.sequence([.group([.scale(to: 2.4, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
    }

    /// The finger lifts off the water with a pop. If it isn't down already (a replay), it presses first.
    private func liftOff() {
        hand.removeAllActions()
        touchSpot.removeAllActions()
        var steps: [SKAction] = []
        if hand.alpha < 0.5 {
            hand.position = fingerSpot
            hand.setScale(1.25)
            steps += [
                .group([.fadeIn(withDuration: 0.15), .scale(to: 0.88, duration: 0.2)]),
                .run { [weak self] in
                    self?.touchSpot.alpha = 1
                    self?.touchSpot.setScale(1)
                },
                .wait(forDuration: 0.5),
            ]
        } else {
            steps.append(.scale(to: 0.84, duration: 0.15))
        }
        let lift = SKAction.group([
            .move(by: CGVector(dx: 12, dy: 34), duration: 0.35),
            .scale(to: 1.25, duration: 0.35),
            .sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.2)]),
        ])
        lift.timingMode = .easeOut
        steps += [.run { [weak self] in self?.pop() }, lift]
        hand.run(.sequence(steps))
    }

    /// The touch ring bursts into droplets as the finger leaves the water.
    private func pop() {
        touchSpot.removeAllActions()
        touchSpot.alpha = 1
        touchSpot.run(.group([.scale(to: 1.9, duration: 0.2), .fadeOut(withDuration: 0.2)]))
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * 2 * .pi
            let drop = SKShapeNode(circleOfRadius: 3.5)
            drop.fillColor = .white
            drop.strokeColor = .clear
            drop.position = fingerSpot
            drop.zPosition = 1
            addChild(drop)
            let fly = SKAction.move(by: CGVector(dx: cos(angle) * 46, dy: sin(angle) * 46), duration: 0.32)
            fly.timingMode = .easeOut
            drop.run(.sequence([
                .group([fly, .sequence([.wait(forDuration: 0.12), .fadeOut(withDuration: 0.2)])]),
                .removeFromParent(),
            ]))
        }
    }

    private func hideHand() {
        hand.removeAllActions()
        touchSpot.removeAllActions()
        hand.run(.fadeOut(withDuration: 0.2))
        touchSpot.run(.fadeOut(withDuration: 0.2))
    }

    private func showArrows(up: Bool) {
        arrowsPointUp = up
        arrows.zRotation = up ? 0 : .pi
        arrows.removeAllActions()
        arrows.run(.fadeIn(withDuration: 0.25))
    }
}
