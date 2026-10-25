import FishKit
import SpriteKit
import SwiftUI

extension ArcadeWorld {
    var color: Color { Color(uiColor: mapColor) }
    var mapColor: UIColor {
        switch self {
        case .shallowReef: UIColor(red: 0.18, green: 0.78, blue: 0.72, alpha: 1)
        case .jellyBloom: UIColor(red: 0.75, green: 0.52, blue: 1, alpha: 1)
        case .kelpForest: UIColor(red: 0.45, green: 0.78, blue: 0.32, alpha: 1)
        case .midnightZone: UIColor(red: 1, green: 0.66, blue: 0.3, alpha: 1)
        case .sunsetCove: UIColor(red: 1, green: 0.5, blue: 0.56, alpha: 1)
        case .riptideReef: UIColor(red: 0.95, green: 0.42, blue: 0.62, alpha: 1)
        }
    }
}

struct ArcadeWorldMap: View {
    @ObservedObject var progress: ArcadeProgress
    /// The unlock is bought (or not on sale): every world is open.
    let unlocked: Bool
    let onSelect: (ArcadeWorld) -> Void
    /// The unlock's screen, featuring the world tapped (nil from the Unlock button).
    let onUnlock: (ArcadeWorld?) -> Void
    /// Settings: sound, vibration, the tutorial, restoring, privacy and support.
    let onSettings: () -> Void
    /// The Open Water, the endless run's prototype: a button beside Settings in Xcode builds, none otherwise.
    var onOpenWater: (() -> Void)? = nil
    /// The pearl shop, the Open Water's: a button beside it, showing your pearls, in Xcode builds only.
    var onPearlShop: (() -> Void)? = nil

    var body: some View {
        ScreenScaled { size, _ in
            // On a screen taller than a phone's (an iPad), the stops keep a phone's spread, in the middle.
            let spread = min(size.height, ScreenFit.largestPhone.height)
            let worlds = ArcadeWorld.mapWorlds
            // A stop per world: the campaign's five, and in Xcode builds the prototypes after them. When they don't
            // fit the screen, the map runs on past its edge and scrolls.
            let stops = Self.stops(count: worlds.count, in: CGSize(width: size.width, height: spread))
            let width = stops.width
            let centers = stops.centers.map { CGPoint(x: $0.x, y: $0.y + (size.height - spread) / 2) }
            // The first open world with main levels left, else the last open one.
            let isOpen = { (world: ArcadeWorld) in ArcadeUnlock.isWorldOpen(world, unlocked: unlocked) }
            let focus = ArcadeWorld.campaign.firstIndex { world in
                isOpen(world) && progress.clearedCounts(in: world).main < min(world.levelCount, ArcadeWorld.mainLevelCount)
            } ?? (ArcadeWorld.campaign.lastIndex(where: isOpen) ?? 0)
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Your fish swims just above the world you're on, clear of its Deep End ring.
                        MapArtLayer(size: CGSize(width: width, height: size.height), points: centers,
                                    fishHome: CGPoint(x: centers[focus].x, y: centers[focus].y + Self.fishLift), look: progress.look)
                            .frame(width: width, height: size.height)
                        ForEach(worlds.indices, id: \.self) { index in
                            let world = worlds[index]
                            let open = isOpen(world)
                            let cleared = progress.clearedCounts(in: world)
                            let main = min(world.levelCount, ArcadeWorld.mainLevelCount)
                            let complete = open && cleared.main >= main
                            let detail = !open ? "Unlock to play"
                                : complete ? "Conquered!" : cleared.main == 0 ? "\(main) levels to conquer" : "\(main - cleared.main) more to conquer"
                            // A ring around the world fills in an arc per level beaten; once it's conquered, the ring
                            // turns gold for its Deep End.
                            let deepEnd = complete && world.deepEndCount > 0 ? (cleared: cleared.deepEnd, count: world.deepEndCount) : nil
                            let crown = WorldCrown.earned(conquered: complete,
                                                          deepEndCleared: deepEnd.map { $0.cleared >= $0.count } ?? false)
                            let deepEndLabel = deepEnd.map { ", Deep End \($0.cleared) of \($0.count) cleared" } ?? ""
                            Button { open ? onSelect(world) : onUnlock(world) } label: {
                                WorldMapStop(title: world.title, detail: detail, world: world,
                                             color: world.color, placeholder: false, locked: !open, deepEnd: deepEnd,
                                             progress: open && !complete ? (cleared: cleared.main, count: main) : nil,
                                             crown: crown)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(open ? "\(world.title), \(detail)\(deepEndLabel)" : "\(world.title), locked. \(detail)")
                            .position(x: centers[index].x, y: size.height - centers[index].y)
                        }
                    }.frame(width: width, height: size.height)
                }
                .scrollClipDisabled()
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                // Opened on the world you're on, where your fish waits.
                .defaultScrollAnchor(UnitPoint(x: Self.scrollAnchor(centering: centers[focus].x, width: width, screenWidth: size.width),
                                               y: 0.5))
                Text("Bigger Fish").font(.custom("AvenirNext-Heavy", size: 30))
                    .padding(.leading, 24).padding(.top, 15).allowsHitTesting(false)
                HStack(spacing: 14) {
                    if let onOpenWater { OpenWaterButton(best: progress.openWaterBest, action: onOpenWater) }
                    if let onPearlShop { PearlShopButton(pearls: progress.pearls, action: onPearlShop) }
                    if !unlocked { UnlockButton { onUnlock(nil) } }
                    SettingsButton(action: onSettings)
                }
                .frame(width: size.width - 24, alignment: .trailing)
                .padding(.top, 14)
                VStack { Spacer(); Text(width > size.width ? "Choose a world. Swipe to explore." : "Choose a world")
                    .font(.custom("AvenirNext-DemiBold", size: 13)).padding(.bottom, 12) }
                    .frame(width: size.width).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .background(OceanBackdrop(bloom: false))
    }

