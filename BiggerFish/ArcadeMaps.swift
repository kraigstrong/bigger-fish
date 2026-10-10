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
        case .riptideReef: UIColor(red: 0.95, green: 0.42, blue: 0.62, alpha: 1)
        }
    }
}

struct ArcadeWorldMap: View {
    @ObservedObject var progress: ArcadeProgress
    let onSelect: (ArcadeWorld) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centers = OceanMapLayout.worldCenters(count: 5, size: size)
            let worlds = ArcadeWorld.mapWorlds
            let comingSoon = [("Kelp Forest", Color.blue), ("Midnight Zone", .orange), ("Riptide Reef", .pink)]
                .filter { soon in !worlds.contains { $0.title == soon.0 } }
            // The first open world with main levels left, else the last open one.
            let focus = ArcadeWorld.campaign.firstIndex { world in
                progress.isWorldOpen(world) && progress.clearedCounts(in: world).main < min(world.levelCount, ArcadeWorld.mainLevelCount)
            } ?? (ArcadeWorld.campaign.lastIndex { progress.isWorldOpen($0) } ?? 0)
            ZStack(alignment: .topLeading) {
                // Your fish swims just above the world you're on, clear of its Deep End ring.
                MapArtLayer(size: size, points: centers,
                            fishHome: CGPoint(x: centers[focus].x, y: centers[focus].y + 72))
                ForEach(0..<5, id: \.self) { index in
                    if worlds.indices.contains(index) {
                        let world = worlds[index]
                        let open = progress.isWorldOpen(world)
                        let cleared = progress.clearedCounts(in: world)
                        let main = min(world.levelCount, ArcadeWorld.mainLevelCount)
                        let complete = open && cleared.main >= main
                        let detail = !open ? "Beat \(world.previousWorld?.title ?? "") to unlock"
                            : !complete ? "\(cleared.main)/\(main) cleared" : "✓ World complete"
                        // A finished world's Deep End shows as a gold ring around it, one arc per level beaten.
                        let deepEnd = complete && world.deepEndCount > 0 ? (cleared: cleared.deepEnd, count: world.deepEndCount) : nil
                        let deepEndLabel = deepEnd.map { ", Deep End \($0.cleared) of \($0.count) cleared" } ?? ""
                        Button { onSelect(world) } label: {
                            WorldMapStop(title: world.title, detail: detail, world: world,
                                         color: world.color, placeholder: false, locked: !open, deepEnd: deepEnd)
                        }
                        .buttonStyle(.plain).disabled(!open)
                        .accessibilityLabel(open ? "\(world.title), \(detail)\(deepEndLabel)" : "\(world.title), locked. \(detail)")
                        .position(x: centers[index].x, y: size.height - centers[index].y)
                    } else {
                        let (title, color) = comingSoon[index - worlds.count]
                        WorldMapStop(title: title, detail: "Coming soon", world: nil, color: color, placeholder: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(title), coming soon")
                            .position(x: centers[index].x, y: size.height - centers[index].y)
                    }
                }
                Text("Bigger Fish").font(.custom("AvenirNext-Heavy", size: 30))
                    .padding(.leading, 24).padding(.top, 15).allowsHitTesting(false)
                SoundToggles()
                    .frame(width: size.width - 24, alignment: .trailing)
                    .padding(.top, 14)
                VStack { Spacer(); Text("Choose a world")
                    .font(.custom("AvenirNext-DemiBold", size: 13)).padding(.bottom, 12) }
                    .frame(width: size.width).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .background(OceanBackdrop(bloom: false))
    }
}

/// The sound effects and music switches, as two small round buttons.
struct SoundToggles: View {
    @ObservedObject var settings = ArcadeSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            toggle($settings.soundEffectsOn, symbol: "speaker.wave.2.fill", label: "Sound effects")
            toggle($settings.musicOn, symbol: "music.note", label: "Music")
        }
    }

    private func toggle(_ isOn: Binding<Bool>, symbol: String, label: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(isOn.wrappedValue ? 0.18 : 0.05)))
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                .overlay {
                    // Off: struck through and dimmed.
                    if !isOn.wrappedValue {
                        Capsule().frame(width: 2.5, height: 30).rotationEffect(.degrees(-45))
                    }
                }
                .opacity(isOn.wrappedValue ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }
}

