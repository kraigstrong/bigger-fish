import FishKit
import SpriteKit
import UIKit

/// Finds what SpriteKit may draw in either order on a phone. Every SpriteView draws with `ignoresSiblingOrder`, so
/// nodes are drawn by global depth alone: the sum of the zPositions from the root down. A parent still draws before
/// its children, but any other two nodes at one depth come out in whatever order the renderer likes. The simulator
/// keeps the order they were added; a phone doesn't, which is how the pause menu's backdrop once drew over its own
/// controls.
///
/// The audit walks a node tree as drawn (hidden subtrees skipped; alpha ignored, since what's faded out now fades in
/// later) and reports every two nodes, neither inside the other, at one depth, whose frames overlap on screen, where
/// at least one is a filled shape or a sprite, and where the order shows, unless an `Allowance` says why it doesn't
/// matter. Main thread only, as SpriteKit's nodes are.
enum DrawOrderAudit {
    /// A node that paints something, where it's drawn.
    struct Drawn {
        let node: SKNode
        /// Its global depth.
        let depth: CGFloat
        /// Its own frame (not its children's), in the root's coordinates.
        let frame: CGRect
        /// Where it is in the tree, for reading a report: each node's type (or name), with its index among its siblings.
        let path: String
        /// A filled shape or a sprite: something that covers what's under it.
        let isSolid: Bool
        /// The one color it paints, when it paints just one (its alpha aside); nil for several or a picture.
        let color: (red: CGFloat, green: CGFloat, blue: CGFloat)?
        let blendMode: SKBlendMode
    }

    /// Two nodes that may draw in either order.
    struct Clash: CustomStringConvertible {
        let first: Drawn
        let second: Drawn
        var description: String {
            "\(first.path) and \(second.path), both at depth \(Self.depth(first.depth)), overlapping at "
                + "\(Self.rect(first.frame.intersection(second.frame)))"
        }
        /// The clash without the indices that change as fish come and go, to tell one case from another.
        var kind: String { "\(Self.stripped(first.path)) / \(Self.stripped(second.path))" }

        private static func depth(_ z: CGFloat) -> String { String(format: "%g", Double(z)) }
        private static func rect(_ r: CGRect) -> String {
            String(format: "(%.0f, %.0f, %.0f × %.0f)", Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        }
        private static func stripped(_ path: String) -> String {
            path.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
        }
    }

    /// A clash that can't change what's on screen, and why.
    struct Allowance {
        let reason: String
        let allows: (Drawn, Drawn) -> Bool
    }

    static let standardAllowances: [Allowance] = [
        // Fish get their own depths by id (1 + id / 2, your fish 30), so two fish swimming past each other draw one
        // over the other; where a part of one meets a part of another at the same depth, which is on top for those
        // few frames is immaterial. This covers what a fish carries (its anglerfish lure, the tutorial's glow ring).
        Allowance(reason: "parts of two different fish swimming past each other") { first, second in
            guard let a = fish(containing: first.node), let b = fish(containing: second.node) else { return false }
            return a !== b
        },
        // Additive blending sums, and a sum is the same in any order.
        Allowance(reason: "both add their light") { first, second in
            first.blendMode == .add && second.blendMode == .add
        },
        // Two layers of one color blend to the same result in either order, whatever their alphas: c·a₂ + (c·a₁ +
        // d(1−a₁))(1−a₂) is symmetric in a₁ and a₂. So white text on a faint white tile, two specks of drifting white,
        // or a jellyfish's stacked halos can't come out differently.
        Allowance(reason: "both paint the same single color") { first, second in
            guard first.blendMode == .alpha, second.blendMode == .alpha, let a = first.color, let b = second.color else {
                return false
            }
            return abs(a.red - b.red) < 0.01 && abs(a.green - b.green) < 0.01 && abs(a.blue - b.blue) < 0.01
        },
    ]

    /// Everything under `root` that may draw in either order on a phone.
    static func clashes(in root: SKNode, allowing allowances: [Allowance] = standardAllowances) -> [Clash] {
        var drawn: [Drawn] = []
        collect(root, root: root, depth: 0, path: String(describing: type(of: root)), into: &drawn)
        // Only nodes at one depth can clash: sort by depth and look along runs of equal depths.
        drawn.sort { $0.depth < $1.depth }
        var clashes: [Clash] = []
        var start = 0
        while start < drawn.count {
            var end = start + 1
            while end < drawn.count && abs(drawn[end].depth - drawn[start].depth) < 0.0001 { end += 1 }
            for i in start..<end {
                for j in (i + 1)..<end {
                    let a = drawn[i], b = drawn[j]
                    guard a.isSolid || b.isSolid else { continue }
                    let overlap = a.frame.intersection(b.frame)
                    guard !overlap.isNull, overlap.width > 0.01, overlap.height > 0.01 else { continue }
                    // A parent draws before its children.
                    guard !a.node.inParentHierarchy(b.node), !b.node.inParentHierarchy(a.node) else { continue }
                    guard !allowances.contains(where: { $0.allows(a, b) }) else { continue }
                    clashes.append(Clash(first: a, second: b))
                }
            }
            start = end
        }
        return clashes
    }

    // MARK: Walking the tree