    /// How far above the world you're on your fish swims.
    static let fishLift: CGFloat = 72

    /// Where the world map's stops go on a screen `size` big, and how wide the map is: spread across the screen as
    /// they always were when that leaves them at least `GameTuning.worldMapTightestSpacing` apart, and otherwise
    /// `GameTuning.worldMapSpacing` apart, with the same margins at the ends, on a map wider than the screen that
    /// scrolls. Either way, in two rows at `GameTuning.worldMapRows`.
    static func stops(count: Int, in size: CGSize) -> (centers: [CGPoint], width: CGFloat) {
        // Math Reef's zig-zag, but on Bigger Fish's own rows (`GameTuning.worldMapRows`).
        func rows(_ centers: [CGPoint]) -> [CGPoint] {
            centers.enumerated().map { index, center in
                let row = index.isMultiple(of: 2) ? GameTuning.worldMapRows.upper : GameTuning.worldMapRows.lower
                return CGPoint(x: center.x, y: size.height * row)
            }
        }
        let spread = OceanMapLayout.worldCenters(count: count, size: size)
        guard spread.count > 1, spread[1].x - spread[0].x < GameTuning.worldMapTightestSpacing else { return (rows(spread), size.width) }
        let margins = spread[0].x + size.width - spread[spread.count - 1].x
        let width = margins + GameTuning.worldMapSpacing * CGFloat(count - 1)
        return (rows(OceanMapLayout.worldCenters(count: count, size: CGSize(width: width, height: size.height))), width)
    }

    /// How far across a map `width` wide to open it (`defaultScrollAnchor`'s x) so the point `x` is in the middle of a
    /// screen `screenWidth` wide, or as near as the map's ends allow.
    static func scrollAnchor(centering x: CGFloat, width: CGFloat, screenWidth: CGFloat) -> CGFloat {
        guard width > screenWidth else { return 0 }
        return min(max((x - screenWidth / 2) / (width - screenWidth), 0), 1)
    }
}

