import SpriteKit
import Testing
import UIKit
@testable import FishKit

/// Both apps draw with `ignoresSiblingOrder`: nodes at one global depth come out in any order on a phone (a parent
/// still before its children), however they were added. So a fish's parts that meet each need a depth of their own.
@MainActor
struct FishNodeDrawOrderTests {
    @Test func partsThatMeetHaveTheirOwnDepths() {
        var clashes: [String] = []
        for pattern in FishStyle.Pattern.allCases {
            for tail in FishStyle.Tail.allCases {
                for fin in [false, true] {
                    // Shut, opening (the mouth line and the open mouth both show), and wide.
                    for mouth in [0, 0.15, 1] as [CGFloat] {
                        let style = FishStyle(body: .orange, accent: .yellow, pattern: pattern, tail: tail,
                                              eyeScale: 1.25, hasDorsalFin: fin)
                        for isPlayer in [false, true] {
                            let fish = FishNode(style: style, isPlayer: isPlayer, tailPhase: 0)
                            fish.apply(radius: 30, facing: 1, tilt: 0, stretchX: 1, stretchY: 1, mouthOpen: mouth,
                                       time: 0, tailRate: 0)
                            clashes += Self.clashes(in: fish).map { "\(pattern) \(tail) fin \(fin) mouth \(mouth): \($0)" }
                        }
                    }
                }
            }
        }
        #expect(clashes.isEmpty, "\(clashes.joined(separator: "\n"))")
    }

    /// Two visible shapes, neither inside the other, at one depth, whose frames overlap, unless both paint one same
    /// color (stacked spots), which blends the same in either order.
    private static func clashes(in fish: FishNode) -> [String] {
        var parts: [(node: SKShapeNode, depth: CGFloat, frame: CGRect, name: String)] = []
        func walk(_ node: SKNode, depth: CGFloat, name: String) {
            guard !node.isHidden else { return }
            let depth = depth + (node === fish ? 0 : node.zPosition)
            if let shape = node as? SKShapeNode, shape.path != nil, let parent = shape.parent {
                let f = shape.frame
                let corners = [CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY), CGPoint(x: f.minX, y: f.maxY),
                               CGPoint(x: f.maxX, y: f.maxY)].map { parent.convert($0, to: fish) }
                let xs = corners.map(\.x), ys = corners.map(\.y)
                parts.append((shape, depth, CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!,
                                                   height: ys.max()! - ys.min()!), name))
            }
            for (index, child) in node.children.enumerated() { walk(child, depth: depth, name: "\(name).\(index)") }
        }
        walk(fish, depth: 0, name: "fish")
        var found: [String] = []
        for i in parts.indices {
            for j in parts.indices where j > i {
                let a = parts[i], b = parts[j]
                guard abs(a.depth - b.depth) < 0.0001, !a.node.inParentHierarchy(b.node), !b.node.inParentHierarchy(a.node)
                else { continue }
                let overlap = a.frame.intersection(b.frame)
                guard !overlap.isNull, overlap.width > 0.01, overlap.height > 0.01 else { continue }
                if let one = color(a.node), let other = color(b.node), one == other { continue }
                found.append("\(a.name) and \(b.name) at depth \(a.depth)")
            }
        }
        return found
    }

    /// The one color a shape paints, as RGB, if it paints just one.
    private static func color(_ shape: SKShapeNode) -> [Int]? {
        func rgb(_ color: UIColor) -> [Int]? {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return a > 0.001 ? [r, g, b].map { Int(($0 * 255).rounded()) } : nil
        }
        let painted = [rgb(shape.fillColor), shape.lineWidth > 0 ? rgb(shape.strokeColor) : nil].compactMap { $0 }
        return Set(painted).count == 1 ? painted[0] : nil
    }
}