struct ArcadeLevelMap: View {
    let world: ArcadeWorld
    @ObservedObject var progress: ArcadeProgress
    /// The level just played, when coming back from it.
    var returnedFrom: Int? = nil
    let onBack: () -> Void
    let onPlay: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let width = max(size.width, OceanMapLayout.levelContentWidth(count: world.levelCount))
            let centers = OceanMapLayout.levelCenters(count: world.levelCount, height: size.height)
            let focus = progress.mapFocus(in: world, returningFrom: returnedFrom)
            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            if world.deepEndCount > 0 {
                                let dropX = OceanMapLayout.levelStartX + OceanMapLayout.levelSpacing * (CGFloat(ArcadeWorld.mainLevelCount) - 0.55)
                                // Drawn out past the safe area at the bottom and right, and past the end, so the deep
                                // water fills the screen even when the map bounces at its end. As an overlay it takes
                                // no room, so the map's layers keep their size and the fish stays on its stop.
                                let insets = geometry.safeAreaInsets
                                Color.clear.frame(width: width - dropX, height: size.height)
                                    .overlay(alignment: .topLeading) {
                                        DeepEndZone(open: progress.isOpen(world, ArcadeWorld.mainLevelCount),
                                                    cleared: progress.clearedCounts(in: world).deepEnd, count: world.deepEndCount)
                                            .frame(width: width - dropX + insets.trailing + 400,
                                                   height: size.height + insets.top + insets.bottom)
                                            .offset(y: -insets.top)
                                    }
                                    .offset(x: dropX)
                            }
                            MapArtLayer(size: CGSize(width: width, height: size.height), points: centers,
                                        fishHome: centers.indices.contains(focus) ? CGPoint(x: centers[focus].x, y: centers[focus].y + 58) : nil,
                                        pulsingStops: centers.indices.contains(focus) ? [centers[focus]] : [])
                                .frame(width: width, height: size.height)
                            ForEach(0..<world.levelCount, id: \.self) { index in
                                let open = progress.isOpen(world, index)
                                let cleared = progress.isCleared(world, index)
                                Button { onPlay(index) } label: {
                                    MapLevelStop(number: index + 1, title: world.levelTitles[index], color: world.color,
                                                 open: open, cleared: cleared,
                                                 best: progress.save.bestTimes[world.levelID(index)],
                                                 deep: ArcadeWorld.isDeepEnd(index))
                                }
                                .buttonStyle(.plain).disabled(!open)
                                .accessibilityLabel("\(world.levelTitles[index]), \(open ? (cleared ? "cleared, replay" : "play") : "locked")")
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
                    Text("\(progress.clearedCounts(in: world).main)/\(min(world.levelCount, ArcadeWorld.mainLevelCount)) cleared")
                        .font(.custom("AvenirNext-DemiBold", size: 14))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.top, 10)
                VStack { Spacer(); Text("Clear a level to open the next. Swipe to explore.")
                    .font(.custom("AvenirNext-DemiBold", size: 12)).padding(.bottom, 12) }
                    .frame(width: size.width).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .background(OceanBackdrop(bloom: world.hasJellies))
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

    var body: some View {
        ZStack {
            if let deepEnd {
                DeepEndRing(cleared: deepEnd.cleared, count: deepEnd.count).frame(width: 96, height: 96)
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
            if cleared {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).offset(y: -43)
            }
            VStack(spacing: 4) {
                Text(title).font(.custom("AvenirNext-DemiBold", size: 12))
                if let best { Text("Best \(Int(best))s").font(.custom("AvenirNext-DemiBold", size: 11)) }
                else if !open { Text("Locked").font(.custom("AvenirNext-DemiBold", size: 11)) }
            }.opacity(open ? 0.95 : 0.55).offset(y: 51)
        }
        .frame(width: 108, height: 128).contentShape(Rectangle())
    }
}

private struct MapArtLayer: View {
    private let scene: MapDecorationScene
    init(size: CGSize, points: [CGPoint], fishHome: CGPoint?, pulsingStops: [CGPoint] = []) {
        scene = MapDecorationScene(size: size, points: points, fishHome: fishHome, pulsingStops: pulsingStops)
    }
    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 30, options: [.allowsTransparency, .ignoresSiblingOrder])
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private final class MapDecorationScene: SKScene {
    private let marker = FishNode(style: .player, isPlayer: true, tailPhase: 0)
    private let home: CGPoint?
    init(size: CGSize, points: [CGPoint], fishHome: CGPoint?, pulsingStops: [CGPoint]) {
        home = fishHome
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
        if let fishHome { marker.position = fishHome; addChild(marker) }
        else if pulsingStops.isEmpty { isPaused = true }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func update(_ currentTime: TimeInterval) {
        guard let home else { return }
        let time = CGFloat(currentTime)
        marker.position = CGPoint(x: home.x, y: home.y + sin(time * 2) * 4)
        marker.apply(radius: 18, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1,
                     mouthOpen: 0, time: time, tailRate: 9)
    }
}

struct OceanBackdrop: View {
    let bloom: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: bloom
                               ? [Color(red: 0.19, green: 0.13, blue: 0.39), Color(red: 0.04, green: 0.07, blue: 0.20)]
                               : [Color(red: 0.06, green: 0.38, blue: 0.49), Color(red: 0.02, green: 0.09, blue: 0.23)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
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
                    context.fill(bed, with: .color((bloom ? Color.purple : Color.teal).opacity(0.2)))
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
