import FishKit
import SpriteKit
import SwiftUI

extension ArcadeWorld {
    var color: Color { Color(uiColor: mapColor) }
    var mapColor: UIColor {
        switch self {
        case .shallowReef: UIColor(red: 0.18, green: 0.78, blue: 0.72, alpha: 1)
        case .jellyBloom: UIColor(red: 0.75, green: 0.52, blue: 1, alpha: 1)
        case .reefLab: UIColor(red: 1, green: 0.74, blue: 0.3, alpha: 1)
        case .jellyLab: UIColor(red: 1, green: 0.45, blue: 0.75, alpha: 1)
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
            let focus = ArcadeWorld.campaign.firstIndex { world in
                (0..<world.levelCount).contains { !progress.isCleared(world, $0) }
            } ?? 0
            ZStack(alignment: .topLeading) {
                MapArtLayer(size: size, points: centers,
                            fishHome: CGPoint(x: centers[focus].x + 66, y: centers[focus].y + 14))
                ForEach(0..<5, id: \.self) { index in
                    if worlds.indices.contains(index) {
                        let world = worlds[index]
                        let cleared = (0..<world.levelCount).filter { progress.isCleared(world, $0) }.count
                        Button { onSelect(world) } label: {
                            WorldMapStop(title: world.title,
                                         detail: cleared == world.levelCount ? "✓ World complete" : "\(cleared)/\(world.levelCount) cleared",
                                         world: world,
                                         color: world.color, placeholder: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(world.title), \(cleared) of \(world.levelCount) levels cleared")
                        .position(x: centers[index].x, y: size.height - centers[index].y)
                    } else {
                        let title = ["Kelp Forest", "The Deep", "Riptide Reef"][index - worlds.count]
                        WorldMapStop(title: title, detail: "Coming soon", world: nil,
                                     color: [.blue, .orange, .pink][index - worlds.count], placeholder: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(title), coming soon")
                            .position(x: centers[index].x, y: size.height - centers[index].y)
                    }
                }
                Text("Bigger Fish").font(.custom("AvenirNext-Heavy", size: 30))
                    .padding(.leading, 24).padding(.top, 15).allowsHitTesting(false)
                VStack { Spacer(); Text("Choose a world")
                    .font(.custom("AvenirNext-DemiBold", size: 13)).padding(.bottom, 12) }
                    .frame(width: size.width).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .background(OceanBackdrop(bloom: false))
    }
}

struct ArcadeLevelMap: View {
    let world: ArcadeWorld
    @ObservedObject var progress: ArcadeProgress
    let onBack: () -> Void
    let onPlay: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let width = max(size.width, OceanMapLayout.levelContentWidth(count: world.levelCount))
            let centers = OceanMapLayout.levelCenters(count: world.levelCount, height: size.height)
            let focus = progress.mapFocus(in: world)
            ZStack(alignment: .topLeading) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            MapArtLayer(size: CGSize(width: width, height: size.height), points: centers,
                                        fishHome: centers.indices.contains(focus) ? CGPoint(x: centers[focus].x, y: centers[focus].y + 58) : nil,
                                        pulsingStops: centers.indices.contains(focus) ? [centers[focus]] : [])
                            ForEach(0..<world.levelCount, id: \.self) { index in
                                let open = progress.isOpen(world, index)
                                let cleared = progress.isCleared(world, index)
                                Button { onPlay(index) } label: {
                                    MapLevelStop(number: index + 1, title: world.levelTitles[index], color: world.color,
                                                 open: open, cleared: cleared,
                                                 best: progress.save.bestTimes[world.levelID(index)])
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
                    Text("\((0..<world.levelCount).filter { progress.isCleared(world, $0) }.count)/\(world.levelCount) cleared")
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

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.16))
                .overlay(Circle().stroke(color.opacity(placeholder ? 0.4 : 0.65), lineWidth: 2))
                .frame(width: 80, height: 80)
                .shadow(color: color.opacity(0.3), radius: 18)
            if let world {
                WorldIllustration(world: world).frame(width: 58, height: 58)
            } else {
                Image(systemName: "lock.fill").font(.system(size: 24, weight: .bold))
            }
            VStack(spacing: 4) {
                Text(title).font(.custom("AvenirNext-Heavy", size: 16))
                Text(detail).font(.custom("AvenirNext-DemiBold", size: 13))
            }.offset(y: 70)
        }
        .opacity(placeholder ? 0.65 : 1)
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

    var body: some View {
        ZStack {
            Circle().fill(open ? color : .white.opacity(0.09))
                .overlay(Circle().stroke(.white.opacity(open ? 0.9 : 0.25), lineWidth: 2.5))
                .frame(width: 56, height: 56)
            Text("\(number)").font(.custom("AvenirNext-Heavy", size: 21))
                .foregroundStyle(open ? Color(red: 0.04, green: 0.12, blue: 0.24) : .white.opacity(0.45))
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

private struct WorldIllustration: View {
    let world: ArcadeWorld
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            if world.hasJellies {
                for (x, y, scale) in [(0.50, 0.43, 1.0), (0.20, 0.62, 0.50), (0.83, 0.62, 0.48)] {
                    let r = w * 0.28 * scale
                    let c = CGPoint(x: w * x, y: h * y)
                    for i in -2...2 {
                        var tentacle = Path()
                        let tx = c.x + CGFloat(i) * r * 0.33
                        tentacle.move(to: CGPoint(x: tx, y: c.y))
                        tentacle.addCurve(to: CGPoint(x: tx + r * 0.12, y: c.y + r * 1.35),
                                          control1: CGPoint(x: tx + r * 0.4, y: c.y + r * 0.5),
                                          control2: CGPoint(x: tx - r * 0.3, y: c.y + r))
                        context.stroke(tentacle, with: .color(Color.pink.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    var dome = Path()
                    dome.move(to: CGPoint(x: c.x - r, y: c.y))
                    dome.addCurve(to: CGPoint(x: c.x + r, y: c.y),
                                  control1: CGPoint(x: c.x - r, y: c.y - r),
                                  control2: CGPoint(x: c.x + r, y: c.y - r))
                    dome.closeSubpath()
                    context.fill(dome, with: .color(Color.cyan.opacity(0.55)))
                    context.stroke(dome, with: .color(.white.opacity(0.9)), lineWidth: 2)
                }
            } else {
                for i in 0..<5 {
                    var coral = Path()
                    let x = w * (0.12 + CGFloat(i) * 0.18)
                    let height = h * (i.isMultiple(of: 2) ? 0.45 : 0.30)
                    coral.move(to: CGPoint(x: x, y: h * 0.9))
                    coral.addLine(to: CGPoint(x: x, y: h * 0.9 - height))
                    coral.move(to: CGPoint(x: x, y: h * 0.9 - height * 0.4))
                    coral.addLine(to: CGPoint(x: x + w * 0.1, y: h * 0.9 - height * 0.8))
                    context.stroke(coral, with: .color(i.isMultiple(of: 2) ? .pink.opacity(0.8) : .orange.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                let body = CGRect(x: w * 0.3, y: h * 0.16, width: w * 0.55, height: h * 0.34)
                var tail = Path()
                tail.move(to: CGPoint(x: w * 0.35, y: h * 0.33))
                tail.addLine(to: CGPoint(x: w * 0.12, y: h * 0.15))
                tail.addLine(to: CGPoint(x: w * 0.12, y: h * 0.50))
                tail.closeSubpath()
                context.fill(tail, with: .color(.yellow))
                context.fill(Path(ellipseIn: body), with: .color(.orange))
                context.stroke(Path(ellipseIn: body), with: .color(.white), lineWidth: 2)
                let eye = CGRect(x: w * 0.66, y: h * 0.2, width: w * 0.11, height: w * 0.11)
                context.fill(Path(ellipseIn: eye), with: .color(.white))
                context.fill(Path(ellipseIn: eye.insetBy(dx: 3, dy: 3)), with: .color(.black))
            }
        }
    }
}
