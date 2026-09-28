import CoreGraphics

/// A horizontally looping world: logical x always satisfies 0 <= x < width,
/// and distances are measured the short way around the seam.
public struct WrappedWorld {
    public let width: CGFloat

    public init(width: CGFloat) {
        self.width = width
    }

    public func wrap(_ x: CGFloat) -> CGFloat {
        let r = x.truncatingRemainder(dividingBy: width)
        let wrapped = r < 0 ? r + width : r
        return wrapped >= width ? 0 : wrapped
    }

    /// Shortest signed horizontal offset from `a` to `b`, in [-width/2, width/2).
    public func delta(from a: CGFloat, to b: CGFloat) -> CGFloat {
        var d = wrap(b - a)
        if d >= width / 2 { d -= width }
        return d
    }

    public func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(delta(from: a.x, to: b.x), b.y - a.y)
    }
}

public extension Comparable {
    func clamped(_ lower: Self, _ upper: Self) -> Self {
        min(max(self, lower), upper)
    }
}

/// SplitMix64 — tiny deterministic RNG so playtests see the same ecosystem every run.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
