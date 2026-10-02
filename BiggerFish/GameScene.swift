import FishKit
import SpriteKit
import UIKit

private struct Swallow {
    let predatorID: Int
    let preyID: Int
    var elapsed: CGFloat = 0
    let duration: CGFloat
    /// prey radius / predator radius at the moment of contact.
    let ratio: CGFloat
    /// Prey position relative to the predator at contact (wrapped).
    let startOffset: CGVector
}

private struct BloomJelly {
    let node: JellyfishNode
    let origin: CGPoint
    var position: CGPoint
    let phase: CGFloat
}

private struct BloomBrain {
    let aggressive: Bool
    var chaseRemaining: CGFloat = 0
    var cooldown: CGFloat = 0
}

private struct Speck {
    let node: SKSpriteNode
    let parallax: CGFloat
    let rise: CGFloat
}

final class GameScene: SKScene {
    private enum Phase { case ready, playing, paused, won, lost }
    private typealias T = GameTuning

    private var phase: Phase = .ready
    private var world = WrappedWorld(width: 1)
    private var fish: [Fish] = []
    private var fishByID: [Int: Fish] = [:]
    private var nodes: [Int: FishNode] = [:]
    private var swallows: [Swallow] = []
    private var player: Fish!
    let arcadeWorld: ArcadeWorld
    private var levelIndex: Int
    private var level: Level { arcadeWorld.levels[levelIndex] }
    private var isFinalLevel: Bool { levelIndex == arcadeWorld.levels.count - 1 }
    var onClear: ((Int, Double) -> Void)?
    var onExit: (() -> Void)?
    var onJellyLesson: (() -> Void)?
    private var showsJellyLesson: Bool
    private var lossReason = "There was a bigger fish."
    private var jellies: [BloomJelly] = []
    private var urchins: [(x: CGFloat, node: SKNode)] = []
    private var brains: [Int: BloomBrain] = [:]
    private var bounceRemaining: CGFloat = 0
    private var bounceCooldown: CGFloat = 0
    private var mapButton = SKShapeNode()
    private let audio = ArcadeAudio()

    init(size: CGSize, world: ArcadeWorld = .shallowReef, levelIndex: Int = 0,
         showsJellyLesson: Bool = true) {
        arcadeWorld = world
        self.levelIndex = min(max(0, levelIndex), world.levels.count - 1)
        self.showsJellyLesson = showsJellyLesson
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var rng = SeededGenerator(seed: T.spawnSeed)

    private let backgroundLayer = SKNode()
    private let fishLayer = SKNode()
    private let hazardLayer = SKNode()
    private let uiLayer = SKNode()
    private let dimNode = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
    private var specks: [Speck] = []
    private var winGlow: SKShapeNode?

    private let messageNode = SKNode()
    private let pauseButton = SKNode()
    private let pauseMenu = SKNode()
    private let levelIndicator = SKNode()
    private var resumeButton = SKShapeNode()
    private var restartButton = SKShapeNode()

    private var holdTouches = Set<UITouch>()
    private var lastUpdate: TimeInterval?
    private var realClock: CGFloat = 0
    /// Simulated seconds since the current run started playing.
    private var simClock: CGFloat = 0
    private var timeScale: CGFloat = 1
    private var slowMoRemaining: CGFloat = 0
    private var slowMoFactor: CGFloat = 1
    private var endedAt: CGFloat = 0
    private var lastCameraX: CGFloat = 0
    private var hasLayers = false
    private var isBuilt = false

    private let closeCallHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let eatenHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let eatenNotification = UINotificationFeedbackGenerator()

    /// Camera scale: 1 at the start of a run, easing toward `minZoom` as the player grows.
    /// World y equals screen y at zoom 1; zooming out makes the water taller in world units.
    private var zoom: CGFloat = 1
    private var screenWaterBottom: CGFloat { T.waterBottomMargin }
    private var screenWaterTop: CGFloat { size.height - T.waterTopMargin }
    private var waterCenter: CGFloat { (screenWaterBottom + screenWaterTop) / 2 }
    private var waterBottom: CGFloat { waterCenter - (waterCenter - screenWaterBottom) / zoom }
    private var waterTop: CGFloat { waterCenter + (screenWaterTop - waterCenter) / zoom }
    /// Player movement is defined in screen points, so it feels the same at any zoom.
    private var playerSpeed: CGFloat { size.width / level.screenCrossSeconds / zoom }
    private var isHolding: Bool { !holdTouches.isEmpty }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.04, green: 0.15, blue: 0.32, alpha: 1)

