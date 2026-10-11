import FishKit
import SpriteKit
import SwiftUI
import UIKit

/// The credits, played, from Settings: a calm swim where every name in `Credits.json` is a fish to eat. Nothing can eat
/// you, there's no timer, and you can't fail. It moves as a level does (hold to rise, let go to fall, the camera easing
/// out as you grow) and eats as one does (the same swallow, sound, and haptic), but it's a small scene of its own: it has
/// no levels, sizes, or planner, and it's never given progress, best times, `ArcadeSave`, or analytics, so it can't
/// record anything. Names come in the file's order, one at a time, and one you miss comes round again. Eating one pops
/// its tag, says thanks, and grows you a little. After the last, a card thanks you for playing and leads back to Settings.
final class CreditsScene: SKScene, ObservableObject {
    private typealias T = GameTuning

    static let startTitle = "Credits"
    static let introLine = "Eat the names to say thanks"
    static let cardTitle = "Thanks for playing!"
    static let cardLine = "You thanked everyone."
    static let doneTitle = "Back to Settings"
    static func thanks(_ name: String) -> String { "Thanks, \(name)!" }

    let credits: ArcadeCredits
    /// Every name, in the order they swim in.
    let names: [ArcadeCredits.Credit]
    /// Reduce Motion: thanks that fade in place rather than float up, tags that fade rather than burst, and names that
    /// don't turn round and wander half as much.
    let reduceMotion: Bool
    /// Leaving, by Skip or the card's button: back to Settings.
    var onExit: (() -> Void)?
    /// Every name is eaten and the card is up (Skip steps aside for its button).
    @Published private(set) var finished = false
    /// The names eaten, in order (indexes into `names`).
    private(set) var eaten: [Int] = []

    /// A name in the water: its fish, how it swims, and its tag.
    private final class Swimmer {
        let index: Int
        let fish: Fish
        let node: FishNode
        let tag: CreditTag
        /// The height it keeps near: a share of the water it may swim in (0 its lowest, 1 its highest).
        let home: CGFloat
        let speed: CGFloat
        var turnAt: CGFloat
        var rng: SeededGenerator

        init(index: Int, fish: Fish, node: FishNode, tag: CreditTag, home: CGFloat, speed: CGFloat, turnAt: CGFloat,
             rng: SeededGenerator) {
            self.index = index
            self.fish = fish
            self.node = node
            self.tag = tag
            self.home = home
            self.speed = speed
            self.turnAt = turnAt
            self.rng = rng
        }
    }

    /// A name going down, as a level's swallow plays: drawn in to your mouth, shrinking, while you open wide.
    private struct Swallow {
        let prey: Swimmer
        var elapsed: CGFloat = 0
        let duration: CGFloat
        let ratio: CGFloat
        let startOffset: CGVector
    }

    /// Short animations, run on the scene's own clock rather than as SKActions, so they stop with it and draw the same in
    /// a test's frames.
    private struct Tween {
        let node: SKNode
        let start: CGFloat
        let seconds: CGFloat
        let removes: Bool
        let step: (SKNode, CGFloat) -> Void
    }

    private let settings: ArcadeSettings
    private var world = WrappedWorld(width: 1)
    private var player: Fish!
    private let playerNode = FishNode(style: .player, isPlayer: true, tailPhase: 0)
    private var swimmers: [Swimmer] = []
    /// Names still to come, in order: a missed one goes back to the front.
    private var waiting: [Int] = []
    /// Screens you've swum since the last name came in.
    private var sinceRelease = CGFloat.greatestFiniteMagnitude
    private var lastHome: CGFloat?
    private var swallow: Swallow?
    private var nextID = 1
    private var rng = SeededGenerator(seed: T.creditsSeed)

    // The camera and clock, as in a level: fixed steps, drawn between them.
    private var zoom: CGFloat = 1
    private var previousZoom: CGFloat = 1
    private var clock: CGFloat = 0
    private var accumulator: CGFloat = 0
    private var lastUpdate: TimeInterval?
    private var previous: [Int: FishPresentation] = [:]
    private var lastCameraX: CGFloat = 0

    private var holdTouches = Set<UITouch>()
    /// Until your first touch you glide on at your height, rather than sinking before you've done anything.
    private var touched = false
    /// The card before the swim, as a level has: nothing moves until your first tap.
    private var started = false
    private var startCard: SKNode?
    private var finishAt: CGFloat?
    private var finishedAt: CGFloat = 0
    private var hasLeft = false

    private let backgroundLayer = SKNode()
    private let fishLayer = SKNode()
    private let tagLayer = SKNode()
    private let dimNode = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
    private let uiLayer = SKNode()
    private var specks: [(node: SKSpriteNode, parallax: CGFloat, rise: CGFloat)] = []
    private var tweens: [Tween] = []
    private var card: SKNode?
    /// The card's button, in scene points.
    private var doneFrame = CGRect.zero
    private var isBuilt = false
    private let mealHaptic = UIImpactFeedbackGenerator(style: .light)
    private let finishHaptic = UINotificationFeedbackGenerator()