/// On the world map without the unlock: a small gold way to see what it opens.
private struct UnlockButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Unlock all", systemImage: "lock.open.fill")
                .font(.custom("AvenirNext-Heavy", size: 15))
                .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.24))
                .padding(.horizontal, 16).frame(height: 40)
                .background(DeepEndColors.gold, in: Capsule())
                .shadow(color: DeepEndColors.gold.opacity(0.4), radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock every world")
    }
}

/// On the world map in Xcode builds: the way into the Open Water, the endless run's prototype, with your best run (in
/// fish eaten) once you have one.
private struct OpenWaterButton: View {
    let best: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Label("Open Water", systemImage: "infinity")
                if best > 0 {
                    Text("Best \(best)").font(.custom("AvenirNext-DemiBold", size: 14)).monospacedDigit().opacity(0.75)
                }
            }
            .font(.custom("AvenirNext-Heavy", size: 15))
            .padding(.horizontal, 16).frame(height: 40)
            .background(Capsule().fill(.white.opacity(0.18)))
            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(best > 0 ? "Open Water, endless run, best \(best) fish" : "Open Water, endless run")
    }
}

/// On the world map in Xcode builds, beside the Open Water: the pearl shop, with how many pearls you have.
private struct PearlShopButton: View {
    let pearls: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                PearlIcon(size: 15)
                Text("\(pearls)").font(.custom("AvenirNext-Heavy", size: 15)).monospacedDigit()
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Capsule().fill(.white.opacity(0.18)))
            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pearl shop, \(pearls) pearls")
    }
}

/// On the world map: the gear that opens Settings.
private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.18)))
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}

struct ArcadeLevelMap: View {
    let world: ArcadeWorld
    @ObservedObject var progress: ArcadeProgress
    /// The unlock is bought (or not on sale): no level is past the free ones.
    let unlocked: Bool
    /// The level just played, when coming back from it.
    var returnedFrom: Int? = nil
    /// A level just cleared for the first time: your fish swims from it to the next one.
    var advancedFrom: Int? = nil
    let onBack: () -> Void
    let onPlay: (Int) -> Void

    /// Where your fish sits over a level: just above it, or higher over a crowned level so the crown shows.
    private func fishSpot(_ index: Int, _ centers: [CGPoint]) -> CGPoint {
        let lift: CGFloat = MapLevelStop.crown(for: index, in: world) == .none ? 58 : 82
        return CGPoint(x: centers[index].x, y: centers[index].y + lift)
    }