        if !hasLayers {
            hasLayers = true
            backgroundLayer.zPosition = 0
            dimNode.zPosition = 5
            dimNode.alpha = 0
            fishLayer.zPosition = 10
            uiLayer.zPosition = 100
            addChild(backgroundLayer)
            addChild(dimNode)
            hazardLayer.zPosition = 8
            addChild(hazardLayer)
            addChild(fishLayer)
            addChild(uiLayer)
            uiLayer.addChild(messageNode)
            uiLayer.addChild(pauseButton)
            uiLayer.addChild(pauseMenu)
            uiLayer.addChild(levelIndicator)
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillResignActive),
                name: UIApplication.willResignActiveNotification, object: nil
            )
        }
        closeCallHaptic.prepare()
        eatenHaptic.prepare()
        if !isBuilt { build() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard isBuilt, size != oldSize, size.width > 1, size.height > 1 else { return }
        layoutStatic()
        resetGame(startPlaying: false)
    }

    private func build() {
        guard size.width > 1, size.height > 1 else { return }
        isBuilt = true
        layoutStatic()
        resetGame(startPlaying: false)
    }

    @objc private func appWillResignActive() {
        if phase == .playing { pauseRun() }
        holdTouches.removeAll()
    }

    // MARK: - Run setup

    private func resetGame(startPlaying: Bool) {
        for node in nodes.values { node.removeFromParent() }
        nodes.removeAll()
        fish.removeAll()
        fishByID.removeAll()
        swallows.removeAll()
        hazardLayer.removeAllChildren()
        jellies.removeAll()
        urchins.removeAll()
        brains.removeAll()
        bounceRemaining = 0
        bounceCooldown = 0
        lossReason = "There was a bigger fish."
        winGlow?.removeFromParent()
        winGlow = nil
        dimNode.removeAllActions()
        dimNode.alpha = 0
        holdTouches.removeAll()
        timeScale = 1
        slowMoRemaining = 0
        simClock = 0
        zoom = 1

        world = WrappedWorld(width: size.width * T.worldScreens)
        rng = SeededGenerator(seed: T.spawnSeed &+ UInt64(levelIndex + (arcadeWorld == .jellyBloom ? 100 : 0)))
        spawnJellies()
        spawnEcosystem()
        lastCameraX = player.position.x
        setPhase(startPlaying ? .playing : .ready)
        buildLevelIndicator()
        render()
    }

    private func spawnEcosystem() {
        let base = T.baseRadius
        let p = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: (waterBottom + waterTop) / 2), radius: base)
        p.velocity = CGVector(dx: playerSpeed, dy: 0)
        player = p
        add(p, style: .player)

        var nextID = 1
        for group in level.spawnGroups {
            for _ in 0..<group.count {
                let normalized = CGFloat.random(in: group.radii, using: &rng)
                let r = normalized * base
                guard let pos = findSpawnPoint(radius: r, dangerous: normalized >= T.spawnDangerRatio) else { continue }
                let f = Fish(id: nextID, isPlayer: false, position: pos, radius: r)
                nextID += 1
                f.heading = Bool.random(using: &rng) ? 1 : -1
                f.cruiseSpeed = CGFloat.random(in: level.aiSpeedRange, using: &rng)
                f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
                f.facing = f.heading
                f.targetY = pos.y
                f.retargetTimer = CGFloat.random(in: T.aiRetargetRange, using: &rng)
                f.turnTimer = CGFloat.random(in: T.aiTurnIntervalRange, using: &rng)
                f.phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                add(f, style: FishStyle.random(using: &rng))
                if level.jellies != nil {
                    brains[f.id] = BloomBrain(aggressive: CGFloat.random(in: 0...1, using: &rng) < T.bloomAggressiveFraction)
                }
            }
        }
    }

    private func findSpawnPoint(radius r: CGFloat, dangerous: Bool) -> CGPoint? {
        let clearBehind = size.width * T.spawnClearBehind
        let clearAhead = size.width * (dangerous ? T.spawnClearAheadDanger : T.spawnClearAheadSmall)
        for _ in 0..<500 {
            let x = CGFloat.random(in: 0..<world.width, using: &rng)
            let y = CGFloat.random(in: (waterBottom + r)...(waterTop - r), using: &rng)
            let dx = world.delta(from: player.position.x, to: x)
            if dx > -clearBehind && dx < clearAhead { continue }
            let point = CGPoint(x: x, y: y)
            let overlaps = fish.contains {
                world.distance($0.position, point) < ($0.radius + r) * T.collisionScale + T.spawnPadding
            }
            let inJelly = jellies.contains { jelly in
                guard let layout = level.jellies else { return false }
                let relative = CGPoint(x: world.delta(from: jelly.position.x, to: point.x),
                                       y: point.y - jelly.position.y)
                return JellyRules.contact(at: relative, previous: relative, fishRadius: r,
                                          domeRadius: layout.radius + T.spawnPadding,
                                          tentacleLength: layout.tentacleLength + T.spawnPadding) != .none
            }
            if !overlaps && !inJelly { return point }
        }
        return nil
    }

    private func add(_ f: Fish, style: FishStyle) {
        fish.append(f)
        fishByID[f.id] = f
        let node = FishNode(style: style, isPlayer: f.isPlayer, tailPhase: CGFloat(f.id) * 1.7)
        node.zPosition = f.isPlayer ? 30 : 1 + CGFloat(f.id) * 0.5
        nodes[f.id] = node
        fishLayer.addChild(node)
    }

    // MARK: - Phases

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        pauseButton.isHidden = newPhase != .playing
        pauseMenu.isHidden = newPhase != .paused
        switch newPhase {
        case .ready:
            let lines = arcadeWorld == .jellyBloom
                ? (showsJellyLesson ? ["Bounce the tops.", "Never touch the bottoms.", "Eat fish or let the jellies clear them."]
                                   : ["Eat smaller fish. Avoid bigger fish.", "Bounce domes. Dodge tentacles."])
                : ["Hold to rise. Release to fall.", "Eat smaller fish. Avoid bigger fish."]
            showMessage(arcadeWorld.levelTitles[levelIndex], lines: lines)
            let start = label("Tap anywhere to swim", fontSize: 12, heavy: false)
            start.alpha = 0.7
            start.position = CGPoint(x: 0, y: -77)
            messageNode.addChild(start)
            addMapButton(to: messageNode, y: -111)
        case .playing, .paused:
            hideMessage()
        case .won:
            let next = isFinalLevel ? "\(arcadeWorld.title) complete! Tap to see the map."
                                   : "Tap for \(arcadeWorld.levelTitles[levelIndex + 1])."
            showMessage("Biggest fish.", lines: [next], delay: 0.9)
            addMapButton(to: messageNode, y: -82)
        case .lost:
            showMessage(lossReason, lines: ["Tap to try again."], delay: 0.35)
            addMapButton(to: messageNode, y: -82)
        }
    }

    private func startRun() {
        if arcadeWorld == .jellyBloom && showsJellyLesson {
            onJellyLesson?()
            showsJellyLesson = false
        }
        simClock = 0
        setPhase(.playing)
    }

    private func pauseRun() {
        buildPauseMenu()
        setPhase(.paused)
        holdTouches.removeAll()
    }

    private func win() {
        onClear?(levelIndex, Double(simClock))
        audio.play(.clear)
        setPhase(.won)
        endedAt = realClock
        slowMoFactor = T.winSlowFactor
        slowMoRemaining = T.winSlowDuration
        dimNode.run(.fadeAlpha(to: 0.35, duration: 0.6))

        let glow = SKShapeNode(circleOfRadius: player.radius * zoom * 1.8)
        glow.strokeColor = SKColor(white: 1, alpha: 0.8)
        glow.fillColor = .clear
        glow.lineWidth = 3
        glow.zPosition = 29
        glow.run(.repeatForever(.sequence([
            .group([.scale(to: 1.6, duration: 1.0), .fadeOut(withDuration: 1.0)]),
            .scale(to: 1, duration: 0),
            .fadeAlpha(to: 0.8, duration: 0),
        ])))
        fishLayer.addChild(glow)
        winGlow = glow
    }

    private func lose() {
        audio.play(.lose)
        setPhase(.lost)
        endedAt = realClock
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            switch phase {
            case .ready:
                if let parent = mapButton.parent, mapButton.contains(parent.convert(p, from: self)) {
                    onExit?(); return
                }
                startRun()
                holdTouches.insert(touch)
            case .playing:
                if hypot(p.x - pauseButton.position.x, p.y - pauseButton.position.y) < 36 {
                    pauseRun()
                } else {
                    holdTouches.insert(touch)
                }
            case .paused:
                if resumeButton.frame.insetBy(dx: -10, dy: -10).contains(p) {
                    setPhase(.playing)
                } else if restartButton.frame.insetBy(dx: -10, dy: -10).contains(p) {
                    resetGame(startPlaying: false)
                } else if mapButton.frame.insetBy(dx: -10, dy: -10).contains(p) {
                    onExit?()
                    return
                }
            case .won:
                if realClock - endedAt >= T.restartDelay {
                    if mapButton.contains(messageNode.convert(p, from: self)) || isFinalLevel {
                        onExit?()
                        return
                    }
                    levelIndex += 1
                    layoutStatic()
                    resetGame(startPlaying: false)
                }
            case .lost:
                if realClock - endedAt >= T.restartDelay {
                    if mapButton.contains(messageNode.convert(p, from: self)) { onExit?(); return }
                    resetGame(startPlaying: true)
                    holdTouches.insert(touch)
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTouches.subtract(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTouches.subtract(touches)
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt else { return }
        let realDt = min(lastUpdate.map { CGFloat(currentTime - $0) } ?? 0, 1.0 / 30)
        lastUpdate = currentTime
        realClock += realDt

        if slowMoRemaining > 0 {
            slowMoRemaining -= realDt
            timeScale = slowMoFactor
        } else {
            timeScale = min(1, timeScale + realDt * 2.5)
        }

        switch phase {
        case .playing, .won, .lost:
            simulate(realDt * timeScale)
        case .ready, .paused:
            break
        }

        let cameraDelta = world.delta(from: lastCameraX, to: player.position.x) * zoom
        lastCameraX = player.position.x
        updateSpecks(realDt: phase == .paused ? 0 : realDt, cameraDelta: cameraDelta)
        render()
    }

    private func simulate(_ dt: CGFloat) {
        simClock += dt
        updateZoom(dt)
        let previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
        for f in fish where f.isAlive {
            if f.isPlayer { movePlayer(f, dt) } else { moveAI(f, dt) }
        }
        if phase == .playing {
            updateJellies(dt, previousFish: previous)
            if phase == .playing { updateUrchins(previousFish: previous) }
        }
        advanceSwallows(dt)
        advanceGrowth(dt)
        if phase == .playing {
            resolveCollisions()
            if GameRules.isWin(fish) { win() }
        }
    }

    private func movePlayer(_ p: Fish, _ dt: CGFloat) {
        bounceRemaining = max(0, bounceRemaining - dt)
        bounceCooldown = max(0, bounceCooldown - dt)
        var motion = T.motion
        if bounceRemaining > 0 {
            motion.maxRiseSpeed = T.jellyBounceSpeed
            motion.fallAcceleration *= 0.35
        }
        let (y, vy) = PlayerMotion.step(
            y: p.position.y, vy: p.velocity.dy, holding: isHolding, dt: dt,
            minY: waterBottom + p.radius * 0.95, maxY: waterTop - p.radius * 0.95,
            zoom: zoom, tuning: motion
        )
        p.velocity = CGVector(dx: playerSpeed, dy: vy)
        p.position = CGPoint(x: world.wrap(p.position.x + playerSpeed * dt), y: y)
        p.facing = 1
    }

    private func updateZoom(_ dt: CGFloat) {
        guard player.isAlive else { return }
        let growth = player.radius / (T.baseRadius * T.zoomStartSize)
        let target = growth > 1 ? max(T.minZoom, pow(1 / growth, T.zoomExponent)) : 1
        zoom += (target - zoom) * min(1, dt * T.zoomEase)
    }

    private func moveAI(_ f: Fish, _ dt: CGFloat) {
        if level.jellies != nil, moveBloomAI(f, dt) { return }
        f.turnTimer -= dt
        if f.turnTimer <= 0 {
            f.heading *= -1
            f.turnTimer = CGFloat.random(in: T.aiTurnIntervalRange, using: &rng)
        }
        let targetVX = f.heading * f.cruiseSpeed * (1 + 0.15 * sin(simClock * 0.7 + f.phase))
        var vx = f.velocity.dx + (targetVX - f.velocity.dx) * min(1, dt * 1.5)

        let minY = waterBottom + f.radius
        let maxY = max(minY, waterTop - f.radius)
        f.retargetTimer -= dt
        if f.retargetTimer <= 0 || abs(f.targetY - f.position.y) < 6 {
            f.targetY = CGFloat.random(in: minY...maxY, using: &rng)
            f.retargetTimer = CGFloat.random(in: T.aiRetargetRange, using: &rng)
        }
        f.targetY = f.targetY.clamped(minY, maxY)
        let desiredVY = ((f.targetY - f.position.y) * 0.9).clamped(-level.aiVerticalSpeed, level.aiVerticalSpeed)
            + sin(simClock * 1.3 + f.phase) * 8
        var vy = f.velocity.dy + (desiredVY - f.velocity.dy) * min(1, dt * 2)

        var y = f.position.y + vy * dt
        if y < minY { y = minY; vy = abs(vy) * 0.3 }
        if y > maxY { y = maxY; vy = -abs(vy) * 0.3 }
        if !vx.isFinite { vx = 0 }

        f.velocity = CGVector(dx: vx, dy: vy)
        f.position = CGPoint(x: world.wrap(f.position.x + vx * dt), y: y)
        // Facing follows horizontal velocity, so turns read as a smooth flip through side-on.
        f.facing = (vx / 20).clamped(-1, 1)
    }

    // MARK: - Jelly Bloom (arcade-only; no shared engine changes)

    private func spawnJellies() {
        guard let layout = level.jellies else { return }
        for i in 0..<layout.count {
            // A safe opening, then alternating bell heights create a route through the field.
            let x = size.width * 0.85 + CGFloat(i) * (world.width - size.width) / CGFloat(layout.count)
            let fraction: CGFloat = i.isMultiple(of: 2) ? 0.37 : 0.68
            let y = max(waterBottom + layout.tentacleLength + 12,
                        waterBottom + (waterTop - waterBottom) * fraction)
            let origin = CGPoint(x: world.wrap(x), y: y)
            let phase = CGFloat(i) * 1.7
            let node = JellyfishNode(radius: layout.radius, tentacleLength: layout.tentacleLength, phase: phase)
            hazardLayer.addChild(node)
            jellies.append(BloomJelly(node: node, origin: origin, position: origin, phase: phase))
        }
        for i in 0..<layout.urchinBeds {
            let center = size.width * 1.1 + CGFloat(i) * (world.width - size.width * 1.4) / CGFloat(max(1, layout.urchinBeds - 1))
            for offset in -2...2 {
                let node = ArcadeArt.urchin(radius: T.urchinRadius)
                hazardLayer.addChild(node)
                urchins.append((x: world.wrap(center + CGFloat(offset) * T.urchinRadius * 1.6), node: node))
            }
        }
    }

    private func updateUrchins(previousFish: [Int: CGPoint]) {
        for urchin in urchins {
            let center = CGPoint(x: urchin.x, y: waterBottom + T.urchinRadius * 0.55)
            for f in fish.filter({ $0.isAlive }) {
                let p = CGPoint(x: world.delta(from: center.x, to: f.position.x), y: f.position.y - center.y)
                let old = previousFish[f.id] ?? f.position
                let previous = CGPoint(x: p.x - world.delta(from: old.x, to: f.position.x),
                                       y: old.y - center.y)
                let delta = CGVector(dx: p.x - previous.x, dy: p.y - previous.y)
                let length = delta.dx * delta.dx + delta.dy * delta.dy
                let t = length > 0 ? (-(previous.x * delta.dx + previous.y * delta.dy) / length).clamped(0, 1) : 0
                let closest = CGPoint(x: previous.x + delta.dx * t, y: previous.y + delta.dy * t)
                if hypot(closest.x, closest.y) < (T.urchinRadius + f.radius) * T.hazardHitboxScale {
                    removeByTentacles(f, reason: "Caught on the urchins.")
                    if f.isPlayer { return }
                }
            }
        }
    }

    private func updateJellies(_ dt: CGFloat, previousFish: [Int: CGPoint]) {
        guard let layout = level.jellies else { return }
        for i in jellies.indices {
            let previousJelly = jellies[i].position
            jellies[i].position = CGPoint(
                x: world.wrap(jellies[i].origin.x + sin(simClock * 0.45 + jellies[i].phase) * layout.sway),
                y: jellies[i].origin.y + sin(simClock * 0.65 + jellies[i].phase) * layout.sway
            )
            let jelly = jellies[i]
            for f in fish.filter({ $0.isAlive }) {
                guard let old = previousFish[f.id] else { continue }
                let p = CGPoint(x: world.delta(from: jelly.position.x, to: f.position.x),
                                y: f.position.y - jelly.position.y)
                // Keep both endpoints on the same wrapped branch. Independently wrapping them
                // can draw a fictitious sweep through a jelly on the other side of the world.
                let movement = world.delta(from: old.x, to: f.position.x)
                    - world.delta(from: previousJelly.x, to: jelly.position.x)
                let previous = CGPoint(x: p.x - movement, y: old.y - previousJelly.y)
                switch JellyRules.contact(at: p, previous: previous, fishRadius: f.radius,
                                          domeRadius: layout.radius, tentacleLength: layout.tentacleLength) {
                case .none: break
                case .bounce:
                    guard !f.isPlayer || bounceCooldown <= 0 else { continue }
                    let x = min(1, abs(p.x) / (layout.radius + f.radius * T.hazardHitboxScale))
                    let surface = layout.radius * 0.65 * sqrt(max(0, 1 - x * x))
                    f.position.y = jelly.position.y + surface + f.radius * T.hazardHitboxScale + 2
                    f.velocity.dy = T.jellyBounceSpeed / zoom
                    jelly.node.bounce()
                    if f.isPlayer {
                        bounceRemaining = T.jellyBounceSeconds
                        bounceCooldown = T.jellyBounceCooldown
                        f.pulse = T.pulseDuration
                        closeCallHaptic.impactOccurred(intensity: 0.55)
                        audio.play(.bounce)
                    }
                case .tentacles:
                    removeByTentacles(f)
                    if f.isPlayer { return }
                }
            }
        }
    }

    private func removeByTentacles(_ victim: Fish, reason: String = "Caught in the tentacles.") {
        // If a predator hits a curtain mid-swallow, its prey escapes rather than getting stuck.
        for swallow in swallows where swallow.predatorID == victim.id || swallow.preyID == victim.id {
            let otherID = swallow.predatorID == victim.id ? swallow.preyID : swallow.predatorID
            if let survivor = fishByID[otherID], survivor.state != .removed {
                survivor.state = .swimming
                survivor.shrink = 1
                survivor.struggle = 0
                survivor.chew = 0
                survivor.squash = 0
            }
        }
        swallows.removeAll { $0.predatorID == victim.id || $0.preyID == victim.id }
        victim.state = .removed
        nodes[victim.id]?.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
        if victim.isPlayer {
            lossReason = reason
            eatenNotification.notificationOccurred(.error)
            lose()
        } else {
            fish.removeAll { $0.id == victim.id }
            fishByID[victim.id] = nil
            brains[victim.id] = nil
            nodes[victim.id] = nil
        }
    }

    private func renderJellies() {
        for urchin in urchins {
            let x = size.width * T.playerScreenX + world.delta(from: player.position.x, to: urchin.x) * zoom
            urchin.node.isHidden = x < -30 || x > size.width + 30
            urchin.node.position = CGPoint(x: x, y: screenWaterBottom + T.urchinRadius * 0.55 * zoom)
            urchin.node.setScale(zoom)
        }
        for jelly in jellies {
            let x = size.width * T.playerScreenX + world.delta(from: player.position.x, to: jelly.position.x) * zoom
            jelly.node.isHidden = x < -100 || x > size.width + 100
            jelly.node.position = CGPoint(x: x, y: waterCenter + (jelly.position.y - waterCenter) * zoom)
            jelly.node.setScale(zoom)
            jelly.node.animate(time: realClock)
        }
    }

    /// Bloom gets a limited commitment chase and short-range fleeing; Shallow Reef keeps its drift AI.
    private func moveBloomAI(_ f: Fish, _ dt: CGFloat) -> Bool {
        guard var brain = brains[f.id], player.isAlive else { return false }
        let dx = world.delta(from: f.position.x, to: player.position.x)
        let dy = player.position.y - f.position.y
        let distance = hypot(dx, dy) * zoom
        let predator = GameRules.encounter(f.radius, player.radius) == .firstEatsSecond
        brain.cooldown = max(0, brain.cooldown - dt)
        if !predator || distance > T.bloomGiveUpRadius {
            if brain.chaseRemaining > 0 { brain.cooldown = 2 }
            brain.chaseRemaining = 0
        }
        if predator && brain.aggressive && brain.chaseRemaining <= 0 && brain.cooldown <= 0,
           distance < T.bloomAggroRadius {
            brain.chaseRemaining = T.bloomChaseSeconds
            let warning = label("!", fontSize: 19, heavy: true)
            warning.name = "chase-warning"
            warning.fontColor = SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
            warning.position = CGPoint(x: 0, y: f.radius * zoom + 12)
            warning.run(.sequence([.scale(to: 1.3, duration: 0.12), .scale(to: 1, duration: 0.12),
                                   .wait(forDuration: 0.4), .fadeOut(withDuration: 0.2), .removeFromParent()]))
            nodes[f.id]?.addChild(warning)
        }
        let chasing = brain.chaseRemaining > 0
        let fleeing = !predator && GameRules.encounter(player.radius, f.radius) == .firstEatsSecond
            && distance < T.bloomFleeRadius
        if chasing {
            brain.chaseRemaining = max(0, brain.chaseRemaining - dt)
            if brain.chaseRemaining == 0 { brain.cooldown = 2 }
        }
        brains[f.id] = brain
        guard chasing || fleeing else { return false }
        let targetVX: CGFloat = chasing
            ? playerSpeed + (dx * 0.8).clamped(-100 / zoom, 100 / zoom)
            : -(dx >= 0 ? CGFloat(1) : CGFloat(-1)) * max(f.cruiseSpeed * 1.3, playerSpeed * 0.6)
        let targetVY = (dy * (chasing ? 1 : -1)).clamped(-T.motion.maxRiseSpeed * 0.85 / zoom,
                                                       T.motion.maxRiseSpeed * 0.85 / zoom)
        let steer = min(1, dt * T.bloomChaseTurnRate)
        f.velocity.dx += (targetVX - f.velocity.dx) * steer
        f.velocity.dy += (targetVY - f.velocity.dy) * steer
        let minY = waterBottom + f.radius, maxY = max(minY, waterTop - f.radius)
        f.position.x = world.wrap(f.position.x + f.velocity.dx * dt)
        f.position.y = (f.position.y + f.velocity.dy * dt).clamped(minY, maxY)
        f.facing = (f.velocity.dx / 20).clamped(-1, 1)
        return true
    }

    private func advanceGrowth(_ dt: CGFloat) {
        for f in fish {
            if f.growElapsed < T.growDuration {
                f.growElapsed += dt
                let t = min(1, f.growElapsed / T.growDuration)
                let eased = 1 - pow(1 - t, 3)
                f.radius = f.growFrom + (f.targetRadius - f.growFrom) * eased
            }
            if f.pulse > 0 { f.pulse = max(0, f.pulse - dt) }
            if case .swallowing = f.state {
                f.mouth = min(1, f.mouth + dt / T.mouthOpenSeconds)
            } else {
                f.mouth = max(0, f.mouth - dt / T.mouthCloseSeconds)
            }
        }
    }

    // MARK: - Collisions and swallowing

    private func resolveCollisions() {
        let candidates = fish.filter { $0.state == .swimming }
        guard candidates.count > 1 else { return }
        let aiMayEat = T.aiFishCanEatEachOther && level.aiCanEat && simClock >= T.aiEatingGracePeriod

        for i in 0..<(candidates.count - 1) {
            for j in (i + 1)..<candidates.count {
                let a = candidates[i], b = candidates[j]
                guard a.state == .swimming, b.state == .swimming else { continue }
                if !a.isPlayer && !b.isPlayer && !aiMayEat { continue }

                let dx = world.delta(from: a.position.x, to: b.position.x)
                let dy = b.position.y - a.position.y
                let reach = (a.radius + b.radius) * T.collisionScale
                guard dx * dx + dy * dy < reach * reach else { continue }

                switch GameRules.encounter(a.radius, b.radius) {
                case .firstEatsSecond: beginSwallow(predator: a, prey: b)
                case .secondEatsFirst: beginSwallow(predator: b, prey: a)
                case .tooClose: bump(a, b, dx: dx, dy: dy, reach: reach)
                }
            }
        }
    }

    /// Near-equal fish gently drift apart vertically instead of producing an arbitrary winner.
    private func bump(_ a: Fish, _ b: Fish, dx: CGFloat, dy: CGFloat, reach: CGFloat) {
        let dir: CGFloat = dy >= 0 ? 1 : -1 // b is above a when positive
        let push: CGFloat = 4
        if a.isPlayer {
            b.position.y += dir * push
            a.velocity.dy -= dir * 60
        } else if b.isPlayer {
            a.position.y -= dir * push
            b.velocity.dy += dir * 60
        } else {
            a.position.y -= dir * push / 2
            b.position.y += dir * push / 2
        }
        for f in [a, b] where !f.isPlayer {
            f.position.y = f.position.y.clamped(waterBottom + f.radius, max(waterBottom + f.radius, waterTop - f.radius))
        }
    }

    private func beginSwallow(predator: Fish, prey: Fish) {
        predator.state = .swallowing(preyID: prey.id)
        prey.state = .beingSwallowed(predatorID: predator.id)
        let ratio = prey.radius / predator.radius
        swallows.append(Swallow(
            predatorID: predator.id,
            preyID: prey.id,
            duration: SwallowTiming.duration(sizeRatio: ratio, curve: T.swallowDurationCurve),
            ratio: ratio,
            startOffset: CGVector(
                dx: world.delta(from: predator.position.x, to: prey.position.x),
                dy: prey.position.y - predator.position.y
            )
        ))
        if let predatorNode = nodes[predator.id], let preyNode = nodes[prey.id] {
            preyNode.zPosition = predatorNode.zPosition - 0.25
        }

        guard predator.isPlayer || prey.isPlayer else { return }
        if ratio >= T.slowMoRatio {
            slowMoFactor = T.closeCallSlowFactor
            slowMoRemaining = T.closeCallSlowDuration
        }
        if prey.isPlayer {
            eatenHaptic.impactOccurred(intensity: 1)
            eatenNotification.notificationOccurred(.error)
        }
    }

    private func advanceSwallows(_ dt: CGFloat) {
        var finished: [Int] = []
        for i in swallows.indices {
            swallows[i].elapsed += dt
            let s = swallows[i]
            guard let predator = fishByID[s.predatorID], let prey = fishByID[s.preyID] else { continue }

            let t = min(1, s.elapsed / s.duration)
            let eased = t * t * (3 - 2 * t)
            let dir: CGFloat = predator.facing >= 0 ? 1 : -1
            let mouth = CGVector(dx: dir * predator.radius * 1.05, dy: -predator.radius * 0.1)
            let ox = s.startOffset.dx + (mouth.dx - s.startOffset.dx) * eased
            let oy = s.startOffset.dy + (mouth.dy - s.startOffset.dy) * eased
            prey.position = CGPoint(x: world.wrap(predator.position.x + ox), y: predator.position.y + oy)
            prey.shrink = 1 - 0.9 * eased

            let closeness = ((s.ratio - 0.7) / 0.3).clamped(0, 1)
            prey.struggle = closeness * (1 - t)
            predator.squash = closeness * 0.09 * sin(s.elapsed * 30) * (1 - t)
            predator.chew = closeness * (1 - t)

            if t >= 1 { finished.append(i) }
        }
        for i in finished.reversed() {
            completeSwallow(swallows.remove(at: i))
        }
    }

    private func completeSwallow(_ s: Swallow) {
        guard let predator = fishByID[s.predatorID], let prey = fishByID[s.preyID] else { return }

        prey.state = .removed
        nodes[prey.id]?.removeFromParent()
        nodes[prey.id] = nil
        fish.removeAll { $0.id == prey.id }
        fishByID[prey.id] = nil

        predator.state = .swimming
        predator.squash = 0
        predator.chew = 0
        predator.targetRadius = GameRules.grownRadius(
            predator: predator.targetRadius, prey: prey.radius, efficiency: level.absorptionEfficiency
        )
        predator.growFrom = predator.radius
        predator.growElapsed = 0
        predator.pulse = T.pulseDuration

        if predator.isPlayer { audio.play(.eat) }
        if predator.isPlayer && s.ratio >= T.closeCallRatio {
            closeCallHaptic.impactOccurred()
        }
        if prey.isPlayer {
            lose()
        } else if phase == .playing && GameRules.isWin(fish) {
            win()
        }
    }

    // MARK: - Rendering

    private func render() {
        let cameraX = player.position.x
        let anchorX = size.width * T.playerScreenX
        renderJellies()
        for f in fish {
            guard let node = nodes[f.id] else { continue }
            let screenX = anchorX + world.delta(from: cameraX, to: f.position.x) * zoom
            let margin = f.radius * zoom * 3
            node.isHidden = screenX < -margin || screenX > size.width + margin
            if node.isHidden { continue }
            node.position = CGPoint(x: screenX, y: waterCenter + (f.position.y - waterCenter) * zoom)

            var stretch: CGFloat = 1
            if f.pulse > 0 {
                stretch += sin((1 - f.pulse / T.pulseDuration) * .pi) * T.pulseAmount
            }
            let stretchX = stretch * (1 + f.squash) * f.shrink
            let stretchY = stretch * (1 - f.squash) * f.shrink

            let rawTilt = f.isPlayer
                ? f.velocity.dy * zoom / T.motion.maxRiseSpeed * T.motion.maxTilt
                : f.velocity.dy / level.aiVerticalSpeed * T.aiMaxTilt
            let facingSign: CGFloat = f.facing >= 0 ? 1 : -1
            let tilt = rawTilt.clamped(-T.motion.maxTilt, T.motion.maxTilt) * facingSign
                + f.struggle * sin(realClock * 45) * 0.35

            // Close calls chew: the mouth works while the prey struggles.
            let mouth = f.mouth * (1 - 0.35 * f.chew * (0.5 + 0.5 * sin(realClock * 38)))

            node.apply(
                radius: f.radius * zoom, facing: f.facing, tilt: tilt,
                stretchX: stretchX, stretchY: stretchY, mouthOpen: mouth,
                time: realClock, tailRate: f.isPlayer ? 14 : 9
            )
        }
        if let glow = winGlow, let playerNode = nodes[player.id] {
            glow.position = playerNode.position
        }
    }

    private func updateSpecks(realDt: CGFloat, cameraDelta: CGFloat) {
        let w = size.width, h = size.height
        for speck in specks {
            var p = speck.node.position
            p.x -= cameraDelta * speck.parallax
            p.y += speck.rise * realDt
            if p.x < -8 { p.x += w + 16 } else if p.x > w + 8 { p.x -= w + 16 }
            if p.y > h + 8 { p.y = -8 }
            speck.node.position = p
        }
    }

    // MARK: - Static layout

    private func layoutStatic() {
        backgroundLayer.removeAllChildren()
        specks.removeAll()

        let gradient = SKSpriteNode(texture: arcadeWorld == .jellyBloom
                                    ? ArcadeArt.bloomWater(night: level.jellies?.night == true)
                                    : WaterTextures.gradient())
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
            node.position = CGPoint(
                x: CGFloat.random(in: 0...size.width, using: &speckRNG),
                y: CGFloat.random(in: 0...size.height, using: &speckRNG)
            )
            node.zPosition = 1
            backgroundLayer.addChild(node)
            specks.append(Speck(node: node, parallax: parallax, rise: CGFloat.random(in: 4...14, using: &speckRNG)))
        }

        dimNode.size = size
        dimNode.position = CGPoint(x: size.width / 2, y: size.height / 2)

        // Right of center so the player (at 30% width) stays visible behind messages.
        messageNode.position = CGPoint(x: size.width * 0.63, y: size.height / 2)
        buildPauseButton()
        buildPauseMenu()
    }

    /// Small "Level N" label with one pip per level, top-left.
    private func buildLevelIndicator() {
        levelIndicator.removeAllChildren()
        let text = label("\(arcadeWorld.title.uppercased()) · \(levelIndex + 1)/5", fontSize: 13, heavy: true)
        text.horizontalAlignmentMode = .left
        text.alpha = 0.9
        levelIndicator.addChild(text)
        for i in 0..<arcadeWorld.levels.count {
            let pip = SKShapeNode(circleOfRadius: 3.5)
            pip.position = CGPoint(x: text.frame.width + 14 + CGFloat(i) * 11, y: 0)
            pip.fillColor = i <= levelIndex ? SKColor(white: 1, alpha: 0.8) : .clear
            pip.strokeColor = SKColor(white: 1, alpha: 0.5)
            pip.lineWidth = 1
            levelIndicator.addChild(pip)
        }
        levelIndicator.position = CGPoint(x: 64, y: size.height - 36)
    }

    private func buildPauseButton() {
        pauseButton.removeAllChildren()
        let circle = SKShapeNode(circleOfRadius: 20)
        circle.fillColor = SKColor(white: 0, alpha: 0.25)
        circle.strokeColor = SKColor(white: 1, alpha: 0.5)
        circle.lineWidth = 1.5
        pauseButton.addChild(circle)
        for x in [-5.0, 5.0] {
            let bar = SKShapeNode(rect: CGRect(x: x - 2.5, y: -8, width: 5, height: 16), cornerRadius: 1.5)
            bar.fillColor = SKColor(white: 1, alpha: 0.85)
            bar.strokeColor = .clear
            pauseButton.addChild(bar)
        }
        pauseButton.position = CGPoint(x: size.width - 64, y: size.height - 36)
    }

    private func buildPauseMenu() {
        pauseMenu.removeAllChildren()
        let shade = SKSpriteNode(color: SKColor(white: 0, alpha: 0.4), size: size)
        shade.anchorPoint = .zero
        pauseMenu.addChild(shade)

        let title = label("Paused", fontSize: 36, heavy: true)
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 90)
        pauseMenu.addChild(title)

        resumeButton = menuButton("Resume", at: CGPoint(x: size.width / 2, y: size.height / 2 + 5))
        restartButton = menuButton("Restart", at: CGPoint(x: size.width / 2, y: size.height / 2 - 60))
        pauseMenu.addChild(resumeButton)
        pauseMenu.addChild(restartButton)
        addMapButton(to: pauseMenu, y: size.height / 2 - 120, x: size.width / 2)
    }

    private func addMapButton(to parent: SKNode, y: CGFloat, x: CGFloat = 0) {
        mapButton.removeFromParent()
        mapButton = menuButton("Level map", at: CGPoint(x: x, y: y))
        mapButton.setScale(0.8)
        parent.addChild(mapButton)
    }

    private func menuButton(_ text: String, at position: CGPoint) -> SKShapeNode {
        let button = SKShapeNode(rectOf: CGSize(width: 170, height: 48), cornerRadius: 24)
        button.fillColor = SKColor(white: 1, alpha: 0.92)
        button.strokeColor = .clear
        button.position = position
        let text = label(text, fontSize: 20, heavy: true)
        text.fontColor = SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1)
        button.addChild(text)
        return button
    }

    private func showMessage(_ title: String, lines: [String], delay: TimeInterval = 0) {
        messageNode.removeAllActions()
        messageNode.removeAllChildren()

        let titleLabel = label(title, fontSize: 40, heavy: true)
        let lineLabels = lines.map { label($0, fontSize: 19, heavy: false) }
        let maxTextWidth = max(240, (size.width - messageNode.position.x - 28) * 2 - 70)
        for text in [titleLabel] + lineLabels where text.frame.width > maxTextWidth {
            text.fontSize *= maxTextWidth / text.frame.width
        }
        let lineSpacing: CGFloat = 30
        let height = 60 + CGFloat(lines.count) * lineSpacing + 30
        let width = max(titleLabel.frame.width, lineLabels.map(\.frame.width).max() ?? 0) + 70

        let panel = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        panel.fillColor = SKColor(white: 0, alpha: 0.3)
        panel.strokeColor = .clear
        messageNode.addChild(panel)

        var y = height / 2 - 45
        titleLabel.position = CGPoint(x: 0, y: y)
        messageNode.addChild(titleLabel)
        y -= 45
        for line in lineLabels {
            line.position = CGPoint(x: 0, y: y)
            messageNode.addChild(line)
            y -= lineSpacing
        }

        messageNode.alpha = 0
        messageNode.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.25)]))
    }

    private func hideMessage() {
        messageNode.removeAllActions()
        messageNode.run(.fadeOut(withDuration: 0.15))
    }

    private func label(_ text: String, fontSize: CGFloat, heavy: Bool) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: heavy ? "AvenirNext-Heavy" : "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
    #if DEBUG
    // Integration-test fixtures exercise the real scene update and hazard resolution.
    func debugStart() { startRun() }
    func debugFallOntoDome() -> Bool {
        guard let jelly = jellies.first, let layout = level.jellies else { return false }
        player.position = CGPoint(x: jelly.position.x,
                                  y: jelly.position.y + layout.radius * 0.65 + player.radius * T.hazardHitboxScale + 5)
        player.velocity.dy = -180
        simulate(1.0 / 30)
        return phase == .playing && player.velocity.dy > T.motion.maxRiseSpeed && bounceRemaining > 0
    }
    func debugTouchTentacles(playerVictim: Bool) -> Bool {
        guard let jelly = jellies.first,
              let victim = playerVictim ? player : fish.first(where: { !$0.isPlayer && $0.isAlive }) else { return false }
        victim.position = CGPoint(x: jelly.position.x, y: jelly.position.y - 40)
        let previous = Dictionary(uniqueKeysWithValues: fish.map { ($0.id, $0.position) })
        updateJellies(0, previousFish: previous)
        return playerVictim ? phase == .lost : fishByID[victim.id] == nil
    }
    func debugPassOppositeJelly() -> Bool {
        guard let jelly = jellies.first else { return false }
        let old = CGPoint(x: world.wrap(jelly.position.x + world.width / 2 - 2), y: jelly.position.y - 40)
        player.position = CGPoint(x: world.wrap(old.x + 4), y: old.y)
        updateJellies(0, previousFish: [player.id: old])
        return phase == .playing
    }
    func debugPassOppositeUrchin() -> Bool {
        guard let urchin = urchins.first else { return false }
        let old = CGPoint(x: world.wrap(urchin.x + world.width / 2 - 2), y: waterBottom + T.urchinRadius)
        player.position = CGPoint(x: world.wrap(old.x + 4), y: old.y)
        updateUrchins(previousFish: [player.id: old])
        return phase == .playing
    }
    func debugTouchUrchin() -> Bool {
        guard let urchin = urchins.first else { return false }
        player.position = CGPoint(x: urchin.x, y: waterBottom + T.urchinRadius)
        updateUrchins(previousFish: [player.id: player.position])
        return phase == .lost
    }
    func debugClearLevel() {
        for f in fish where !f.isPlayer { f.state = .removed }
        simulate(1.0 / 30)
    }
    #endif

}