    init(credits: ArcadeCredits = .shipped, reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
         settings: ArcadeSettings = .shared) {
        self.credits = credits
        names = credits.names
        self.reduceMotion = reduceMotion
        self.settings = settings
        super.init(size: T.playfieldSize)
        scaleMode = .aspectFit
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // The water, as in a level: zooming out makes it taller in world points.
    private var screenWaterBottom: CGFloat { T.waterBottomMargin }
    private var screenWaterTop: CGFloat { size.height - T.waterTopMargin }
    private var waterCenter: CGFloat { (screenWaterBottom + screenWaterTop) / 2 }
    private var waterBottom: CGFloat { waterCenter - (waterCenter - screenWaterBottom) / zoom }
    private var waterTop: CGFloat { waterCenter + (screenWaterTop - waterCenter) / zoom }
    private var playerSpeed: CGFloat { size.width / T.creditsCrossSeconds / zoom }
    private var isHolding: Bool {
        #if DEBUG
        if let debugHolding { return debugHolding }
        #endif
        return !holdTouches.isEmpty
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        if !isBuilt { build() }
        mealHaptic.prepare()
        // Awake while you swim, as in a level; the card lets the phone sleep.
        UIApplication.shared.isIdleTimerDisabled = !finished && !hasLeft
        configureAccessibility()
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .screenChanged, argument: accessibilityElements?.first)
        }
    }

    override func willMove(from view: SKView) {
        UIApplication.shared.isIdleTimerDisabled = false
        super.willMove(from: view)
    }

    private func build() {
        isBuilt = true
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.04, green: 0.15, blue: 0.32, alpha: 1)
        backgroundLayer.zPosition = 0
        fishLayer.zPosition = 10
        // Over every fish, yours included (the fish layer's 10, plus 30).
        tagLayer.zPosition = 60
        dimNode.zPosition = 90
        uiLayer.zPosition = 100
        for layer in [backgroundLayer, fishLayer, tagLayer, dimNode, uiLayer] { addChild(layer) }
        layoutBackdrop()
        world = WrappedWorld(width: size.width * T.creditsWorldScreens)
        player = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: waterCenter), radius: T.baseRadius)
        player.velocity = CGVector(dx: playerSpeed, dy: 0)
        playerNode.zPosition = 30
        fishLayer.addChild(playerNode)
        waiting = Array(names.indices)
        releaseNext()
        showStartCard()
        lastCameraX = player.position.x
        capture()
        render()
    }

    /// The level's water: its gradient, the surface line, and drifting specks.
    private func layoutBackdrop() {
        let gradient = SKSpriteNode(texture: WaterTextures.gradient())
        gradient.anchorPoint = .zero
        gradient.size = size
        backgroundLayer.addChild(gradient)
        let surface = SKSpriteNode(color: SKColor(white: 1, alpha: 0.22), size: CGSize(width: size.width, height: 2))
        surface.anchorPoint = .zero
        surface.position = CGPoint(x: 0, y: screenWaterTop + 4)
        surface.zPosition = 1
        backgroundLayer.addChild(surface)
        var speckRNG = SeededGenerator(seed: 7)
        let dot = WaterTextures.dot()
        for _ in 0..<55 {
            let parallax = CGFloat.random(in: 0.15...0.7, using: &speckRNG)
            let node = SKSpriteNode(texture: dot)
            let d = 1.5 + parallax * 4
            node.size = CGSize(width: d, height: d)
            node.alpha = 0.12 + parallax * 0.3
            node.position = CGPoint(x: CGFloat.random(in: 0...size.width, using: &speckRNG),
                                    y: CGFloat.random(in: 0...size.height, using: &speckRNG))
            node.zPosition = 1
            backgroundLayer.addChild(node)
            specks.append((node, parallax, CGFloat.random(in: 4...14, using: &speckRNG)))
        }
        dimNode.anchorPoint = .zero
        dimNode.size = size
        dimNode.alpha = 0
    }

    /// The card before the swim, drawn as a level's: the title, the one line, and "Tap to start", beside your fish.
    private func showStartCard() {
        let card = SKNode()
        let title = Self.label(Self.startTitle, size: 40, heavy: true)
        let line = Self.label(Self.introLine, size: 19, heavy: false)
        let start = Self.label("Tap to start", size: 22, heavy: true)
        let height: CGFloat = 180, width = max(title.frame.width, line.frame.width, start.frame.width) + 70
        let panel = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        panel.fillColor = SKColor(white: 0, alpha: 0.3)
        panel.strokeColor = .clear
        // Under its text: the scene ignores sibling order, so the same depth could draw it over them.
        panel.zPosition = -1
        card.addChild(panel)
        title.position = CGPoint(x: 0, y: height / 2 - 45)
        line.position = CGPoint(x: 0, y: height / 2 - 90)
        start.position = CGPoint(x: 0, y: -height / 2 + 30)
        for text in [title, line, start] { card.addChild(text) }
        card.position = CGPoint(x: size.width * 0.63, y: size.height / 2)
        card.alpha = 0
        card.run(.fadeIn(withDuration: 0.25))
        uiLayer.addChild(card)
        startCard = card
    }

    /// Your first tap: the card goes and the swim begins.
    private func start() {
        guard !started else { return }
        started = true
        startCard?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        startCard = nil
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt else { return }
        let elapsed = min(max(lastUpdate.map { CGFloat(currentTime - $0) } ?? 0, 0), T.maximumFrameElapsed)
        lastUpdate = currentTime
        advance(elapsed)
        render(elapsed: elapsed)
    }

    private func advance(_ elapsed: CGFloat) {
        // Still on the start card: nothing swims yet.
        guard started else { return }
        accumulator += elapsed
        while accumulator + 1e-10 >= T.simulationStep {
            accumulator = max(0, accumulator - T.simulationStep)
            capture()
            simulate(T.simulationStep)
        }
    }

    private func simulate(_ dt: CGFloat) {
        clock += dt
        updateZoom(dt)
        movePlayer(dt)
        for s in swimmers where s.fish.state == .swimming { swim(s, dt) }
        advanceSwallow(dt)
        advanceGrowth(dt)
        guard !finished else { return }
        sinceRelease += dt / T.creditsCrossSeconds
        catchNames()
        sendMissedRound()
        releaseNext()
        if waiting.isEmpty && swimmers.isEmpty && swallow == nil {
            let at = finishAt ?? clock + T.creditsCardDelay
            finishAt = at
            if clock >= at { finish() }
        }
    }

    /// Out as you grow, as in a level.
    private func updateZoom(_ dt: CGFloat) {
        let growth = player.radius / (T.baseRadius * T.zoomStartSize)
        let target = growth > 1 ? max(T.minZoom, pow(1 / growth, T.zoomExponent)) : 1
        zoom += (target - zoom) * min(1, dt * T.zoomEase)
    }

    private func movePlayer(_ dt: CGFloat) {
        let p = player!
        let minY = waterBottom + p.radius * 0.95, maxY = waterTop - p.radius * 0.95
        var y = p.position.y, vy = p.velocity.dy
        if touched && !finished {
            (y, vy) = PlayerMotion.step(y: y, vy: vy, holding: isHolding, dt: dt, minY: minY, maxY: maxY, zoom: zoom,
                                        tuning: T.motion)
        } else {
            // Before your first touch, and under the closing card, you glide on at your height.
            vy -= vy * min(1, dt * 4)
            y = (y + vy * dt).clamped(minY, maxY)
        }
        p.velocity = CGVector(dx: playerSpeed, dy: vy)
        p.position = CGPoint(x: world.wrap(p.position.x + playerSpeed * dt), y: y)
        p.facing = 1
    }

    // MARK: - Names

    /// How far ahead of you a fish is, in screens (negative: behind).
    private func screensAhead(_ f: Fish) -> CGFloat {
        world.delta(from: player.position.x, to: f.position.x) * zoom / size.width
    }

    /// Where a name of `radius` may swim (world heights): above `creditsLowest` of the water, and low enough that its tag
    /// fits under the top of the screen at this zoom.
    private func swimBand(_ radius: CGFloat) -> ClosedRange<CGFloat> {
        let low = max(waterBottom + radius, waterBottom + T.creditsLowest * (waterTop - waterBottom))
        let room = size.height - T.creditsTagTopMargin - CreditTag.height - T.creditsTagGap - radius * zoom
        let high = min(waterTop - radius, waterCenter + (room - waterCenter) / zoom)
        return low...max(low, high)
    }

    /// The next name comes in once you've swum `creditsSpacing` screens since the last, so you meet them one at a time;
    /// but not while one you've just passed is still in the water: once it's missed, it comes round first, keeping the
    /// file's order.
    private func releaseNext() {
        guard let next = waiting.first, swimmers.count < T.creditsInWater, sinceRelease >= T.creditsSpacing,
              swimmers.allSatisfy({ $0.fish.state != .swimming || screensAhead($0.fish) >= 0 }) else { return }
        waiting.removeFirst()
        release(next)
    }

    /// A name comes in just off screen ahead, a little smaller than you, somewhere new in the water.
    private func release(_ index: Int) {
        let id = nextID
        nextID += 1
        sinceRelease = 0
        // First a little below the middle, then each well above or below the last, so you swim to it.
        var home: CGFloat = 0.3
        if let last = lastHome {
            let shift = CGFloat.random(in: 0.35...0.7, using: &rng)
            home = (last < 0.5 ? last + shift : last - shift).clamped(0, 1)
        }
        lastHome = home
        let f = Fish(id: id, isPlayer: false, position: .zero, radius: player.targetRadius * T.creditsNameSize)
        let band = swimBand(f.radius)
        f.position = CGPoint(x: world.wrap(player.position.x + T.creditsEnterAhead * size.width / zoom),
                             y: band.lowerBound + home * (band.upperBound - band.lowerBound))
        f.heading = Double.random(in: 0..<1, using: &rng) < T.creditsAtYouShare ? -1 : 1
        f.facing = f.heading
        let speed = CGFloat.random(in: T.creditsSwimSpeed, using: &rng)
        f.velocity = CGVector(dx: f.heading * speed, dy: 0)
        f.targetY = f.position.y
        f.phase = CGFloat(id) * 1.7
        // Each name looks the same every time it comes round.
        var look = SeededGenerator(seed: T.creditsSeed &+ UInt64(index + 1) &* 7_919)
        let node = FishNode(style: FishStyle.random(using: &look), isPlayer: false, tailPhase: f.phase)
        node.zPosition = 1 + CGFloat(id % 40) * 0.5
        fishLayer.addChild(node)
        let tag = CreditTag(names[index])
        tagLayer.addChild(tag)
        var movement = FreeSwim.movementGenerator(ecosystemSeed: T.creditsSeed, id: id)
        let turnAt = clock + CGFloat.random(in: T.creditsTurnSeconds, using: &movement)
        swimmers.append(Swimmer(index: index, fish: f, node: node, tag: tag, home: home, speed: speed, turnAt: turnAt,
                                rng: movement))
        previous[id] = FishPresentation(f)
        #if DEBUG
        debugReleases.append(index)
        #endif
    }

    /// A name swims like the tutorial's free swimmers: on at its own pace, a little faster and slower as it goes,
    /// wandering gently up and down near its height, and now and then turning round (its tag stays as it is).
    private func swim(_ s: Swimmer, _ dt: CGFloat) {
        let f = s.fish
        let band = swimBand(f.radius)
        let home = band.lowerBound + s.home * (band.upperBound - band.lowerBound)
        let calm: CGFloat = reduceMotion ? 0.5 : 1
        let reach = T.creditsWander * calm * (waterTop - waterBottom)
        let low = max(band.lowerBound, home - reach), high = max(low, min(band.upperBound, home + reach))
        if !reduceMotion && clock >= s.turnAt {
            f.heading *= -1
            s.turnAt = clock + CGFloat.random(in: T.creditsTurnSeconds, using: &s.rng)
        }
        let pulse = reduceMotion ? 0 : 0.2 * sin(clock * 0.9 + f.phase)
        let vx = f.velocity.dx + (f.heading * s.speed * (1 + pulse) - f.velocity.dx) * min(1, dt * 1.5)
        f.retargetTimer -= dt
        if f.retargetTimer <= 0 || abs(f.targetY - f.position.y) < 4 {
            f.targetY = CGFloat.random(in: low...high, using: &s.rng)
            f.retargetTimer = CGFloat.random(in: 1.2...2.4, using: &s.rng)
        }
        f.targetY = f.targetY.clamped(low, high)
        let wander = T.creditsWanderSpeed * calm
        let desiredVY = ((f.targetY - f.position.y) * 0.9).clamped(-wander, wander)
            + (reduceMotion ? 0 : sin(clock * 1.3 + f.phase) * 6)
        let vy = f.velocity.dy + (desiredVY - f.velocity.dy) * min(1, dt * 2)
        FreeSwim.integrate(f, velocity: CGVector(dx: vx, dy: vy), dt: dt, minY: band.lowerBound, maxY: band.upperBound,
                           world: world)
        // A turn reads as a smooth flip through side-on.
        let direction: CGFloat = abs(f.velocity.dx) > 2 ? (f.velocity.dx >= 0 ? 1 : -1) : f.heading
        f.facing += (direction - f.facing) * min(1, dt * T.freeEncounterFacingRate)
    }

    /// One you've passed swims on round the reef and comes in again, next in line.
    private func sendMissedRound() {
        let missed = swimmers.filter { $0.fish.state == .swimming && screensAhead($0.fish) < -T.creditsMissedBehind }
        guard !missed.isEmpty else { return }
        for s in missed { remove(s) }
        waiting.insert(contentsOf: missed.map(\.index), at: 0)
    }

    private func remove(_ s: Swimmer) {
        swimmers.removeAll { $0 === s }
        s.node.removeFromParent()
        s.tag.removeFromParent()
        previous[s.fish.id] = nil
    }

    // MARK: - Eating

    /// Nothing eats you here: touch a name and it's yours.
    private func catchNames() {
        guard swallow == nil, player.state == .swimming else { return }
        for s in swimmers where s.fish.state == .swimming {
            let dx = world.delta(from: player.position.x, to: s.fish.position.x), dy = s.fish.position.y - player.position.y
            let reach = (player.radius + s.fish.radius) * T.collisionScale
            guard dx * dx + dy * dy < reach * reach else { continue }
            player.state = .swallowing(preyID: s.fish.id)
            s.fish.state = .beingSwallowed(predatorID: player.id)
            let ratio = s.fish.radius / player.radius
            swallow = Swallow(prey: s, duration: SwallowTiming.duration(sizeRatio: ratio, curve: T.swallowDurationCurve),
                              ratio: ratio, startOffset: CGVector(dx: dx, dy: dy))
            s.node.zPosition = playerNode.zPosition - 0.25
            return
        }
    }

    /// The level's swallow: the name is drawn in to your mouth, shrinking, and a close call makes you chew.
    private func advanceSwallow(_ dt: CGFloat) {
        guard var s = swallow else { return }
        s.elapsed += dt
        swallow = s
        let prey = s.prey.fish
        let t = min(1, s.elapsed / s.duration), eased = t * t * (3 - 2 * t)
        let mouth = CGVector(dx: (player.facing >= 0 ? 1 : -1) * player.radius * 1.05, dy: -player.radius * 0.1)
        prey.position = CGPoint(x: world.wrap(player.position.x + s.startOffset.dx + (mouth.dx - s.startOffset.dx) * eased),
                                y: player.position.y + s.startOffset.dy + (mouth.dy - s.startOffset.dy) * eased)
        prey.shrink = 1 - 0.9 * eased
        let closeness = ((s.ratio - 0.7) / 0.3).clamped(0, 1)
        prey.struggle = closeness * (1 - t)
        player.squash = closeness * 0.09 * sin(s.elapsed * 30) * (1 - t)
        player.chew = closeness * (1 - t)
        if t >= 1 { eat(s.prey) }
    }

    /// Swallowed: its tag pops with the eat sound and a tap, thanks float up, and you grow a little.
    private func eat(_ s: Swimmer) {
        swallow = nil
        swimmers.removeAll { $0 === s }
        s.node.removeFromParent()
        previous[s.fish.id] = nil
        eaten.append(s.index)
        player.state = .swimming
        player.squash = 0
        player.chew = 0
        player.targetRadius = GameRules.grownRadius(predator: player.targetRadius, prey: s.fish.radius, efficiency: T.creditsGrowth)
        player.growFrom = player.radius
        player.growElapsed = 0
        player.pulse = T.pulseDuration
        play(.eat)
        buzz(.meal)
        // Where it went down, on screen.
        let mouth = CGPoint(x: size.width * T.playerScreenX + world.delta(from: player.position.x, to: s.fish.position.x) * zoom,
                            y: waterCenter + (s.fish.position.y - waterCenter) * zoom)
        s.tag.position = tagSpot(over: mouth, radius: s.fish.radius * s.fish.shrink * zoom)
        pop(s.tag)
        let name = names[s.index].name
        thank(name, at: CGPoint(x: s.tag.position.x, y: s.tag.position.y + CreditTag.pointer + CreditTag.bubbleHeight / 2))
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: Self.thanks(name)) }
    }

    private func advanceGrowth(_ dt: CGFloat) {
        let p = player!
        if p.growElapsed < T.growDuration {
            p.growElapsed += dt
            let t = min(1, p.growElapsed / T.growDuration)
            p.radius = p.growFrom + (p.targetRadius - p.growFrom) * (1 - pow(1 - t, 3))
        }
        if p.pulse > 0 { p.pulse = max(0, p.pulse - dt) }
        if case .swallowing = p.state {
            p.mouth = min(1, p.mouth + dt / T.mouthOpenSeconds)
        } else {
            p.mouth = max(0, p.mouth - dt / T.mouthCloseSeconds)
        }
    }

    /// The tag bursts into droplets, as the tutorial's touch ring does (with Reduce Motion, it just fades).
    private func pop(_ tag: CreditTag) {
        let center = CGPoint(x: tag.position.x, y: tag.position.y + CreditTag.pointer + CreditTag.bubbleHeight / 2)
        animate(tag, over: T.creditsPopSeconds, removing: true) { [reduceMotion] node, t in
            node.alpha = 1 - t
            if !reduceMotion { node.setScale(1 + 0.25 * t) }
        }
        guard !reduceMotion else { return }
        for i in 0..<10 {
            let angle = CGFloat(i) / 10 * 2 * .pi
            let drop = SKShapeNode(circleOfRadius: 3.5)
            drop.fillColor = .white
            drop.strokeColor = .clear
            tagLayer.addChild(drop)
            // From the bubble's edge, outward.
            let reach = CGVector(dx: cos(angle) * (tag.width / 2 + 18), dy: sin(angle) * (CreditTag.bubbleHeight / 2 + 18))
            animate(drop, over: 0.34, removing: true) { node, t in
                let out = 0.75 + 0.25 * (1 - (1 - t) * (1 - t))
                node.position = CGPoint(x: center.x + reach.dx * out, y: center.y + reach.dy * out)
                node.alpha = t < 0.35 ? 1 : 1 - (t - 0.35) / 0.65
            }
        }
    }

    /// "Thanks, Chad H!" floats up from where the name was as its tag goes, and fades (in place, with Reduce Motion).
    private func thank(_ name: String, at point: CGPoint) {
        let line = SKNode()
        let text = Self.label(Self.thanks(name), size: T.creditsThanksFont, heavy: true)
        let shadow = Self.label(Self.thanks(name), size: T.creditsThanksFont, heavy: true)
        shadow.fontColor = SKColor(white: 0, alpha: 0.35)
        shadow.position = CGPoint(x: 1.5, y: -1.5)
        shadow.zPosition = -1
        line.addChild(shadow)
        line.addChild(text)
        line.name = "thanks"
        let rise = reduceMotion ? 0 : T.creditsThanksRise
        let half = text.frame.width / 2 + 12
        let start = CGPoint(x: point.x.clamped(half, size.width - half), y: min(point.y, size.height - 24 - rise))
        uiLayer.addChild(line)
        animate(line, after: T.creditsPopSeconds, over: T.creditsThanksSeconds, removing: true) { node, t in
            node.position = CGPoint(x: start.x, y: start.y + rise * (1 - (1 - t) * (1 - t)))
            node.alpha = t < 0.1 ? t / 0.1 : t < 0.5 ? 1 : 1 - (t - 0.5) / 0.5
        }
    }

    // MARK: - The end

    /// After the last name: the clear chime, a success tap, and the card.
    private func finish() {
        finished = true
        finishedAt = clock
        holdTouches.removeAll()
        if view != nil { UIApplication.shared.isIdleTimerDisabled = false }
        play(.clear)
        buzz(.finish)
        animate(dimNode, over: 0.6) { node, t in node.alpha = 0.35 * t }
        showCard()
        configureAccessibility()
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .screenChanged, argument: accessibilityElements?.first)
        }
    }

    /// "Thanks for playing!", as a passed level's card looks, with one button: back to Settings.
    private func showCard() {
        let card = SKNode()
        let width: CGFloat = 430, height: CGFloat = 210
        let backing = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        backing.fillColor = SKColor(red: 0.10, green: 0.52, blue: 0.30, alpha: 0.92)
        backing.strokeColor = SKColor(white: 1, alpha: 0.6)
        backing.lineWidth = 2
        card.addChild(backing)
        let heading = Self.label(Self.cardTitle, size: 32, heavy: true)
        heading.position = CGPoint(x: 0, y: 62)
        card.addChild(heading)
        let line = Self.label(Self.cardLine, size: 19, heavy: false)
        line.position = CGPoint(x: 0, y: 22)
        card.addChild(line)
        let button = CGRect(x: -160, y: -74, width: 320, height: 58)
        let pill = SKShapeNode(rect: button, cornerRadius: button.height / 2)
        pill.fillColor = .white
        pill.strokeColor = .clear
        card.addChild(pill)
        let caption = Self.label(Self.doneTitle, size: 23, heavy: true)
        caption.fontColor = SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1)
        caption.position = CGPoint(x: button.midX, y: button.midY)
        card.addChild(caption)
        card.position = CGPoint(x: size.width / 2, y: size.height / 2)
        doneFrame = button.offsetBy(dx: card.position.x, dy: card.position.y)
        uiLayer.addChild(card)
        self.card = card
        animate(card, after: 0.2, over: 0.3) { [reduceMotion] node, t in
            node.alpha = t
            node.setScale(reduceMotion ? 1 : 0.92 + 0.08 * t)
        }
    }

    /// Back to Settings: by Skip at any time, or the card's button. Once.
    func leave() {
        guard !hasLeft else { return }
        hasLeft = true
        holdTouches.removeAll()
        if view != nil { UIApplication.shared.isIdleTimerDisabled = false }
        onExit?()
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if finished {
                tapCard(at: touch.location(in: self))
                continue
            }
            start()
            touched = true
            holdTouches.insert(touch)
        }
    }

    /// The card's button, after a moment, so a finger still down from the last name doesn't leave at once.
    private func tapCard(at point: CGPoint) {
        guard clock - finishedAt >= T.restartDelay, doneFrame.insetBy(dx: -10, dy: -10).contains(point) else { return }
        leave()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { holdTouches.subtract(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { holdTouches.subtract(touches) }

    // MARK: - Settings: sound, vibration

    enum Haptic { case meal, finish }

    private func buzz(_ haptic: Haptic) {
        guard settings.vibrationOn else { return }
        #if DEBUG
        debugHaptics.append(haptic)
        #endif
        switch haptic {
        case .meal: mealHaptic.impactOccurred(intensity: T.mealHapticIntensity)
        case .finish: finishHaptic.notificationOccurred(.success)
        }
    }

    private func play(_ effect: ArcadeAudio.Effect) {
        guard settings.soundEffectsOn else { return }
        #if DEBUG
        debugSounds.append(effect)
        #endif
        ArcadeAudio.shared.play(effect)
    }

    // MARK: - VoiceOver

    /// VoiceOver reads every name (Skip is beside it, in `CreditsView`); at the end, the card and its button.
    private func configureAccessibility() {
        guard let view else { return }
        view.isAccessibilityElement = false
        isAccessibilityElement = false
        func screen(_ rect: CGRect) -> CGRect {
            let lower = convertPoint(toView: CGPoint(x: rect.minX, y: rect.minY))
            let upper = convertPoint(toView: CGPoint(x: rect.maxX, y: rect.maxY))
            return UIAccessibility.convertToScreenCoordinates(
                CGRect(x: min(lower.x, upper.x), y: min(lower.y, upper.y), width: abs(upper.x - lower.x), height: abs(upper.y - lower.y)),
                in: view)
        }
        let list = UIAccessibilityElement(accessibilityContainer: self)
        list.accessibilityLabel = credits.spokenList
        list.accessibilityTraits = .staticText
        list.accessibilityFrame = screen(CGRect(origin: .zero, size: size))
        guard finished, let card else {
            accessibilityElements = [list]
            return
        }
        let thanks = UIAccessibilityElement(accessibilityContainer: self)
        thanks.accessibilityLabel = "\(Self.cardTitle) \(Self.cardLine)"
        thanks.accessibilityTraits = .header
        thanks.accessibilityFrame = screen(card.calculateAccumulatedFrame())
        let done = ArcadeResultAccessibilityElement(accessibilityContainer: self)
        done.accessibilityLabel = Self.doneTitle
        done.accessibilityTraits = .button
        done.accessibilityFrame = screen(doneFrame)
        done.activate = { [weak self] in
            self?.leave()
            return self != nil
        }
        accessibilityElements = [thanks, done, list]
    }

    // MARK: - Drawing

    private func capture() {
        previous[player.id] = FishPresentation(player)
        for s in swimmers { previous[s.fish.id] = FishPresentation(s.fish) }
        previousZoom = zoom
    }

    private func render(elapsed: CGFloat = 0) {
        let fraction = (accumulator / T.simulationStep).clamped(0, 1)
        let zoom = previousZoom + (self.zoom - previousZoom) * fraction
        let time = clock + accumulator
        let cameraX = pose(player, fraction).position.x
        draw(player, playerNode, cameraX: cameraX, zoom: zoom, fraction: fraction, time: time)
        for s in swimmers {
            let pose = draw(s.fish, s.node, cameraX: cameraX, zoom: zoom, fraction: fraction, time: time)
            // Over its fish, upright and its own size on screen at any zoom: it never mirrors or tilts as the fish turns.
            s.tag.position = tagSpot(over: s.node.position, radius: pose.radius * pose.shrink * zoom)
            s.tag.isHidden = s.tag.position.x < -s.tag.width || s.tag.position.x > size.width + s.tag.width
        }
        runTweens(time: time)
        let cameraDelta = world.delta(from: lastCameraX, to: cameraX) * zoom
        lastCameraX = cameraX
        for speck in specks {
            var p = speck.node.position
            p.x -= cameraDelta * speck.parallax
            p.y += speck.rise * elapsed
            if p.x < -8 { p.x += size.width + 16 } else if p.x > size.width + 8 { p.x -= size.width + 16 }
            if p.y > size.height + 8 { p.y = -8 }
            speck.node.position = p
        }
    }

    /// Where a tag's point goes, over a fish drawn at `fish` with `radius` on screen.
    private func tagSpot(over fish: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: fish.x, y: fish.y + radius + T.creditsTagGap)
    }

    private func pose(_ f: Fish, _ fraction: CGFloat) -> FishPresentation {
        let current = FishPresentation(f)
        return previous[f.id]?.interpolated(to: current, fraction: fraction, world: world) ?? current
    }

    /// Drawn as a level draws its fish: squash and stretch, tilt, the mouth, and the tail.
    @discardableResult
    private func draw(_ f: Fish, _ node: FishNode, cameraX: CGFloat, zoom: CGFloat, fraction: CGFloat, time: CGFloat) -> FishPresentation {
        let pose = pose(f, fraction)
        let x = size.width * T.playerScreenX + world.delta(from: cameraX, to: pose.position.x) * zoom
        node.position = CGPoint(x: x, y: waterCenter + (pose.position.y - waterCenter) * zoom)
        let margin = pose.radius * zoom * 3
        node.isHidden = x < -margin || x > size.width + margin
        var stretch: CGFloat = 1
        if pose.pulse > 0 { stretch += sin((1 - pose.pulse / T.pulseDuration) * .pi) * T.pulseAmount }
        let stretchX = stretch * (1 + pose.squash) * pose.shrink, stretchY = stretch * (1 - pose.squash) * pose.shrink
        let rawTilt = f.isPlayer ? pose.velocity.dy * zoom / T.motion.maxRiseSpeed * T.motion.maxTilt
                                 : pose.velocity.dy / T.creditsWanderSpeed * T.aiMaxTilt
        let tilt = rawTilt.clamped(-T.motion.maxTilt, T.motion.maxTilt) * (pose.facing >= 0 ? 1 : -1)
            + pose.struggle * sin(time * 45) * 0.35
        let mouth = pose.mouth * (1 - 0.35 * pose.chew * (0.5 + 0.5 * sin(time * 38)))
        node.apply(radius: pose.radius * zoom, facing: pose.facing, tilt: tilt, stretchX: stretchX, stretchY: stretchY,
                   mouthOpen: mouth, time: time, tailRate: f.isPlayer ? 14 : 9)
        return pose
    }

    private func animate(_ node: SKNode, after delay: CGFloat = 0, over seconds: CGFloat, removing: Bool = false,
                         _ step: @escaping (SKNode, CGFloat) -> Void) {
        step(node, 0)
        tweens.append(Tween(node: node, start: clock + delay, seconds: seconds, removes: removing, step: step))
    }

    private func runTweens(time: CGFloat) {
        var running: [Tween] = []
        for tween in tweens {
            let t = ((time - tween.start) / tween.seconds).clamped(0, 1)
            tween.step(tween.node, t)
            if t < 1 { running.append(tween) } else if tween.removes { tween.node.removeFromParent() }
        }
        tweens = running
    }

    static func label(_ text: String, size: CGFloat, heavy: Bool) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: heavy ? "AvenirNext-Heavy" : "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = size
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    // MARK: - Tests and previews

    #if DEBUG
    private var debugHolding: Bool?
    /// Every haptic and sound played, in order (only those the settings let through).
    private(set) var debugHaptics: [Haptic] = []
    private(set) var debugSounds: [ArcadeAudio.Effect] = []
    /// Each name as it came into the water: one that shows up twice was missed and came round.
    private(set) var debugReleases: [Int] = []
    var debugPlayer: Fish { player }
    var debugZoom: CGFloat { zoom }
    var debugClock: CGFloat { clock }
    var debugEatenNames: [String] { eaten.map { names[$0].name } }
    /// The names in the water: which, its fish, and its tag (where it's drawn, after `debugRender`).
    var debugSwimmers: [(index: Int, fish: Fish, tag: CreditTag)] { swimmers.map { ($0.index, $0.fish, $0.tag) } }
    /// The "Thanks, …!" lines showing, and where.
    var debugThanks: [SKNode] { uiLayer.children.filter { $0.name == "thanks" } }
    var debugCardShowing: Bool { card?.parent != nil }

    /// Whether the start card is still up, waiting for the first tap.
    var debugWaitingToStart: Bool { !started }
    /// Moves time on, the swim started as a first tap would.
    func debugAdvance(seconds: CGFloat) {
        start()
        for _ in 0..<Int((seconds / T.simulationStep).rounded(.up)) { advance(T.simulationStep) }
    }
    func debugRender() { render() }
    /// Taps the card's button, as a finger would, `after` seconds into the card.
    func debugTapDone(after seconds: CGFloat = T.restartDelay) {
        debugAdvance(seconds: max(0, finishedAt + seconds - clock) + T.simulationStep)
        tapCard(at: CGPoint(x: doneFrame.midX, y: doneFrame.midY))
    }

    /// How the test player plays: going for each name, never touching the screen, holding and letting go at random, or
    /// keeping away from the names until `until` seconds in, then going for them.
    enum DebugPlayer { case eater, passive, flailing, dodger(until: CGFloat) }

    /// Plays on the real controls until the card comes up or `limit` seconds pass. The eater heads for the nearest name
    /// ahead of it. Returns whether it reached the card, and when.
    @discardableResult
    func debugPlay(_ style: DebugPlayer = .eater, limit: CGFloat = 300, onFrame: (() -> Void)? = nil) -> (finished: Bool, seconds: CGFloat) {
        start()
        touched = true
        var flail = SeededGenerator(seed: 9), flipAt: CGFloat = 0, holding = false
        while clock < limit && !finished {
            let ahead = swimmers.filter { $0.fish.state == .swimming && screensAhead($0.fish) > -0.03 }
                .min { screensAhead($0.fish) < screensAhead($1.fish) }
            switch style {
            case .passive:
                holding = false
            case .flailing:
                if clock >= flipAt { holding.toggle(); flipAt = clock + CGFloat.random(in: 0.1...0.7, using: &flail) }
            case .dodger(let until) where clock < until:
                let threat = ahead?.fish.position.y ?? player.position.y
                holding = threat < (waterBottom + waterTop) / 2
            case .eater, .dodger:
                // With no name coming, it keeps to the middle of the water.
                holding = (ahead?.fish.position.y ?? waterCenter) > player.position.y + 3
            }
            debugHolding = holding
            advance(T.simulationStep)
            onFrame?()
        }
        debugHolding = nil
        return (finished, clock)
    }

    /// A name `scale` times your size, right on you: a fish that big would eat you in a level.
    func debugPutNameOnYou(scale: CGFloat) {
        let index = names.indices.first ?? 0
        waiting.removeAll { $0 == index }
        release(index)
        guard let s = swimmers.last else { return }
        s.fish.radius = player.radius * scale
        s.fish.targetRadius = s.fish.radius
        s.fish.position = player.position
    }
    #endif
}

/// A name's tag, over its fish: the name, with its role in small capitals over it, in a bubble that points down at the
/// fish. It's drawn in points on screen, upright, so it reads the same at any zoom and never mirrors as its fish turns.
/// Its origin is the tip of the point.
final class CreditTag: SKNode {
    static let pointer: CGFloat = 7
    static let bubbleHeight: CGFloat = 50
    static var height: CGFloat { pointer + bubbleHeight }
    let width: CGFloat
    let credit: ArcadeCredits.Credit

    init(_ credit: ArcadeCredits.Credit) {
        self.credit = credit
        let name = CreditsScene.label(credit.name, size: GameTuning.creditsNameFont, heavy: true)
        let role = SKLabelNode()
        role.attributedText = NSAttributedString(string: credit.tag.uppercased(), attributes: [
            .font: UIFont(name: "AvenirNext-Heavy", size: GameTuning.creditsRoleFont) ?? .boldSystemFont(ofSize: GameTuning.creditsRoleFont),
            .foregroundColor: UIColor(white: 1, alpha: 0.72),
            .kern: 1.1,
        ])
        role.verticalAlignmentMode = .center
        width = max(name.frame.width, role.frame.width) + 30
        super.init()
        let h = Self.bubbleHeight, p = Self.pointer, w = width, r: CGFloat = 16
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: -w / 2, y: p, width: w, height: h), cornerWidth: r, cornerHeight: r)
        path.move(to: CGPoint(x: -7, y: p + 0.5))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 7, y: p + 0.5))
        let bubble = SKShapeNode(path: path)
        bubble.fillColor = SKColor(red: 0.02, green: 0.09, blue: 0.23, alpha: 0.55)
        bubble.strokeColor = SKColor(white: 1, alpha: 0.5)
        bubble.lineWidth = 1.5
        addChild(bubble)
        role.position = CGPoint(x: 0, y: p + h - 14)
        name.position = CGPoint(x: 0, y: p + 19)
        addChild(role)
        addChild(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The credits on screen: the scene letterboxed on the ocean like a level, with Skip in the corner until the card
/// comes up (as the tutorial's).
struct CreditsView: View {
    @ObservedObject var scene: CreditsScene

    var body: some View {
        GeometryReader { geometry in
            let fitted = GameTuning.fittedPlayfieldSize(in: geometry.size)
            ZStack {
                OceanBackdrop(bloom: false)
                SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                    .id(ObjectIdentifier(scene))
                    .frame(width: fitted.width, height: fitted.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            if !scene.finished {
                Button("Skip") { scene.leave() }
                    .font(.custom("AvenirNext-DemiBold", size: 14)).foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black.opacity(0.25), in: Capsule())
                    .buttonStyle(.plain)
                    .padding(.leading, 24).padding(.top, 14)
                    .accessibilityLabel("Skip the credits")
            }
        }
    }
}