    var body: some View {
        ScreenScaled { size, insets in
            let width = max(size.width, OceanMapLayout.levelContentWidth(count: world.levelCount))
            let centers = OceanMapLayout.levelCenters(count: world.levelCount, height: size.height)
            let advanced = advancedFrom.flatMap { progress.isOpen(world, $0 + 1) && centers.indices.contains($0 + 1) ? $0 : nil }
            let focus = advanced.map { $0 + 1 } ?? progress.mapFocus(in: world, returningFrom: returnedFrom)
            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            if world.deepEndCount > 0 {
                                let dropX = OceanMapLayout.levelStartX + OceanMapLayout.levelSpacing * (CGFloat(ArcadeWorld.mainLevelCount) - 0.55)
                                // Drawn out past the safe area at the bottom and right, and past the end, so the deep
                                // water fills the screen even when the map bounces at its end. As an overlay it takes
                                // no room, so the map's layers keep their size and the fish stays on its stop.
                                Color.clear.frame(width: width - dropX, height: size.height)
                                    .overlay(alignment: .topLeading) {
                                        DeepEndZone(open: progress.isOpen(world, ArcadeWorld.mainLevelCount),
                                                    cleared: progress.clearedCounts(in: world).deepEnd, count: world.deepEndCount,
                                                    needsUnlock: ArcadeUnlock.needsUnlock(world, ArcadeWorld.mainLevelCount, unlocked: unlocked))
                                            .frame(width: width - dropX + insets.trailing + 400,
                                                   height: size.height + insets.top + insets.bottom)
                                            .offset(y: -insets.top)
                                    }
                                    .offset(x: dropX)
                            }
                            MapArtLayer(size: CGSize(width: width, height: size.height), points: centers,
                                        fishHome: centers.indices.contains(focus) ? fishSpot(focus, centers) : nil,
                                        fishFrom: advanced.map { fishSpot($0, centers) },
                                        pulsingStops: centers.indices.contains(focus) ? [centers[focus]] : [],
                                        look: progress.look)
                                .frame(width: width, height: size.height)
                            ForEach(0..<world.levelCount, id: \.self) { index in
                                // Past the free levels, a stop offers the unlock (tapping it shows what it opens).
                                let needsUnlock = ArcadeUnlock.needsUnlock(world, index, unlocked: unlocked)
                                let open = progress.isOpen(world, index) && !needsUnlock
                                let cleared = progress.isCleared(world, index)
                                Button { onPlay(index) } label: {
                                    MapLevelStop(number: index + 1, title: world.levelTitles[index], color: world.color,
                                                 open: open, cleared: cleared,
                                                 best: progress.save.bestTimes[world.levelID(index)],
                                                 deep: ArcadeWorld.isDeepEnd(index), needsUnlock: needsUnlock,
                                                 conquers: MapLevelStop.crown(for: index, in: world))
                                }
                                .buttonStyle(.plain).disabled(!open && !needsUnlock)
                                .accessibilityLabel("\(world.levelTitles[index]), \(needsUnlock ? "part of the unlock" : open ? (cleared ? "cleared, replay" : "play") : "locked")")
                                .position(x: centers[index].x, y: size.height - centers[index].y)
                            }
                            // Stable scroll targets are separate from the positioned buttons.
                            HStack(spacing: 0) {
                                Color.clear.frame(width: OceanMapLayout.levelStartX - OceanMapLayout.levelSpacing / 2)
                                ForEach(0..<world.levelCount, id: \.self) { index in
                                    Color.clear.frame(width: OceanMapLayout.levelSpacing, height: 1).id("level-\(index)")
                                }
                            }.allowsHitTesting(false)
                        }.frame(width: width, height: size.height)
                    }
                    .scrollClipDisabled()
                    .onAppear { proxy.scrollTo("level-\(focus)", anchor: .center) }
                }
                HStack(spacing: 14) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.25), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityLabel("Back to worlds")
                    Text(world.title).font(.custom("AvenirNext-Heavy", size: 26))
                    WorldProgressBar(progress: WorldProgress(world: world, level: 0) { progress.isCleared(world, $0) })
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.top, 10)
                VStack { Spacer(); Text(goal)
                    .font(.custom("AvenirNext-DemiBold", size: 12)).padding(.bottom, 12) }
                    .frame(width: size.width).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .background(OceanBackdrop(bloom: world.hasJellies, sunset: world == .sunsetCove))
    }

    /// Along the bottom: the world's goal until it's met, then its Deep End's.
    private var goal: String {
        let main = WorldProgress(world: world, level: 0) { progress.isCleared(world, $0) }
        guard main.isConquered, world.deepEndCount > 0 else { return "Clear all \(main.run.count) levels to conquer \(world.title). Swipe to explore." }
        let deep = WorldProgress(world: world, level: ArcadeWorld.mainLevelCount) { progress.isCleared(world, $0) }
        return deep.isConquered ? "\(world.title) and its Deep End conquered!" : "\(world.title) conquered! The Deep End waits past level \(ArcadeWorld.mainLevelCount)."
    }
}