    private static func collect(_ node: SKNode, root: SKNode, depth: CGFloat, path: String, into drawn: inout [Drawn]) {
        guard !node.isHidden else { return }
        let depth = depth + (node === root ? 0 : node.zPosition)
        if node !== root, let paint = paint(of: node), let frame = frame(of: node, in: root),
           frame.width > 0.01, frame.height > 0.01 {
            drawn.append(Drawn(node: node, depth: depth, frame: frame, path: path, isSolid: paint.isSolid,
                               color: paint.color, blendMode: paint.blendMode))
        }
        for (index, child) in node.children.enumerated() {
            collect(child, root: root, depth: depth, path: path + " › " + label(child) + "[\(index)]", into: &drawn)
        }
    }

    private static func label(_ node: SKNode) -> String {
        let kind = String(describing: type(of: node))
        return node.name.map { "\(kind) “\($0)”" } ?? kind
    }

    /// Its own frame in the root's coordinates: the corners of its frame (in its parent's), carried up.
    private static func frame(of node: SKNode, in root: SKNode) -> CGRect? {
        guard let parent = node.parent else { return nil }
        let local = node.frame
        guard !local.isNull, !local.isEmpty else { return nil }
        let corners = [CGPoint(x: local.minX, y: local.minY), CGPoint(x: local.maxX, y: local.minY),
                       CGPoint(x: local.minX, y: local.maxY), CGPoint(x: local.maxX, y: local.maxY)]
            .map { parent === root ? $0 : parent.convert($0, to: root) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    // MARK: What a node paints

    private typealias Color = (red: CGFloat, green: CGFloat, blue: CGFloat)

    /// Whether a node paints anything, whether it covers what's under it, and its one color if it has just one.
    private static func paint(of node: SKNode) -> (isSolid: Bool, color: Color?, blendMode: SKBlendMode)? {
        switch node {
        case let shape as SKShapeNode:
            guard shape.path != nil else { return nil }
            let filled = visible(shape.fillColor)
            let stroked = visible(shape.strokeColor) && (shape.lineWidth > 0 || shape.glowWidth > 0)
            guard filled || stroked else { return nil }
            var colors: [Color?] = []
            if filled { colors.append(shape.fillTexture == nil ? rgb(shape.fillColor) : nil) }
            if stroked { colors.append(shape.strokeTexture == nil ? rgb(shape.strokeColor) : nil) }
            return (filled, single(colors), shape.blendMode)
        case let sprite as SKSpriteNode:
            guard sprite.size.width > 0, sprite.size.height > 0 else { return nil }
            guard let texture = sprite.texture else {
                return visible(sprite.color) ? (true, rgb(sprite.color), sprite.blendMode) : nil
            }
            let color: Color?
            if sprite.colorBlendFactor >= 0.999 { color = rgb(sprite.color) }
            else if sprite.colorBlendFactor <= 0.001 { color = uniformColor(of: texture) }
            else { color = nil }
            return (true, color, sprite.blendMode)
        case let label as SKLabelNode:
            if let attributed = label.attributedText {
                guard attributed.length > 0 else { return nil }
                var colors: [Color?] = []
                attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                    colors.append((value as? UIColor).map(rgb) ?? rgb(.black))
                }
                return (false, single(colors), label.blendMode)
            }
            guard let text = label.text, !text.isEmpty else { return nil }
            return (false, rgb(label.fontColor ?? .white), label.blendMode)
        default:
            return nil
        }
    }

    private static func visible(_ color: UIColor) -> Bool {
        var alpha: CGFloat = 0
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha > 0.001
    }

    private static func rgb(_ color: UIColor) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    private static func single(_ colors: [Color?]) -> Color? {
        guard let first = colors.first ?? nil else { return nil }
        for color in colors {
            guard let color, abs(color.red - first.red) < 0.01, abs(color.green - first.green) < 0.01,
                  abs(color.blue - first.blue) < 0.01 else { return nil }
        }
        return first
    }

    /// The one color a picture is drawn in (a white dot, a symbol), or nil if it has several (kelp, a gradient).
    private static func uniformColor(of texture: SKTexture) -> Color? {
        let key = ObjectIdentifier(texture)
        if let known = textureColors[key], known.texture === texture { return known.color }
        let image = texture.cgImage()
        let width = min(image.width, 64), height = min(image.height, 64)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var found: Color?
        var uniform = true
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { uniform = false; return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for index in stride(from: 0, to: pixels.count, by: 4) where uniform {
            let alpha = CGFloat(pixels[index + 3])
            // Faint edge pixels round too coarsely to say.
            guard alpha >= 64 else { continue }
            let color = (CGFloat(pixels[index]) / alpha, CGFloat(pixels[index + 1]) / alpha, CGFloat(pixels[index + 2]) / alpha)
            if let found {
                uniform = abs(color.0 - found.red) < 0.03 && abs(color.1 - found.green) < 0.03 && abs(color.2 - found.blue) < 0.03
            } else {
                found = color
            }
        }
        let result = uniform ? found : nil
        textureColors[key] = (texture, result)
        return result
    }
    /// Each texture's color, the texture kept so its address can't be reused by another.
    private static var textureColors: [ObjectIdentifier: (texture: SKTexture, color: Color?)] = [:]

    // MARK: Fish

    /// The fish a node is part of, if any.
    static func fish(containing node: SKNode) -> FishNode? {
        var current: SKNode? = node
        while let at = current {
            if let fish = at as? FishNode { return fish }
            current = at.parent
        }
        return nil
    }
}
