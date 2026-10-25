import FishKit
import SpriteKit
import UIKit

/// Something the Open Water's pearls buy for your fish (the shop's list is `GameTuning.pearlShop`): a body color, a
/// pattern, a hat, or a trail. Looks only, never part of what eats or is eaten (that's the fish's radius): colors and
/// patterns stay inside your body, and a hat stands at most `GameTuning.pearlHatHeadroom` above your back fin.
struct PearlItem: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case color, pattern, hat, trail

        var title: String {
            switch self {
            case .color: "Colors"
            case .pattern: "Patterns"
            case .hat: "Hats"
            case .trail: "Trails"
            }
        }

        /// Its mark on the shop's rail (an SF Symbol).
        var symbol: String {
            switch self {
            case .color: "paintpalette.fill"
            case .pattern: "circle.hexagongrid.fill"
            case .hat: "hat.widebrim.fill"
            case .trail: "sparkles"
            }
        }
    }

    /// Saved with what a player owns and wears: never rename one.
    let id: String
    let kind: Kind
    let name: String
    let price: Int
    /// A limited edition's time of year, the only time it's on sale. Whoever bought one keeps it and wears it all year.
    let season: PearlSeason?
    /// What earns it, for one that's never sold: whoever's done it has it.
    let earnedBy: PearlGoal?

    init(_ id: String, _ kind: Kind, _ name: String, price: Int, season: PearlSeason? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.price = price
        self.season = season
        earnedBy = nil
    }

    init(_ id: String, _ kind: Kind, _ name: String, earnedBy goal: PearlGoal) {
        self.id = id
        self.kind = kind
        self.name = name
        price = 0
        season = nil
        earnedBy = goal
    }

    static func item(_ id: String) -> PearlItem? { GameTuning.pearlShop.first { $0.id == id } }

    /// Whether it can be bought on `date`: always, unless it's a limited edition out of its season, or it's earned.
    func onSale(_ date: Date = PearlSeason.today) -> Bool { earnedBy == nil && season?.contains(date) ?? true }
}

/// What earns an item that's never sold (`PearlItem.earnedBy`): something done in an Open Water run, or a world's crown
/// on the map (Kraig, 2026-10-25: "One silver for conquering a world. Gold for conquering a deep end. Diamond for
/// conquering them all."). Each is judged from what's saved, so it counts from before the item existed.
enum PearlGoal: Equatable {
    /// Eat this many fish in one Open Water run.
    case fishInOneRun(Int)
    /// Reach this level of an Open Water run (counting from 0): 2 is Kelp Forest, 5 round all five worlds.
    case openWaterLevel(Int)
    /// A world's ten main levels, any world's Deep End, or every world's Deep End.
    case conquerAWorld, conquerADeepEnd, conquerEveryDeepEnd

    /// The shop tile's few words.
    var short: String {
        switch self {
        case .fishInOneRun(let fish): "\(fish) fish"
        case .openWaterLevel(let level): level < GameTuning.openWaterWorlds.count ? GameTuning.openWaterWorlds[level].title
                                                                                    : "All worlds"
        case .conquerAWorld: "Conquer a world"
        case .conquerADeepEnd: "A Deep End"
        case .conquerEveryDeepEnd: "Every Deep End"
        }
    }

    /// What to do, in full.
    var description: String {
        switch self {
        case .fishInOneRun(let fish): "Eat \(fish) fish in one Open Water run"
        case .openWaterLevel(let level):
            level < GameTuning.openWaterWorlds.count ? "Reach \(GameTuning.openWaterWorlds[level].title) in an Open Water run"
                                                     : "Get round all five worlds in an Open Water run"
        case .conquerAWorld: "Conquer a world: all ten of its levels"
        case .conquerADeepEnd: "Conquer a world's Deep End"
        case .conquerEveryDeepEnd: "Conquer every world's Deep End"
        }
    }
}

/// A time of year a limited edition is on sale, every year: from one day through another, the last day included, and
/// across the new year when the last comes first (Christmas's: Kraig, 2026-10-24, "Dec 1 – Jan 6").
struct PearlSeason: Equatable {
    struct Day: Equatable, Comparable {
        let month: Int
        let day: Int

        static func < (a: Day, b: Day) -> Bool { (a.month, a.day) < (b.month, b.day) }
    }

    let name: String
    let from: Day
    let through: Day
    /// The tile's mark of a limited edition (an SF Symbol).
    let symbol: String

    static let christmas = PearlSeason(name: "Christmas", from: Day(month: 12, day: 1), through: Day(month: 1, day: 6),
                                       symbol: "snowflake")

    /// The calendar a season's days are counted in: the Gregorian, whatever calendar the player prefers (Christmas is in
    /// December in any of them), in the player's own time zone.
    static func calendar(preferring preferred: Calendar = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = preferred.timeZone
        calendar.locale = preferred.locale
        return calendar
    }

    func contains(_ date: Date, calendar: Calendar = PearlSeason.calendar()) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return false }
        let today = Day(month: month, day: day)
        return from <= through ? from <= today && today <= through : today >= from || today <= through
    }

    /// "Dec 1 – Jan 6".
    var dates: String {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar()
        let months = formatter.shortMonthSymbols ?? []
        func name(_ day: Day) -> String { "\(months.indices.contains(day.month - 1) ? months[day.month - 1] : "\(day.month)") \(day.day)" }
        return "\(name(from)) – \(name(through))"
    }

    /// Today, for what's on sale. Xcode builds can pretend it's Christmas, from the shop, to try the season's things.
    static var today: Date {
        #if DEBUG
        let gregorian = calendar()
        if pretendItsChristmas,
           let christmas = gregorian.date(from: DateComponents(year: gregorian.component(.year, from: Date()), month: 12, day: 15)) {
            return christmas
        }
        #endif
        return Date()
    }

    #if DEBUG
    static var pretendItsChristmas = false
    #endif
}

/// What your fish wears: one item of each kind at most, or none (the plain orange fish).
struct PlayerLook: Equatable {
    private(set) var items: [PearlItem.Kind: PearlItem] = [:]

    static let plain = PlayerLook()

    init() {}

    /// From the save (`ArcadeSave.wornLook`): an item each kind, by ID. One this version doesn't know (from a later
    /// version) or filed under the wrong kind is left off.
    init(ids: [String: String]) {
        for (kind, id) in ids {
            guard let kind = PearlItem.Kind(rawValue: kind), let item = PearlItem.item(id), item.kind == kind else { continue }
            items[kind] = item
        }
    }