private struct WorldMapStop: View {
    let title: String
    let detail: String
    let world: ArcadeWorld?
    let color: Color
    let placeholder: Bool
    var locked = false
    var deepEnd: (cleared: Int, count: Int)? = nil
    /// The world's ten levels, as a ring in its color, until it's conquered.
    var progress: (cleared: Int, count: Int)? = nil
    /// A crown on top: silver once its tenth level is beaten, gold once its Deep End is too.
    var crown: WorldCrown = .none

    var body: some View {
        ZStack {
            if let deepEnd {
                DeepEndRing(cleared: deepEnd.cleared, count: deepEnd.count).frame(width: 96, height: 96)
            } else if let progress {
                DeepEndRing(cleared: progress.cleared, count: progress.count, lineWidth: 3.5, color: color)
                    .frame(width: 96, height: 96)
            }
            Circle().fill(color.opacity(0.16))
                .overlay(Circle().stroke(color.opacity(placeholder ? 0.4 : 0.65), lineWidth: 2))
                .frame(width: 80, height: 80)
                .shadow(color: color.opacity(0.3), radius: 18)
            if let world {
                WorldIllustration(world: world).frame(width: 58, height: 58)
                    .saturation(locked ? 0 : 1).opacity(locked ? 0.45 : 1)
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 20, weight: .bold))
                        .padding(7).background(.black.opacity(0.55), in: Circle()).offset(x: 26, y: 26)
                }
            } else {
                Image(systemName: "lock.fill").font(.system(size: 24, weight: .bold))
            }
            if let color = crown.color {
                Image(systemName: "crown.fill").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(color)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(y: -50)
            }
            VStack(spacing: 4) {
                Text(title).font(.custom("AvenirNext-Heavy", size: 16))
                Text(detail).font(.custom("AvenirNext-DemiBold", size: 13)).multilineTextAlignment(.center)
                    .fixedSize()
            }.offset(y: 70)
        }
        .opacity(placeholder ? 0.65 : locked ? 0.85 : 1)
        .frame(width: 140, height: 180).contentShape(Rectangle())
    }
}

private struct MapLevelStop: View {
    let number: Int
    let title: String
    let color: Color
    let open: Bool
    let cleared: Bool
    let best: Double?
    /// A Deep End level: deep navy with a gold rim.
    var deep = false
    /// Past the free levels without the unlock: a gold padlock, and tapping it shows the unlock.
    var needsUnlock = false
    /// The level that earns a crown: the tenth (silver, for the world) or the Deep End's last (gold). The crown over it
    /// takes its color once the level is beaten.
    var conquers: WorldCrown = .none

    /// The crown a level earns: silver for the world's tenth, gold for its Deep End's last, none for the rest.
    static func crown(for index: Int, in world: ArcadeWorld) -> WorldCrown {
        if index == ArcadeWorld.mainLevelCount - 1 { return .silver }
        return index == world.levelCount - 1 && ArcadeWorld.isDeepEnd(index) ? .gold : .none
    }

    private static let gold = Color(red: 1, green: 0.8, blue: 0.32)

