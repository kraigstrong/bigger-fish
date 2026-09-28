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
    private var rng = SeededGenerator(seed: T.spawnSeed)

    private let backgroundLayer = SKNode()
    private let fishLayer = SKNode()
    private let uiLayer = SKNode()
    private let dimNode = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
    private var specks: [Speck] = []
    private var winGlow: SKShapeNode?

    private let messageNode = SKNode()
    private let pauseButton = SKNode()
    private let pauseMenu = SKNode()
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

    private var waterBottom: CGFloat { T.waterBottomMargin }
    private var waterTop: CGFloat { size.height - T.waterTopMargin }
    private var playerSpeed: CGFloat { size.width / T.screenCrossSeconds }
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
            addChild(fishLayer)
            addChild(uiLayer)
            uiLayer.addChild(messageNode)
            uiLayer.addChild(pauseButton)
            uiLayer.addChild(pauseMenu)
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
        winGlow?.removeFromParent()
        winGlow = nil
        dimNode.removeAllActions()
        dimNode.alpha = 0
        holdTouches.removeAll()
        timeScale = 1
        slowMoRemaining = 0
        simClock = 0

        world = WrappedWorld(width: size.width * T.worldScreens)
        rng = SeededGenerator(seed: T.spawnSeed)
        spawnEcosystem()
        lastCameraX = player.position.x
        setPhase(startPlaying ? .playing : .ready)
        render()
    }

    private func spawnEcosystem() {
        let base = T.baseRadius
        let p = Fish(id: 0, isPlayer: true, position: CGPoint(x: 0, y: (waterBottom + waterTop) / 2), radius: base)
        p.velocity = CGVector(dx: playerSpeed, dy: 0)
        player = p
        add(p, style: .player)

        var nextID = 1
        for group in T.spawnGroups {
            for _ in 0..<group.count {
                let normalized = CGFloat.random(in: group.radii, using: &rng)
                let r = normalized * base
                guard let pos = findSpawnPoint(radius: r, dangerous: normalized >= T.spawnDangerRatio) else { continue }
                let f = Fish(id: nextID, isPlayer: false, position: pos, radius: r)
                nextID += 1
                f.heading = Bool.random(using: &rng) ? 1 : -1
                f.cruiseSpeed = CGFloat.random(in: T.aiSpeedRange, using: &rng)
                f.velocity = CGVector(dx: f.heading * f.cruiseSpeed, dy: 0)
                f.facing = f.heading
                f.targetY = pos.y
                f.retargetTimer = CGFloat.random(in: T.aiRetargetRange, using: &rng)
                f.turnTimer = CGFloat.random(in: T.aiTurnIntervalRange, using: &rng)
                f.phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                add(f, style: FishStyle.random(using: &rng))
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
            if !overlaps { return point }
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
            showMessage("Bigger Fish", lines: ["Hold to rise. Release to fall.", "Eat smaller fish. Avoid bigger fish."])
        case .playing, .paused:
            hideMessage()
        case .won:
            showMessage("Biggest fish.", lines: ["Tap to swim again."], delay: 0.9)
        case .lost:
            showMessage("There was a bigger fish.", lines: ["Tap to try again."], delay: 0.35)
        }
    }

    private func startRun() {
        simClock = 0
        setPhase(.playing)
    }

    private func pauseRun() {
        setPhase(.paused)
        holdTouches.removeAll()
    }

    private func win() {
        setPhase(.won)
        endedAt = realClock
        slowMoFactor = T.winSlowFactor
        slowMoRemaining = T.winSlowDuration
        dimNode.run(.fadeAlpha(to: 0.35, duration: 0.6))

        let glow = SKShapeNode(circleOfRadius: player.radius * 1.8)
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
        setPhase(.lost)
        endedAt = realClock
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            switch phase {
            case .ready:
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
                }
            case .won, .lost:
                if realClock - endedAt >= T.restartDelay {
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

        let cameraDelta = world.delta(from: lastCameraX, to: player.position.x)
        lastCameraX = player.position.x
        updateSpecks(realDt: phase == .paused ? 0 : realDt, cameraDelta: cameraDelta)
        render()
    }

    private func simulate(_ dt: CGFloat) {
        simClock += dt
        for f in fish where f.isAlive {
            if f.isPlayer { movePlayer(f, dt) } else { moveAI(f, dt) }
        }
        advanceSwallows(dt)
        advanceGrowth(dt)
        resolveCollisions()
    }

    private func movePlayer(_ p: Fish, _ dt: CGFloat) {
        var vy = p.velocity.dy
        vy += (isHolding ? T.riseAcceleration : -T.fallAcceleration) * dt
        vy *= exp(-T.verticalDamping * dt)
        vy = vy.clamped(-T.maxFallSpeed, T.maxRiseSpeed)

        var y = p.position.y + vy * dt
        let minY = waterBottom + p.radius * 0.95
        let maxY = waterTop - p.radius * 0.95
        if y < minY {
            y = minY
            if vy < 0 { vy = -vy * T.boundaryBounce }
        } else if y > maxY {
            y = maxY
            if vy > 0 { vy = -vy * T.boundaryBounce }
        }

        p.velocity = CGVector(dx: playerSpeed, dy: vy)
        p.position = CGPoint(x: world.wrap(p.position.x + playerSpeed * dt), y: y)
        p.facing = 1
    }

    private func moveAI(_ f: Fish, _ dt: CGFloat) {
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
        let desiredVY = ((f.targetY - f.position.y) * 0.9).clamped(-T.aiVerticalSpeed, T.aiVerticalSpeed)
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

    private func advanceGrowth(_ dt: CGFloat) {
        for f in fish {
            if f.growElapsed < T.growDuration {
                f.growElapsed += dt
                let t = min(1, f.growElapsed / T.growDuration)
                let eased = 1 - pow(1 - t, 3)
                f.radius = f.growFrom + (f.targetRadius - f.growFrom) * eased
            }
            if f.pulse > 0 { f.pulse = max(0, f.pulse - dt) }
        }
    }

    // MARK: - Collisions and swallowing

    private func resolveCollisions() {
        let candidates = fish.filter { $0.state == .swimming }
        guard candidates.count > 1 else { return }
        let aiMayEat = T.aiFishCanEatEachOther && simClock >= T.aiEatingGracePeriod

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
            duration: GameRules.swallowDuration(sizeRatio: ratio),
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
        predator.targetRadius = GameRules.grownRadius(predator: predator.targetRadius, prey: prey.radius)
        predator.growFrom = predator.radius
        predator.growElapsed = 0
        predator.pulse = T.pulseDuration

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
        for f in fish {
            guard let node = nodes[f.id] else { continue }
            let screenX = anchorX + world.delta(from: cameraX, to: f.position.x)
            let margin = f.radius * 3
            node.isHidden = screenX < -margin || screenX > size.width + margin
            if node.isHidden { continue }
            node.position = CGPoint(x: screenX, y: f.position.y)

            var stretch: CGFloat = 1
            if f.pulse > 0 {
                stretch += sin((1 - f.pulse / T.pulseDuration) * .pi) * T.pulseAmount
            }
            let stretchX = stretch * (1 + f.squash) * f.shrink
            let stretchY = stretch * (1 - f.squash) * f.shrink

            let rawTilt = f.isPlayer
                ? f.velocity.dy / T.maxRiseSpeed * T.maxTilt
                : f.velocity.dy / T.aiVerticalSpeed * T.aiMaxTilt
            let facingSign: CGFloat = f.facing >= 0 ? 1 : -1
            let tilt = rawTilt.clamped(-T.maxTilt, T.maxTilt) * facingSign
                + f.struggle * sin(realClock * 45) * 0.35

            node.apply(
                radius: f.radius, facing: f.facing, tilt: tilt,
                stretchX: stretchX, stretchY: stretchY,
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

        let gradient = SKSpriteNode(texture: GameScene.gradientTexture())
        gradient.anchorPoint = .zero
        gradient.size = size
        backgroundLayer.addChild(gradient)

        let surface = SKSpriteNode(color: SKColor(white: 1, alpha: 0.22), size: CGSize(width: size.width, height: 2))
        surface.anchorPoint = .zero
        surface.position = CGPoint(x: 0, y: waterTop + 4)
        surface.zPosition = 1
        backgroundLayer.addChild(surface)

        var speckRNG = SeededGenerator(seed: 7)
        let dot = GameScene.dotTexture()
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
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        pauseMenu.addChild(title)

        resumeButton = menuButton("Resume", at: CGPoint(x: size.width / 2, y: size.height / 2 + 5))
        restartButton = menuButton("Restart", at: CGPoint(x: size.width / 2, y: size.height / 2 - 60))
        pauseMenu.addChild(resumeButton)
        pauseMenu.addChild(restartButton)
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

    private static func gradientTexture() -> SKTexture {
        let size = CGSize(width: 4, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [
                UIColor(red: 0.20, green: 0.62, blue: 0.80, alpha: 1).cgColor,
                UIColor(red: 0.08, green: 0.35, blue: 0.60, alpha: 1).cgColor,
                UIColor(red: 0.03, green: 0.12, blue: 0.30, alpha: 1).cgColor,
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }

    private static func dotTexture() -> SKTexture {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return SKTexture(image: image)
    }
}