    var ids: [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.key.rawValue, $0.value.id) }) }

    subscript(kind: PearlItem.Kind) -> PearlItem? { items[kind] }

    /// This look with `item` on in its kind's place.
    func wearing(_ item: PearlItem) -> PlayerLook {
        var look = self
        look.items[item.kind] = item
        return look
    }

    /// This look with nothing of `kind` on.
    func without(_ kind: PearlItem.Kind) -> PlayerLook {
        var look = self
        look.items[kind] = nil
        return look
    }

    /// The fish's colors and built-in pattern (FishKit's spots and stripes).
    var style: FishStyle {
        var style = FishStyle.player
        if let color = self[.color], let colors = PearlShopArt.colors[color.id] {
            style.body = colors.body
            style.accent = colors.accent
        }
        switch self[.pattern]?.id {
        case "pattern.spots": style.pattern = .spots
        case "pattern.stripes": style.pattern = .stripes
        default: break
        }
        return style
    }

    /// A fish drawn in this look (its style, markings and hat). Its trail is the scene's to draw (`PearlTrailMotes`).
    func fish(tailPhase: CGFloat = 0) -> FishNode {
        let node = FishNode(style: style, isPlayer: true, tailPhase: tailPhase)
        dress(node)
        return node
    }

    /// Puts this look's markings and hat on a fish drawn in its `style`.
    func dress(_ node: FishNode) {
        node.setMarkings(self[.pattern].flatMap(PearlShopArt.markings))
        node.setHeadwear(self[.hat].flatMap(PearlShopArt.hat))
    }

    var trail: PearlTrail? { self[.trail].flatMap { PearlTrail(rawValue: $0.id) } }
}

/// What a trail leaves behind you as you swim.
enum PearlTrail: String {
    case bubbles = "trail.bubbles", sparkles = "trail.sparkles", rainbow = "trail.rainbow", cropDuster = "trail.cropduster"
    case comet = "trail.comet"
    case notes = "trail.notes", hearts = "trail.hearts", confetti = "trail.confetti"
}

/// The drawing of everything the shop sells, at FishKit's reference radius (30) facing right.
enum PearlShopArt {
    private static let R = FishNode.referenceRadius