    var body: some View {
        ZStack {
            Circle().fill(deep ? Color(red: 0.05, green: 0.1, blue: 0.26).opacity(open ? 1 : 0.6) : open ? color : .white.opacity(0.09))
                .overlay(Circle().stroke(deep ? Self.gold.opacity(open ? 1 : 0.4) : .white.opacity(open ? 0.9 : 0.25),
                                         lineWidth: deep ? 3.5 : 2.5))
                .shadow(color: deep && open ? Self.gold.opacity(0.5) : .clear, radius: 10)
                .frame(width: 56, height: 56)
            Text("\(number)").font(.custom("AvenirNext-Heavy", size: 21))
                .foregroundStyle(deep ? Self.gold.opacity(open ? 1 : 0.45)
                                 : open ? Color(red: 0.04, green: 0.12, blue: 0.24) : .white.opacity(0.45))
            if needsUnlock {
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.24))
                    .frame(width: 24, height: 24).background(Self.gold, in: Circle())
                    .offset(x: 21, y: 21)
            }
            if let earned = conquers.color {
                // Still to earn, an outline; beaten, filled in its color.
                Image(systemName: cleared ? "crown.fill" : "crown").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(cleared ? earned : .white.opacity(open ? 0.9 : 0.5))
                    .shadow(color: cleared ? earned.opacity(0.6) : .clear, radius: 6)
                    .offset(y: -45)
            } else if cleared {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).offset(y: -43)
            }
            VStack(spacing: 4) {
                Text(title).font(.custom("AvenirNext-DemiBold", size: 12))
                if needsUnlock { Text("Unlock").font(.custom("AvenirNext-Heavy", size: 11)).foregroundStyle(Self.gold) }
                else if let best { Text("Best \(Int(best))s").font(.custom("AvenirNext-DemiBold", size: 11)) }
                else if !open { Text("Locked").font(.custom("AvenirNext-DemiBold", size: 11)) }
            }.opacity(open || needsUnlock ? 0.95 : 0.55).offset(y: 51)
        }
        .frame(width: 108, height: 128).contentShape(Rectangle())
    }
}

private struct MapArtLayer: View {
    private let scene: MapDecorationScene
    /// `fishFrom`: where your fish starts, swimming on to `fishHome`. `look`: what your fish wears.
    init(size: CGSize, points: [CGPoint], fishHome: CGPoint?, fishFrom: CGPoint? = nil, pulsingStops: [CGPoint] = [],
         look: PlayerLook = .plain) {
        scene = MapDecorationScene(size: size, points: points, fishHome: fishHome, fishFrom: fishFrom, pulsingStops: pulsingStops,
                                   look: look)
    }
    var body: some View {
        MapArtView(scene: scene).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The map art's SpriteKit view: SpriteView's, but drawn at the menus' scale (`ScreenScaled`) on an iPad, where a
/// SwiftUI scale effect would only stretch what it drew at a phone's size.
private struct MapArtView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> ScaledView {
        let view = ScaledView()
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 30
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ScaledView, context: Context) {
        view.menuScale = context.environment.menuScale
        if view.scene !== scene { view.presentScene(scene) }
    }

    final class ScaledView: SKView {
        var menuScale: CGFloat = 1 { didSet { if menuScale != oldValue { matchScreen() } } }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            matchScreen()
        }

        private func matchScreen() {
            guard let screen = window?.windowScene?.screen else { return }
            contentScaleFactor = screen.scale * menuScale
        }
    }
}

