import CoreGraphics

public enum SwallowTiming {
    /// Interpolates a (prey/predator radius ratio → seconds) curve, clamped at the ends.
    /// Nearly equal swallows take longer so the player feels how close the call was.
    public static func duration(sizeRatio: CGFloat, curve: [(ratio: CGFloat, seconds: CGFloat)]) -> CGFloat {
        guard let first = curve.first, let last = curve.last else { return 0.3 }
        if sizeRatio <= first.ratio { return first.seconds }
        if sizeRatio >= last.ratio { return last.seconds }
        for (lo, hi) in zip(curve, curve.dropFirst()) where sizeRatio <= hi.ratio {
            let t = (sizeRatio - lo.ratio) / (hi.ratio - lo.ratio)
            return lo.seconds + (hi.seconds - lo.seconds) * t
        }
        return last.seconds
    }
}