    /// A pearl beside a count (the Open Water's at the top of the screen, and its card's Shop button): white, with a
    /// pale rim and a glint.
    static func pearlIcon(radius: CGFloat) -> SKNode {
        let pearl = SKShapeNode(circleOfRadius: radius)
        pearl.fillColor = SKColor(red: 0.97, green: 0.95, blue: 0.93, alpha: 1)
        pearl.strokeColor = SKColor(red: 0.85, green: 0.78, blue: 0.86, alpha: 1)
        pearl.lineWidth = 1.5
        let shine = SKShapeNode(circleOfRadius: radius * 2 / 7)
        shine.fillColor = .white
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -radius * 2.5 / 7, y: radius * 2.5 / 7)
        shine.zPosition = 1
        pearl.addChild(shine)
        return pearl
    }

    /// Each body color: the body, and the fins and tail. None is another fish's (FishKit's palette), so you can still
    /// find yourself.
    static let colors: [String: (body: SKColor, accent: SKColor)] = [
        "color.gold": (SKColor(red: 1.00, green: 0.80, blue: 0.18, alpha: 1), SKColor(red: 1.00, green: 0.93, blue: 0.55, alpha: 1)),
        "color.ruby": (SKColor(red: 0.88, green: 0.16, blue: 0.26, alpha: 1), SKColor(red: 1.00, green: 0.55, blue: 0.52, alpha: 1)),
        "color.copper": (SKColor(red: 0.78, green: 0.40, blue: 0.17, alpha: 1), SKColor(red: 0.98, green: 0.70, blue: 0.42, alpha: 1)),
        "color.pearl": (SKColor(red: 0.95, green: 0.92, blue: 0.97, alpha: 1), SKColor(red: 0.98, green: 0.74, blue: 0.87, alpha: 1)),
        // Mint chip and royal purple: plain mint and violet are other fish's colors, so their fins set them apart.
        "color.mint": (SKColor(red: 0.62, green: 0.92, blue: 0.80, alpha: 1), SKColor(red: 0.42, green: 0.26, blue: 0.16, alpha: 1)),
        "color.purple": (SKColor(red: 0.52, green: 0.20, blue: 0.68, alpha: 1), SKColor(red: 1.00, green: 0.82, blue: 0.32, alpha: 1)),
    ]

    // MARK: Patterns

    /// Markings for the patterns FishKit doesn't draw itself (`FishNode.setMarkings`).
    static func markings(_ item: PearlItem) -> SKNode? {
        switch item.id {
        case "pattern.bands": clownBands()
        case "pattern.stars": stars()
        case "pattern.champion": championGlow()
        case "pattern.zebra": zebra()
        case "pattern.hearts": polkaHearts()
        default: nil
        }
    }

    /// The body's half-height at `x` (reference radius), a little inside its white outline.
    private static func halfHeight(at x: CGFloat) -> CGFloat {
        let a = FishNode.bodySize.width / 2, b = FishNode.bodySize.height / 2
        return max(0, b * sqrt(max(0, 1 - pow(x / a, 2))) - 2.2)
    }

    /// A clownfish's two white bands, edged in black.
    private static func clownBands() -> SKNode {
        let node = SKNode()
        for (center, width) in [(0.38 * R, 0.3 * R), (-0.5 * R, 0.34 * R)] {
            let left = center - width / 2, right = center + width / 2
            let path = CGMutablePath()
            let steps = 8
            for i in 0...steps {
                let x = left + (right - left) * CGFloat(i) / CGFloat(steps)
                let point = CGPoint(x: x, y: halfHeight(at: x))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            for i in (0...steps).reversed() {
                let x = left + (right - left) * CGFloat(i) / CGFloat(steps)
                path.addLine(to: CGPoint(x: x, y: -halfHeight(at: x)))
            }
            path.closeSubpath()
            let band = SKShapeNode(path: path)
            band.fillColor = .white
            band.strokeColor = .clear
            node.addChild(band)
            for x in [left, right] {
                let edge = CGMutablePath()
                edge.move(to: CGPoint(x: x, y: halfHeight(at: x)))
                edge.addLine(to: CGPoint(x: x, y: -halfHeight(at: x)))
                let line = SKShapeNode(path: edge)
                line.strokeColor = SKColor(white: 0.08, alpha: 0.85)
                line.lineWidth = 2
                line.zPosition = 0.1
                node.addChild(line)
            }
        }
        return node
    }

    /// Little white stars scattered over the body.
    private static func stars() -> SKNode {
        let node = SKNode()
        let spots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
            (-0.72, 0.18, 0.15), (-0.32, 0.5, 0.11), (-0.2, -0.12, 0.14), (0.2, 0.42, 0.1), (0.22, -0.42, 0.11),
            (-0.7, -0.38, 0.1),
        ]
        for (i, spot) in spots.enumerated() {
            let star = SKShapeNode(path: starPath(points: 5, outer: spot.r * R, inner: spot.r * R * 0.45))
            star.position = CGPoint(x: spot.x * R, y: spot.y * R)
            star.zRotation = CGFloat(i) * 0.5
            star.fillColor = SKColor(red: 1, green: 0.98, blue: 0.86, alpha: 0.95)
            star.strokeColor = .clear
            node.addChild(star)
        }
        return node
    }

    /// A zebra's dark stripes, slanting back across the body.
    private static func zebra() -> SKNode {
        let node = SKNode()
        for (index, (center, width)) in [(0.62 * R, 0.1 * R), (0.3 * R, 0.13 * R), (-0.04 * R, 0.14 * R), (-0.38 * R, 0.13 * R),
                                          (-0.7 * R, 0.11 * R), (-0.98 * R, 0.08 * R)].enumerated() {
            let left = center - width / 2, right = center + width / 2, slant = 0.14 * R
            let path = CGMutablePath()
            let steps = 6
            for i in 0...steps {
                let x = left + (right - left) * CGFloat(i) / CGFloat(steps)
                let point = CGPoint(x: x, y: halfHeight(at: x))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            for i in (0...steps).reversed() {
                let x = left + (right - left) * CGFloat(i) / CGFloat(steps) - slant
                path.addLine(to: CGPoint(x: x, y: -halfHeight(at: x)))
            }
            path.closeSubpath()
            let stripe = SKShapeNode(path: path)
            stripe.fillColor = SKColor(white: 0.1, alpha: 0.85)
            stripe.strokeColor = .clear
            stripe.zPosition = CGFloat(index) * 0.01
            node.addChild(stripe)
        }
        return node
    }

    /// Little pink hearts scattered over the body.
    private static func polkaHearts() -> SKNode {
        let node = SKNode()
        let spots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
            (-0.7, 0.2, 0.13), (-0.3, 0.5, 0.11), (-0.18, -0.15, 0.14), (0.22, 0.4, 0.1), (0.25, -0.42, 0.11), (-0.68, -0.4, 0.1),
        ]
        for (i, spot) in spots.enumerated() {
            let heart = SKShapeNode(path: heartPath(spot.size * R))
            heart.position = CGPoint(x: spot.x * R, y: spot.y * R)
            heart.zRotation = CGFloat(i % 3 - 1) * 0.25
            heart.fillColor = SKColor(red: 1, green: 0.45, blue: 0.7, alpha: 0.95)
            heart.strokeColor = .clear
            node.addChild(heart)
        }
        return node
    }

    /// A heart `size` from its middle to its point, pointing down.
    static func heartPath(_ size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -size))
        path.addCurve(to: CGPoint(x: -size, y: 0.35 * size), control1: CGPoint(x: -0.55 * size, y: -0.5 * size),
                      control2: CGPoint(x: -size, y: -0.15 * size))
        path.addArc(center: CGPoint(x: -0.5 * size, y: 0.35 * size), radius: 0.5 * size, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addArc(center: CGPoint(x: 0.5 * size, y: 0.35 * size), radius: 0.5 * size, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: CGPoint(x: 0, y: -size), control1: CGPoint(x: size, y: -0.15 * size),
                      control2: CGPoint(x: 0.55 * size, y: -0.5 * size))
        path.closeSubpath()
        return path
    }

    /// A gold star over your middle, in a warm glow that swells and fades.
    private static func championGlow() -> SKNode {
        let node = SKNode()
        let glow = SKSpriteNode(texture: ArcadeArt.glow, size: CGSize(width: 1.5 * R, height: 1.25 * R))
        glow.color = SKColor(red: 1, green: 0.78, blue: 0.25, alpha: 1)
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.alpha = 0.7
        glow.position = CGPoint(x: -0.1 * R, y: 0)
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.8), .fadeAlpha(to: 0.75, duration: 0.8)])))
        node.addChild(glow)
        let star = SKShapeNode(path: starPath(points: 5, outer: 0.3 * R, inner: 0.13 * R))
        star.position = glow.position
        star.fillColor = SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        star.strokeColor = SKColor(red: 0.7, green: 0.45, blue: 0.05, alpha: 1)
        star.lineWidth = 1.2
        star.zPosition = 0.1
        node.addChild(star)
        return node
    }

    static func starPath(points: Int, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(points) + .pi / 2
            let r = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Hats

    /// A hat for `FishNode.setHeadwear`. It's drawn around the headwear's spot (just above the body, ahead of the back
    /// fin) and sits down onto the body from there. It may stand up to `GameTuning.pearlHatHeadroom` above the fin's top
    /// (`PearlShopTests.nothingMakesYouLookBigger`): it's only drawn, never part of what eats or is eaten (that's the
    /// fish's radius).
    static func hat(_ item: PearlItem) -> SKNode? {
        let hat: SKNode
        switch item.id {
        case "hat.beanie": hat = beanie()
        case "hat.flower": hat = flower()
        case "hat.sailor": hat = sailorCap()
        case "hat.cone": hat = trafficCone()
        case "hat.crown": hat = crown(.gold)
        case "hat.crown.silver": hat = crown(.silver)
        case "hat.crown.diamond": hat = crown(.diamond)
        case "hat.starfish": hat = starfish()
        case "hat.party": hat = partyHat()
        case "hat.bow": hat = bow()
        case "hat.cowboy": hat = cowboyHat()
        case "hat.pirate": hat = pirateHat()
        case "hat.wizard": hat = wizardHat()
        case "hat.unicorn": hat = unicornHorn()
        case "hat.sharkfin": hat = sharkFin()
        case "hat.baseball": hat = baseballCap()
        case "hat.tiara": hat = tiara()
        case "hat.santa": hat = santaHat()
        case "hat.antlers": hat = antlers()
        default: return nil
        }
        // Down onto the body (its top is about this far below the headwear's spot).
        hat.position = CGPoint(x: 0, y: -0.2 * R)
        let worn = SKNode()
        worn.addChild(hat)
        return worn
    }

    private static func shape(_ path: CGPath, fill: SKColor, stroke: SKColor = SKColor(white: 0.1, alpha: 0.7),
                              line: CGFloat = 1.5, z: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = line
        node.zPosition = z
        return node
    }

    private static func ball(_ radius: CGFloat, at center: CGPoint, fill: SKColor, z: CGFloat) -> SKShapeNode {
        shape(CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
                     transform: nil), fill: fill, line: 1.2, z: z)
    }

    private static func beanie() -> SKNode {
        let node = SKNode()
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: -9.5, y: 0))
        dome.addQuadCurve(to: CGPoint(x: 9.5, y: 0), control: CGPoint(x: 0, y: 20))
        dome.closeSubpath()
        node.addChild(shape(dome, fill: SKColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1), z: 0))
        let cuff = CGPath(roundedRect: CGRect(x: -10.5, y: -2.5, width: 21, height: 4.5), cornerWidth: 2, cornerHeight: 2, transform: nil)
        node.addChild(shape(cuff, fill: SKColor(red: 0.85, green: 0.93, blue: 1, alpha: 1), z: 0.1))
        node.addChild(ball(3, at: CGPoint(x: 0, y: 11.5), fill: SKColor(red: 0.85, green: 0.93, blue: 1, alpha: 1), z: 0.2))
        return node
    }

    private static func flower() -> SKNode {
        let node = SKNode()
        let middle = CGPoint(x: 0, y: 6)
        for i in 0..<5 {
            let angle = CGFloat(i) * 2 * .pi / 5 + .pi / 2
            let petal = SKShapeNode(circleOfRadius: 3.8)
            petal.position = CGPoint(x: middle.x + cos(angle) * 4.4, y: middle.y + sin(angle) * 4.4)
            petal.fillColor = SKColor(red: 1, green: 0.55, blue: 0.75, alpha: 1)
            petal.strokeColor = SKColor(red: 0.75, green: 0.25, blue: 0.45, alpha: 0.8)
            petal.lineWidth = 1
            petal.zPosition = CGFloat(i) * 0.01
            node.addChild(petal)
        }
        let center = SKShapeNode(circleOfRadius: 2.8)
        center.position = middle
        center.fillColor = SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)
        center.strokeColor = .clear
        center.zPosition = 0.1
        node.addChild(center)
        return node
    }

    private static func sailorCap() -> SKNode {
        let node = SKNode()
        let top = CGPath(ellipseIn: CGRect(x: -11, y: 6, width: 22, height: 7), transform: nil)
        node.addChild(shape(top, fill: .white, z: 0))
        let crown = CGPath(roundedRect: CGRect(x: -8, y: -1.5, width: 16, height: 10), cornerWidth: 2, cornerHeight: 2, transform: nil)
        node.addChild(shape(crown, fill: .white, z: 0.1))
        let band = CGPath(rect: CGRect(x: -8, y: -1.5, width: 16, height: 3.2), transform: nil)
        node.addChild(shape(band, fill: SKColor(red: 0.1, green: 0.16, blue: 0.4, alpha: 1), line: 1, z: 0.2))
        let brim = CGMutablePath()
        brim.move(to: CGPoint(x: 6.5, y: -1.5))
        brim.addQuadCurve(to: CGPoint(x: 14, y: -2.5), control: CGPoint(x: 10.5, y: 1.5))
        brim.addLine(to: CGPoint(x: 6.5, y: -1.5))
        node.addChild(shape(brim, fill: SKColor(white: 0.1, alpha: 1), line: 1, z: 0.3))
        return node
    }

    /// An orange cone with two white bands, on its square base.
    private static func trafficCone() -> SKNode {
        let node = SKNode()
        let base = CGPath(roundedRect: CGRect(x: -9, y: -2.5, width: 18, height: 3), cornerWidth: 1.2, cornerHeight: 1.2,
                          transform: nil)
        node.addChild(shape(base, fill: SKColor(red: 0.8, green: 0.28, blue: 0.04, alpha: 1), z: 0))
        // The cone's half-width at a height.
        let height: CGFloat = 19
        let half = { (y: CGFloat) in 6.5 - 5.2 * y / height }
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: -half(0), y: 0))
        cone.addLine(to: CGPoint(x: -half(height), y: height))
        cone.addQuadCurve(to: CGPoint(x: half(height), y: height), control: CGPoint(x: 0, y: height + 0.8))
        cone.addLine(to: CGPoint(x: half(0), y: 0))
        cone.closeSubpath()
        node.addChild(shape(cone, fill: SKColor(red: 1, green: 0.42, blue: 0.05, alpha: 1), z: 0.1))
        for (index, (low, high)) in [(CGFloat(4.5), CGFloat(7.5)), (11, 13.8)].enumerated() {
            let band = CGMutablePath()
            band.move(to: CGPoint(x: -half(low), y: low))
            band.addLine(to: CGPoint(x: -half(high), y: high))
            band.addLine(to: CGPoint(x: half(high), y: high))
            band.addLine(to: CGPoint(x: half(low), y: low))
            band.closeSubpath()
            node.addChild(shape(band, fill: .white, stroke: .clear, line: 0, z: 0.2 + CGFloat(index) * 0.01))
        }
        return node
    }

    /// A crown's metal, rim, and jewel: gold (the original), silver, or diamond, like the map's crowns and beyond.
    private enum Crown {
        case gold, silver, diamond

        var metal: SKColor {
            switch self {
            case .gold: SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
            case .silver: SKColor(red: 0.86, green: 0.88, blue: 0.93, alpha: 1)
            case .diamond: SKColor(red: 0.78, green: 0.93, blue: 1, alpha: 1)
            }
        }

        var rim: SKColor {
            switch self {
            case .gold: SKColor(red: 0.6, green: 0.4, blue: 0.05, alpha: 1)
            case .silver: SKColor(red: 0.45, green: 0.48, blue: 0.56, alpha: 1)
            case .diamond: SKColor(red: 0.3, green: 0.58, blue: 0.82, alpha: 1)
            }
        }

        var jewel: SKColor {
            switch self {
            case .gold: SKColor(red: 0.9, green: 0.15, blue: 0.3, alpha: 1)
            case .silver: SKColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 1)
            case .diamond: .white
            }
        }
    }

    private static func crown(_ kind: Crown) -> SKNode {
        let node = SKNode()
        let gold = kind.metal
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -9, y: -2))
        path.addLine(to: CGPoint(x: -9, y: 10))
        path.addLine(to: CGPoint(x: -4.5, y: 4.5))
        path.addLine(to: CGPoint(x: 0, y: 13))
        path.addLine(to: CGPoint(x: 4.5, y: 4.5))
        path.addLine(to: CGPoint(x: 9, y: 10))
        path.addLine(to: CGPoint(x: 9, y: -2))
        path.closeSubpath()
        node.addChild(shape(path, fill: gold, stroke: kind.rim, line: 1.2, z: 0))
        for (index, tip) in [CGPoint(x: -9, y: 10), CGPoint(x: 0, y: 13), CGPoint(x: 9, y: 10)].enumerated() {
            node.addChild(ball(1.5, at: tip, fill: kind == .diamond ? .white : gold, z: 0.1 + CGFloat(index) * 0.01))
        }
        if kind == .diamond {
            // A cut stone, its facets catching the light.
            let stone = CGMutablePath()
            stone.move(to: CGPoint(x: 0, y: 5.2))
            stone.addLine(to: CGPoint(x: 2.6, y: 2.4))
            stone.addLine(to: CGPoint(x: 0, y: -0.8))
            stone.addLine(to: CGPoint(x: -2.6, y: 2.4))
            stone.closeSubpath()
            node.addChild(shape(stone, fill: .white, stroke: kind.rim, line: 1, z: 0.2))
            return node
        }
        let jewel = SKShapeNode(circleOfRadius: 2)
        jewel.position = CGPoint(x: 0, y: 2)
        jewel.fillColor = kind.jewel
        jewel.strokeColor = .clear
        jewel.zPosition = 0.2
        node.addChild(jewel)
        return node
    }

    /// A striped cone of a party hat, a pompom on its point.
    private static func partyHat() -> SKNode {
        let node = SKNode()
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: -8, y: 0))
        cone.addLine(to: CGPoint(x: 1.5, y: 16))
        cone.addLine(to: CGPoint(x: 8, y: 0))
        cone.closeSubpath()
        node.addChild(shape(cone, fill: SKColor(red: 0.3, green: 0.8, blue: 0.95, alpha: 1), z: 0))
        for (index, (y, color)) in [(CGFloat(3.5), SKColor(red: 1, green: 0.4, blue: 0.7, alpha: 1)),
                                    (9, SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1))].enumerated() {
            let half = 8 * (1 - y / 16), x = 1.5 * y / 16
            let band = CGMutablePath()
            band.move(to: CGPoint(x: x - half, y: y))
            band.addLine(to: CGPoint(x: x + 1.5 * 2.2 / 16 - half * (1 - 2.2 / (16 - y)), y: y + 2.2))
            band.addLine(to: CGPoint(x: x + 1.5 * 2.2 / 16 + half * (1 - 2.2 / (16 - y)), y: y + 2.2))
            band.addLine(to: CGPoint(x: x + half, y: y))
            band.closeSubpath()
            node.addChild(shape(band, fill: color, stroke: .clear, line: 0, z: 0.1 + CGFloat(index) * 0.01))
        }
        node.addChild(ball(2.5, at: CGPoint(x: 1.5, y: 16), fill: SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1), z: 0.2))
        return node
    }

    /// A big pink bow: two loops and the knot between.
    private static func bow() -> SKNode {
        let node = SKNode()
        let pink = SKColor(red: 1, green: 0.42, blue: 0.68, alpha: 1)
        for (index, side) in [CGFloat(-1), 1].enumerated() {
            let loop = CGMutablePath()
            loop.move(to: CGPoint(x: 0, y: 4))
            loop.addQuadCurve(to: CGPoint(x: side * 10, y: 9), control: CGPoint(x: side * 5, y: 12))
            loop.addQuadCurve(to: CGPoint(x: side * 9, y: -1), control: CGPoint(x: side * 12.5, y: 4))
            loop.addQuadCurve(to: CGPoint(x: 0, y: 4), control: CGPoint(x: side * 4, y: 0))
            loop.closeSubpath()
            node.addChild(shape(loop, fill: pink, z: CGFloat(index) * 0.01))
        }
        node.addChild(ball(2.8, at: CGPoint(x: 0, y: 4), fill: SKColor(red: 0.9, green: 0.25, blue: 0.52, alpha: 1), z: 0.1))
        return node
    }

    /// A brown cowboy hat: its dented crown and band, and a wide brim curling up at the sides.
    private static func cowboyHat() -> SKNode {
        let node = SKNode()
        let crown = CGMutablePath()
        crown.move(to: CGPoint(x: -7.5, y: 1))
        crown.addLine(to: CGPoint(x: -6.5, y: 11))
        crown.addQuadCurve(to: CGPoint(x: 0, y: 10.5), control: CGPoint(x: -3.5, y: 13))
        crown.addQuadCurve(to: CGPoint(x: 6.5, y: 11), control: CGPoint(x: 3.5, y: 13))
        crown.addLine(to: CGPoint(x: 7.5, y: 1))
        crown.closeSubpath()
        node.addChild(shape(crown, fill: SKColor(red: 0.66, green: 0.43, blue: 0.22, alpha: 1), z: 0))
        let band = CGPath(rect: CGRect(x: -7.4, y: 1.5, width: 14.8, height: 2.6), transform: nil)
        node.addChild(shape(band, fill: SKColor(red: 0.3, green: 0.18, blue: 0.1, alpha: 1), line: 1, z: 0.1))
        let brim = CGMutablePath()
        brim.move(to: CGPoint(x: -15, y: 4.5))
        brim.addQuadCurve(to: CGPoint(x: 15, y: 4.5), control: CGPoint(x: 0, y: -5))
        brim.addQuadCurve(to: CGPoint(x: -15, y: 4.5), control: CGPoint(x: 0, y: 0.5))
        brim.closeSubpath()
        node.addChild(shape(brim, fill: SKColor(red: 0.56, green: 0.35, blue: 0.17, alpha: 1), z: 0.2))
        return node
    }

    /// A black pirate's hat, gold along its edge and a white skull on the front.
    private static func pirateHat() -> SKNode {
        let node = SKNode()
        let hat = CGMutablePath()
        hat.move(to: CGPoint(x: -13, y: 1))
        hat.addQuadCurve(to: CGPoint(x: 0, y: 14), control: CGPoint(x: -8, y: 15))
        hat.addQuadCurve(to: CGPoint(x: 13, y: 1), control: CGPoint(x: 8, y: 15))
        hat.addQuadCurve(to: CGPoint(x: -13, y: 1), control: CGPoint(x: 0, y: 5))
        hat.closeSubpath()
        node.addChild(shape(hat, fill: SKColor(white: 0.12, alpha: 1), stroke: SKColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1),
                            line: 1.4, z: 0))
        for (index, (from, to)) in [(CGPoint(x: -3.2, y: 3.6), CGPoint(x: 3.2, y: 7.6)),
                                    (CGPoint(x: -3.2, y: 7.6), CGPoint(x: 3.2, y: 3.6))].enumerated() {
            let bone = CGMutablePath()
            bone.move(to: from)
            bone.addLine(to: to)
            let line = shape(bone, fill: .clear, stroke: .white, line: 1.4, z: 0.1 + CGFloat(index) * 0.01)
            line.lineCap = .round
            node.addChild(line)
        }
        node.addChild(ball(2.4, at: CGPoint(x: 0, y: 8.4), fill: .white, z: 0.2))
        return node
    }

    /// A wizard's tall purple hat, its point flopping back, stars on it.
    private static func wizardHat() -> SKNode {
        let node = SKNode()
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: -7, y: 0))
        cone.addQuadCurve(to: CGPoint(x: -7, y: 18.5), control: CGPoint(x: -2, y: 12))
        cone.addQuadCurve(to: CGPoint(x: 7, y: 0), control: CGPoint(x: 4, y: 12))
        cone.closeSubpath()
        node.addChild(shape(cone, fill: SKColor(red: 0.4, green: 0.22, blue: 0.75, alpha: 1), z: 0))
        let brim = CGPath(ellipseIn: CGRect(x: -11.5, y: -2, width: 23, height: 4.5), transform: nil)
        node.addChild(shape(brim, fill: SKColor(red: 0.32, green: 0.16, blue: 0.62, alpha: 1), z: 0.1))
        for (index, (x, y, r)) in [(CGFloat(-1), CGFloat(5.5), CGFloat(2.4)), (-3, 11, 1.6)].enumerated() {
            let star = shape(starPath(points: 5, outer: r, inner: r * 0.45), fill: SKColor(red: 1, green: 0.88, blue: 0.35, alpha: 1),
                             stroke: .clear, line: 0, z: 0.2 + CGFloat(index) * 0.01)
            star.position = CGPoint(x: x, y: y)
            node.addChild(star)
        }
        return node
    }

    /// A unicorn's horn, pale gold with its spiral, leaning forward.
    private static func unicornHorn() -> SKNode {
        let node = SKNode()
        let horn = CGMutablePath()
        horn.move(to: CGPoint(x: -4, y: 0))
        horn.addLine(to: CGPoint(x: 5, y: 17))
        horn.addLine(to: CGPoint(x: 4, y: 0))
        horn.closeSubpath()
        node.addChild(shape(horn, fill: SKColor(red: 1, green: 0.92, blue: 0.62, alpha: 1),
                            stroke: SKColor(red: 0.8, green: 0.58, blue: 0.2, alpha: 1), line: 1.3, z: 0))
        for (index, y) in [CGFloat(3.5), 7.5, 11.5].enumerated() {
            let along = y / 17, half = 4 * (1 - along), x = 5 * along
            let twist = CGMutablePath()
            twist.move(to: CGPoint(x: x - half, y: y - 1.2))
            twist.addLine(to: CGPoint(x: x + half, y: y + 1.2))
            node.addChild(shape(twist, fill: .clear, stroke: SKColor(red: 0.95, green: 0.55, blue: 0.75, alpha: 1), line: 1.3,
                                z: 0.1 + CGFloat(index) * 0.01))
        }
        return node
    }

    /// A starfish sitting on your head at a tilt, its arms dotted.
    private static func starfish() -> SKNode {
        let node = SKNode()
        let star = shape(starPath(points: 5, outer: 10, inner: 4.6), fill: SKColor(red: 1, green: 0.55, blue: 0.42, alpha: 1),
                         stroke: SKColor(red: 0.7, green: 0.25, blue: 0.2, alpha: 1), line: 1.3, z: 0)
        star.position = CGPoint(x: 0, y: 7)
        star.zRotation = 0.25
        node.addChild(star)
        for i in 0..<5 {
            let angle = CGFloat(i) * 2 * .pi / 5 + .pi / 2 + 0.25
            let dot = SKShapeNode(circleOfRadius: 1)
            dot.position = CGPoint(x: cos(angle) * 5.4, y: 7 + sin(angle) * 5.4)
            dot.fillColor = SKColor(red: 1, green: 0.85, blue: 0.75, alpha: 1)
            dot.strokeColor = .clear
            dot.zPosition = 0.1 + CGFloat(i) * 0.01
            node.addChild(dot)
        }
        return node
    }

    /// A shark's grey fin over the middle of your back, swept back, hiding your own back fin (Kraig, 2026-10-25: "the
    /// shark fin needs to be further back"). It stands upright: headwear sits tilted forward.
    private static func sharkFin() -> SKNode {
        let node = SKNode()
        let fin = SKNode()
        fin.position = CGPoint(x: -21, y: -3.4)
        fin.zRotation = 0.25
        node.addChild(fin)
        // Its front edge bows up and back to the tip, which hangs behind the back edge's foot.
        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: 13, y: 0))
        outline.addQuadCurve(to: CGPoint(x: -12, y: 16), control: CGPoint(x: 8, y: 14))
        outline.addQuadCurve(to: CGPoint(x: -8, y: 0), control: CGPoint(x: -7, y: 5))
        outline.closeSubpath()
        fin.addChild(shape(outline, fill: SKColor(red: 0.52, green: 0.6, blue: 0.68, alpha: 1),
                           stroke: SKColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1), line: 1.4, z: 0))
        let shine = CGMutablePath()
        shine.move(to: CGPoint(x: 8.5, y: 2))
        shine.addQuadCurve(to: CGPoint(x: -4, y: 11), control: CGPoint(x: 5, y: 9.5))
        fin.addChild(shape(shine, fill: .clear, stroke: SKColor(white: 1, alpha: 0.35), line: 1.5, z: 0.1))
        return node
    }

    /// A blue cap with its button on top and its bill out over your eye.
    private static func baseballCap() -> SKNode {
        let node = SKNode()
        let blue = SKColor(red: 0.13, green: 0.38, blue: 0.86, alpha: 1)
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: -10, y: -1.5))
        dome.addQuadCurve(to: CGPoint(x: 9, y: -1.5), control: CGPoint(x: -1, y: 18))
        dome.closeSubpath()
        node.addChild(shape(dome, fill: blue, z: 0))
        let seam = CGMutablePath()
        seam.move(to: CGPoint(x: -0.5, y: 8))
        seam.addQuadCurve(to: CGPoint(x: 2.5, y: -1.5), control: CGPoint(x: 2, y: 4))
        node.addChild(shape(seam, fill: .clear, stroke: SKColor(white: 1, alpha: 0.35), line: 1, z: 0.1))
        node.addChild(ball(1.7, at: CGPoint(x: -0.5, y: 8.4), fill: blue, z: 0.2))
        let bill = CGMutablePath()
        bill.move(to: CGPoint(x: 5, y: -1.5))
        bill.addQuadCurve(to: CGPoint(x: 17, y: -3.2), control: CGPoint(x: 13, y: 1.8))
        bill.addQuadCurve(to: CGPoint(x: 5, y: -1.5), control: CGPoint(x: 12, y: -3.8))
        bill.closeSubpath()
        node.addChild(shape(bill, fill: SKColor(red: 0.08, green: 0.26, blue: 0.66, alpha: 1), z: 0.3))
        return node
    }

    /// A silver band rising to three points, a pink jewel in the middle and a blue one either side.
    private static func tiara() -> SKNode {
        let node = SKNode()
        let silver = SKColor(red: 0.9, green: 0.92, blue: 0.97, alpha: 1)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -10, y: -1.5))
        path.addLine(to: CGPoint(x: -10, y: 1.5))
        path.addQuadCurve(to: CGPoint(x: -5.5, y: 6.5), control: CGPoint(x: -8.5, y: 5))
        path.addQuadCurve(to: CGPoint(x: 0, y: 11.5), control: CGPoint(x: -2.5, y: 6.5))
        path.addQuadCurve(to: CGPoint(x: 5.5, y: 6.5), control: CGPoint(x: 2.5, y: 6.5))
        path.addQuadCurve(to: CGPoint(x: 10, y: 1.5), control: CGPoint(x: 8.5, y: 5))
        path.addLine(to: CGPoint(x: 10, y: -1.5))
        path.closeSubpath()
        node.addChild(shape(path, fill: silver, stroke: SKColor(red: 0.5, green: 0.53, blue: 0.65, alpha: 1), line: 1.2, z: 0))
        node.addChild(ball(2.2, at: CGPoint(x: 0, y: 5), fill: SKColor(red: 1, green: 0.35, blue: 0.65, alpha: 1), z: 0.1))
        for (index, x) in [CGFloat(-5.5), 5.5].enumerated() {
            node.addChild(ball(1.3, at: CGPoint(x: x, y: 2.6), fill: SKColor(red: 0.35, green: 0.75, blue: 1, alpha: 1),
                               z: 0.11 + CGFloat(index) * 0.01))
        }
        return node
    }

    /// A red hat flopping back, with its white fur brim and pompom.
    private static func santaHat() -> SKNode {
        let node = SKNode()
        let hat = CGMutablePath()
        hat.move(to: CGPoint(x: -9.5, y: 0))
        hat.addLine(to: CGPoint(x: 9.5, y: 0))
        hat.addQuadCurve(to: CGPoint(x: -2, y: 15), control: CGPoint(x: 8, y: 13))
        hat.addQuadCurve(to: CGPoint(x: -15, y: 6.5), control: CGPoint(x: -10, y: 15.5))
        hat.addQuadCurve(to: CGPoint(x: -9.5, y: 0), control: CGPoint(x: -11, y: 4))
        hat.closeSubpath()
        node.addChild(shape(hat, fill: SKColor(red: 0.86, green: 0.1, blue: 0.13, alpha: 1), z: 0))
        let brim = CGPath(roundedRect: CGRect(x: -11, y: -2.5, width: 22, height: 5), cornerWidth: 2.5, cornerHeight: 2.5,
                          transform: nil)
        node.addChild(shape(brim, fill: .white, z: 0.1))
        node.addChild(ball(3.2, at: CGPoint(x: -15.5, y: 6), fill: .white, z: 0.2))
        return node
    }

    /// A reindeer's antlers, a branch of two tines each, the back one a little behind the front.
    private static func antlers() -> SKNode {
        let node = SKNode()
        for (index, base) in [CGFloat(-6), 5].enumerated() {
            let antler = CGMutablePath()
            antler.move(to: CGPoint(x: base, y: -1))
            antler.addQuadCurve(to: CGPoint(x: base - 4, y: 16), control: CGPoint(x: base + 2, y: 9))
            antler.move(to: CGPoint(x: base + 0.7, y: 6.5))
            antler.addLine(to: CGPoint(x: base + 5, y: 10.5))
            antler.move(to: CGPoint(x: base - 1.6, y: 11.5))
            antler.addLine(to: CGPoint(x: base + 2.5, y: 15))
            // A dark outline under the antler's own brown: the back one drawn under the front.
            let depth = CGFloat(index) * 0.1
            let outline = shape(antler, fill: .clear, stroke: SKColor(red: 0.3, green: 0.17, blue: 0.07, alpha: 1), line: 4.4,
                                z: depth)
            let brown = shape(antler, fill: .clear, stroke: SKColor(red: 0.66, green: 0.44, blue: 0.24, alpha: 1), line: 2.6,
                              z: depth + 0.05)
            for part in [outline, brown] {
                part.lineCap = .round
                part.lineJoin = .round
                node.addChild(part)
            }
        }
        return node
    }

    // MARK: Trails

    /// A trail's mote: its texture, how it's blended, and its size against your radius.
    static func mote(_ trail: PearlTrail) -> (texture: SKTexture, additive: Bool, size: CGFloat) {
        switch trail {
        case .bubbles: (bubbleTexture, false, 0.42)
        case .sparkles: (sparkleTexture, true, 0.62)
        case .rainbow: (ArcadeArt.glow, true, 0.7)
        case .cropDuster: (puffTexture, false, 0.6)
        case .comet: (ArcadeArt.glow, true, 0.8)
        case .notes: (noteTextures[0], false, 0.55)
        case .hearts: (heartTexture, false, 0.45)
        case .confetti: (confettiTexture, false, 0.3)
        }
    }

    private static let bubbleTexture: SKTexture = {
        let side: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(white: 1, alpha: 0.2).cgColor)
            cg.fillEllipse(in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.9).cgColor)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: CGRect(x: 2.5, y: 2.5, width: side - 5, height: side - 5))
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: side * 0.24, y: side * 0.2, width: side * 0.24, height: side * 0.24))
        }
        return SKTexture(image: image)
    }()

    /// Two music notes, white: a quaver, then a pair.
    static let noteTextures: [SKTexture] = ["\u{266A}", "\u{266B}"].map { glyph in
        let side: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let text = NSAttributedString(string: glyph, attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .bold),
                                                                      .foregroundColor: UIColor.white])
            let size = text.size()
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
        return SKTexture(image: image)
    }

    private static let heartTexture: SKTexture = {
        let side: CGFloat = 32
        let symbol = UIImage(systemName: "heart.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold))!
            .withTintColor(UIColor(red: 1, green: 0.35, blue: 0.6, alpha: 1), renderingMode: .alwaysOriginal)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            symbol.draw(at: CGPoint(x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2))
        }
        return SKTexture(image: image)
    }()

    /// A strip of paper, white, for each mote to take its own color.
    private static let confettiTexture: SKTexture = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.addPath(CGPath(roundedRect: CGRect(x: 8, y: 3, width: 8, height: 18), cornerWidth: 2, cornerHeight: 2,
                                             transform: nil))
            context.cgContext.fillPath()
        }
        return SKTexture(image: image)
    }()

    /// A little cloud of gas: three soft green puffs.
    private static let puffTexture: SKTexture = {
        let side: CGFloat = 48
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 0.62, green: 0.74, blue: 0.22, alpha: 0.75).cgColor)
            for (x, y, r) in [(0.5, 0.42, 0.3), (0.3, 0.6, 0.22), (0.7, 0.62, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
                cg.fillEllipse(in: CGRect(x: (x - r) * side, y: (y - r) * side, width: 2 * r * side, height: 2 * r * side))
            }
            cg.setFillColor(UIColor(red: 0.85, green: 0.92, blue: 0.5, alpha: 0.55).cgColor)
            cg.fillEllipse(in: CGRect(x: 0.36 * side, y: 0.26 * side, width: 0.18 * side, height: 0.16 * side))
        }
        return SKTexture(image: image)
    }()

    private static let sparkleTexture: SKTexture = {
        let side: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.translateBy(x: side / 2, y: side / 2)
            cg.addPath(starPath(points: 4, outer: side / 2 - 1, inner: side * 0.11))
            cg.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).cgColor)
            cg.fillPath()
        }
        return SKTexture(image: image)
    }()
}

