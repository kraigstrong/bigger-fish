import SpriteKit
import SwiftUI
import UIKit

// How far through a world you are, shown the same way everywhere: one pip per level, then a crown for conquering
// it. A playtester didn't know beating all ten levels was the goal, so the card before each level, the card after
// each win, and both maps all show the run and what's left of it.

/// A level's run (its world's ten main levels, or its Deep End) and which of them are cleared.
struct WorldProgress: Equatable {
    let world: ArcadeWorld
    /// The run the level belongs to, as level indices.
    let run: Range<Int>
    /// Which of the run's levels are cleared, in order.
    let cleared: [Bool]

    init(world: ArcadeWorld, level: Int, isCleared: (Int) -> Bool) {
        self.world = world
        let main = min(world.levelCount, ArcadeWorld.mainLevelCount)
        run = ArcadeWorld.isDeepEnd(level) ? main..<world.levelCount : 0..<main
        cleared = run.map(isCleared)
    }

    var isDeepEnd: Bool { run.lowerBound >= ArcadeWorld.mainLevelCount }
    var clearedCount: Int { cleared.filter { $0 }.count }
    var remaining: Int { run.count - clearedCount }
    var isConquered: Bool { remaining == 0 }
    /// What clearing the run conquers.
    var goal: String { isDeepEnd ? "The Deep End" : world.title }

    /// The line under the pips: the goal, and how far off it is.
    var caption: String {
        if isConquered { return "\(goal) conquered!" }
        if clearedCount == 0 { return "Clear all \(run.count) to conquer \(goal)" }
        return "\(remaining) more to conquer \(goal)"
    }
}

/// The run's pips and crown, on the card before a level and the card after a win. The level about to be played (or
/// the next one, after a win) pulses; a level just won for the first time fills in with a pop.
final class WorldProgressStrip: SKNode {
    static let pipRadius: CGFloat = 8.5
    static let pipSpacing: CGFloat = 25
    static let gold = SKColor(red: 1, green: 0.8, blue: 0.32, alpha: 1)

    private var pips: [SKShapeNode] = []
    private let crown: SKSpriteNode?
    private let color: SKColor
    private let progress: WorldProgress
    /// Width of the pips and crown, and the caption under them.
    let rowWidth: CGFloat
    let caption: SKLabelNode

    /// `earned`: a level just won for the first time, drawn empty until `playEarned` fills it in.
    init(progress: WorldProgress, next: Int?, earned: Int? = nil) {
        self.progress = progress
        color = progress.isDeepEnd ? Self.gold : progress.world.mapColor
        crown = SKSpriteNode.symbol("crown.fill", pointSize: 20, weight: .bold,
                                    color: progress.isConquered ? Self.gold : UIColor(white: 1, alpha: 0.4))
        let count = progress.run.count
        rowWidth = CGFloat(count - 1) * Self.pipSpacing + Self.pipRadius * 2 + 34
        caption = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        super.init()

        let left = -rowWidth / 2 + Self.pipRadius
        for (offset, index) in progress.run.enumerated() {
            let pip = SKShapeNode(circleOfRadius: Self.pipRadius)
            pip.position = CGPoint(x: left + CGFloat(offset) * Self.pipSpacing, y: 0)
            let done = progress.cleared[offset] && index != earned
            style(pip, cleared: done, isNext: index == next)
            addChild(pip)
            pips.append(pip)
        }
        if let crown {
            crown.position = CGPoint(x: rowWidth / 2 - 13, y: 1)
            addChild(crown)
        }
        caption.text = progress.caption
        caption.fontSize = 16
        caption.fontColor = SKColor(white: 1, alpha: 0.9)
        caption.verticalAlignmentMode = .center
        caption.position = CGPoint(x: 0, y: -27)
        addChild(caption)
        if let next { pulse(next) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Width the strip needs, caption included.
    var width: CGFloat { max(rowWidth, caption.frame.width) }

    /// Fills in the level just won: a pop, a ring bursting out, and a glint on the crown if that conquered the run.
    func playEarned(_ index: Int, after delay: TimeInterval) {
        guard let offset = progress.run.firstIndex(of: index).map({ progress.run.distance(from: progress.run.lowerBound, to: $0) }),
              pips.indices.contains(offset) else { return }
        let pip = pips[offset]
        run(.sequence([.wait(forDuration: delay), .run { [weak self] in
            guard let self else { return }
            style(pip, cleared: true, isNext: false)
            pip.setScale(1.7)
            let settle = SKAction.scale(to: 1, duration: 0.3)
            settle.timingMode = .easeOut
            pip.run(settle)
            let ring = SKShapeNode(circleOfRadius: Self.pipRadius)
            ring.strokeColor = .white
            ring.lineWidth = 2
            ring.position = pip.position
            addChild(ring)
            ring.run(.sequence([.group([.scale(to: 2.6, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        }]))
    }

    private func style(_ pip: SKShapeNode, cleared: Bool, isNext: Bool) {
        pip.fillColor = cleared ? color : .clear
        pip.strokeColor = cleared || isNext ? .white : SKColor(white: 1, alpha: 0.35)
        pip.lineWidth = cleared ? 2 : isNext ? 2.5 : 1.5
    }

    private func pulse(_ index: Int) {
        guard let offset = progress.run.firstIndex(of: index).map({ progress.run.distance(from: progress.run.lowerBound, to: $0) }),
              pips.indices.contains(offset) else { return }
        let grow = SKAction.scale(to: 1.25, duration: 0.5)
        grow.timingMode = .easeInEaseOut
        let shrink = SKAction.scale(to: 1, duration: 0.5)
        shrink.timingMode = .easeInEaseOut
        pips[offset].run(.repeatForever(.sequence([grow, shrink])))
    }
}

/// The run as a bar in the level map's header: a segment per level, then the crown.
struct WorldProgressBar: View {
    let progress: WorldProgress

    var body: some View {
        let color = progress.isDeepEnd ? DeepEndColors.gold : progress.world.color
        HStack(spacing: 4) {
            ForEach(Array(progress.cleared.enumerated()), id: \.offset) { _, cleared in
                Capsule().fill(cleared ? color : .white.opacity(0.16))
                    .overlay(Capsule().stroke(.white.opacity(cleared ? 0.7 : 0.3), lineWidth: 1))
                    .frame(width: 13, height: 9)
            }
            Image(systemName: "crown.fill").font(.system(size: 15, weight: .bold))
                .foregroundStyle(progress.isConquered ? DeepEndColors.gold : .white.opacity(0.4))
                .padding(.leading, 3)
            Text("\(progress.clearedCount)/\(progress.run.count)").font(.custom("AvenirNext-DemiBold", size: 14))
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.clearedCount) of \(progress.run.count) cleared. \(progress.caption)")
    }
}

extension SKSpriteNode {
    /// An SF Symbol as a sprite, drawn in `color`.
    static func symbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .regular,
                       color: UIColor = .white) -> SKSpriteNode? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let drawn = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        return SKSpriteNode(texture: SKTexture(image: drawn))
    }
}
