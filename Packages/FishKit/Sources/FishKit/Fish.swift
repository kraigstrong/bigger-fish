import CoreGraphics

public enum FishState: Equatable {
    case swimming
    case swallowing(preyID: Int)
    case beingSwallowed(predatorID: Int)
    case removed
}

/// Simulation state for one fish. The player and AI fish share the same rules;
/// the AI steering fields are simply unused for the player.
public final class Fish {
    public let id: Int
    public let isPlayer: Bool
    public var position: CGPoint
    public var velocity = CGVector.zero
    /// Current rendered (and therefore gameplay) radius. Animates toward `targetRadius` after eating.
    public var radius: CGFloat
    public var targetRadius: CGFloat
    public var state: FishState = .swimming

    // Growth animation
    public var growFrom: CGFloat = 0
    public var growElapsed: CGFloat = .greatestFiniteMagnitude

    // AI steering
    public var heading: CGFloat = 1
    public var cruiseSpeed: CGFloat = 0
    public var targetY: CGFloat = 0
    public var retargetTimer: CGFloat = 0
    public var turnTimer: CGFloat = 0
    public var phase: CGFloat = 0

    // Visual-only state
    /// -1...1; sign is the direction the fish faces, magnitude < 1 while turning.
    public var facing: CGFloat = 1
    public var pulse: CGFloat = 0
    public var squash: CGFloat = 0
    public var shrink: CGFloat = 1
    public var struggle: CGFloat = 0
    /// 0 = closed, 1 = wide open.
    public var mouth: CGFloat = 0
    /// 0...1 chewing intensity during close-call swallows.
    public var chew: CGFloat = 0

    public init(id: Int, isPlayer: Bool, position: CGPoint, radius: CGFloat) {
        self.id = id
        self.isPlayer = isPlayer
        self.position = position
        self.radius = radius
        self.targetRadius = radius
    }

    public var isAlive: Bool {
        switch state {
        case .swimming, .swallowing: true
        case .beingSwallowed, .removed: false
        }
    }
}