final class MapDecorationScene: SKScene {
    private let marker: FishNode
    private let home: CGPoint?
    /// A swim from a level just cleared to the next: where it starts, and when (the first frame).
    private let from: CGPoint?
    private var swimStart: TimeInterval?
    private static let swimDelay: TimeInterval = 0.35
    private static let swimSeconds: TimeInterval = 1.1
    init(size: CGSize, points: [CGPoint], fishHome: CGPoint?, fishFrom: CGPoint?, pulsingStops: [CGPoint], look: PlayerLook = .plain) {
        marker = look.fish()
        home = fishHome
        from = fishFrom
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(OceanMapArt.dottedPath(through: points))
        for center in pulsingStops {
            let halo = SKShapeNode(circleOfRadius: 34)
            halo.position = center
            halo.strokeColor = SKColor(white: 1, alpha: 0.8)
            halo.lineWidth = 3
            halo.fillColor = .clear
            halo.run(.repeatForever(.sequence([
                .group([.scale(to: 1.25, duration: 0.9), .fadeOut(withDuration: 0.9)]),
                .scale(to: 1, duration: 0), .fadeAlpha(to: 1, duration: 0),
            ])))
            addChild(halo)
        }
        // Your fish over the dotted path and a stop's pulsing ring, its tail and fin (at -2 and -1 of its own) under
        // them as they've always been: the scene ignores sibling order, so its body at the path's depth could go under.
        marker.zPosition = 0.5
        if let fishHome { marker.position = fishFrom ?? fishHome; addChild(marker) }
        else if pulsingStops.isEmpty { isPaused = true }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func update(_ currentTime: TimeInterval) {
        guard let home else { return }
        let time = CGFloat(currentTime)
        var spot = home
        var swimming = false
        if let from {
            let start = swimStart ?? currentTime
            swimStart = start
            let t = CGFloat(min(1, max(0, (currentTime - start - Self.swimDelay) / Self.swimSeconds)))
            if t < 1 {
                // Eased along, with a little hop over the path between the stops.
                let eased = t * t * (3 - 2 * t)
                spot = CGPoint(x: from.x + (home.x - from.x) * eased,
                               y: from.y + (home.y - from.y) * eased + sin(.pi * eased) * 22)
                swimming = t > 0
            }
        }
        marker.position = CGPoint(x: spot.x, y: spot.y + sin(time * 2) * 4)
        marker.apply(radius: 18, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1,
                     mouthOpen: 0, time: time, tailRate: swimming ? 22 : 9)
    }
}

struct OceanBackdrop: View {
    let bloom: Bool
    /// Sunset Cove's level map: its coral water fading to deep purple.
    var sunset = false
    private var colors: [Color] {
        if sunset { return [Color(red: 0.62, green: 0.25, blue: 0.42), Color(red: 0.14, green: 0.05, blue: 0.24)] }
        return bloom
            ? [Color(red: 0.19, green: 0.13, blue: 0.39), Color(red: 0.04, green: 0.07, blue: 0.20)]
            : [Color(red: 0.06, green: 0.38, blue: 0.49), Color(red: 0.02, green: 0.09, blue: 0.23)]
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { context, size in
                    for i in 0..<42 {
                        let x = CGFloat((i * 137 + 19) % 997) / 997 * size.width
                        let y = CGFloat((i * 89 + 31) % 499) / 499 * size.height
                        let r = CGFloat(2 + i % 4)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                     with: .color(.white.opacity(Double(2 + i % 4) * 0.04)))
                    }
                    var bed = Path()
                    bed.move(to: CGPoint(x: 0, y: size.height))
                    bed.addLine(to: CGPoint(x: 0, y: size.height - 20))
                    bed.addCurve(to: CGPoint(x: size.width, y: size.height - 24),
                                 control1: CGPoint(x: size.width * 0.3, y: size.height - 45),
                                 control2: CGPoint(x: size.width * 0.7, y: size.height + 15))
                    bed.addLine(to: CGPoint(x: size.width, y: size.height))
                    context.fill(bed, with: .color((sunset ? Color.pink : bloom ? Color.purple : Color.teal).opacity(0.2)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }.ignoresSafeArea()
    }
}

/// Drawn from the game's own fish and jellyfish art (IconographyTests renders it).
extension ArcadeWorld {
    /// The world's picture on the world map and unlock screen.
    var illustration: String {
        switch self {
        case .shallowReef: "WorldShallowReef"
        case .jellyBloom: "WorldJellyBloom"
        case .kelpForest: "WorldKelpForest"
        case .midnightZone: "WorldMidnightZone"
        case .sunsetCove: "WorldSunsetCove"
        case .riptideReef: "WorldRiptideReef"
        }
    }
}

struct WorldIllustration: View {
    let world: ArcadeWorld
    var body: some View {
        Group {
            if world == .riptideReef {
                // A stand-in while Riptide Reef is a prototype, until it has a picture of its own.
                Image(systemName: "water.waves").resizable().scaledToFit().padding(10).foregroundStyle(world.color)
            } else {
                Image(world.illustration).resizable().scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }
}