/// The motes a trail leaves (`PearlTrail`): each let go behind your tail where you were and left in the water as you
/// swim on, rising or twinkling as it fades. Nothing here touches the game: no random numbers, only the clock.
final class PearlTrailMotes {
    private struct Mote {
        let node: SKSpriteNode
        let at: CGPoint
        let born: CGFloat
        let index: Int
    }
    private var motes: [Mote] = []
    private var next: CGFloat = 0
    private var count = 0

    /// Lets out a mote, if one's due, behind a fish at `position` (in the water's coordinates) with `radius`, facing
    /// `facing`.
    func release(_ trail: PearlTrail, position: CGPoint, radius: CGFloat, facing: CGFloat, time: CGFloat,
                 into parent: SKNode, z: CGFloat) {
        guard time >= next else { return }
        next = time + GameTuning.pearlTrailEvery[trail]!
        count += 1
        let look = PearlShopArt.mote(trail)
        let node = SKSpriteNode(texture: look.texture)
        let side = look.size * radius
        node.size = CGSize(width: side, height: side)
        if look.additive { node.blendMode = .add }
        if trail == .rainbow {
            node.color = SKColor(hue: (CGFloat(count) * 0.045).truncatingRemainder(dividingBy: 1), saturation: 0.85,
                                 brightness: 1, alpha: 1)
            node.colorBlendFactor = 1
        } else if trail == .comet {
            // White-hot at your tail, cooling to orange along the tail.
            node.color = SKColor(red: 1, green: 0.88, blue: 0.6, alpha: 1)
            node.colorBlendFactor = 1
        } else if trail == .notes {
            node.texture = PearlShopArt.noteTextures[count % 2]
        } else if trail == .confetti {
            node.color = SKColor(hue: (CGFloat(count) * 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 1,
                                 alpha: 1)
            node.colorBlendFactor = 1
        }
        // A hair apart each, so two can't swap places as they're drawn.
        node.zPosition = z + CGFloat(count % 50) * 0.0001
        node.alpha = 0
        parent.addChild(node)
        let behind: CGFloat = facing < 0 ? 1.55 : -1.55
        let wobble = sin(CGFloat(count) * 2.39996) * 0.28
        motes.append(Mote(node: node, at: CGPoint(x: position.x + behind * radius, y: position.y + wobble * radius),
                          born: time, index: count))
    }

    /// Every mote where it was let go (`place` turns the water's coordinates into the scene's), at `scale` (the
    /// camera's zoom), as old as it is.
    func render(_ trail: PearlTrail?, time: CGFloat, scale: CGFloat, place: (CGPoint) -> CGPoint) {
        guard !motes.isEmpty else { return }
        motes.removeAll { mote in
            let age = time - mote.born
            guard let trail, let life = GameTuning.pearlTrailSeconds[trail], age < life else {
                mote.node.removeFromParent()
                return true
            }
            let t = age / life
            var point = place(mote.at)
            var size: CGFloat = 1
            switch trail {
            case .bubbles:
                point.x += sin(age * 9 + CGFloat(mote.index)) * 1.5
                point.y += age * 26
                size = 0.8 + 0.4 * t
            case .sparkles:
                size = (1 - t) * (0.75 + 0.25 * sin(age * 30 + CGFloat(mote.index)))
                mote.node.zRotation = CGFloat(mote.index) * 0.7 + age * 2
            case .rainbow:
                size = 1 - 0.6 * t
            case .comet:
                size = 1 - 0.75 * t
                mote.node.color = SKColor(red: 1, green: 0.88 - 0.4 * t, blue: 0.6 - 0.5 * t, alpha: 1)
            case .notes:
                // Floating up, swaying as they go.
                point.x += sin(age * 6 + CGFloat(mote.index)) * 3
                point.y += age * 30
                size = 1 - 0.3 * t
                mote.node.zRotation = sin(age * 4 + CGFloat(mote.index)) * 0.3
            case .hearts:
                point.y += age * 22
                size = (1 - 0.4 * t) * (0.9 + 0.1 * sin(age * 14))
            case .confetti:
                // Tumbling down.
                point.x += sin(age * 8 + CGFloat(mote.index)) * 2
                point.y -= age * 24
                mote.node.zRotation = age * 7 + CGFloat(mote.index)
            case .cropDuster:
                // Each puff swells and drifts up as it hangs in the water behind you.
                point.x += sin(age * 5 + CGFloat(mote.index)) * 2
                point.y += age * 14
                size = 0.55 + 0.75 * t
                mote.node.zRotation = CGFloat(mote.index) * 1.3
            }
            mote.node.position = point
            mote.node.setScale(scale * size)
            mote.node.alpha = min(1, age / 0.06) * (1 - t)
            return false
        }
    }

    func removeAll() {
        for mote in motes { mote.node.removeFromParent() }
        motes.removeAll()
        next = 0
    }
}
