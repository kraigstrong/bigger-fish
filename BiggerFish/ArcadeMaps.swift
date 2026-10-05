import FishKit
import SpriteKit
import SwiftUI

extension ArcadeWorld {
    var color: Color { Color(uiColor: mapColor) }
    var mapColor: UIColor {
        self == .shallowReef ? UIColor(red: 0.18, green: 0.78, blue: 0.72, alpha: 1)
                            : UIColor(red: 0.75, green: 0.52, blue: 1, alpha: 1)
    }
}

struct ArcadeWorldMap: View {
    @ObservedObject var progress: ArcadeProgress
    let onSelect: (ArcadeWorld) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let width = max(size.width, CGFloat(ArcadeWorld.allCases.count) * 160 + 102)
            let centers = OceanMapLayout.worldCenters(count: ArcadeWorld.allCases.count,
                                                       size: CGSize(width: width, height: size.height))
            let focus = ArcadeWorld.allCases.firstIndex { world in
                world.levels.indices.contains { !progress.isCleared(world, $0) }
            } ?? 0
            ZStack(alignment: .topLeading) {
                MapArtLayer(size: size, points: [], fishHome: nil, bed: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        MapArtLayer(size: CGSize(width: width, height: size.height), points: centers,
                                    fishHome: CGPoint(x: centers[focus].x + 66, y: centers[focus].y + 14), bed: false)
                        ForEach(Array(ArcadeWorld.allCases.enumerated()), id: \.element.id) { index, world in
                            let cleared = world.levels.indices.filter { progress.isCleared(world, $0) }.count
                            Button { onSelect(world) } label: {
                                ZStack {
                                    Circle().fill(world.color).overlay(Circle().stroke(.white, lineWidth: 4))
                                        .frame(width: 80, height: 80)
                                    Image(systemName: world == .shallowReef ? "fish.fill" : "water.waves")
                                        .font(.system(size: 32, weight: .bold))
                                    VStack(spacing: 4) {
                                        Text(world.title).font(.custom("AvenirNext-Heavy", size: 16))
                                        Text(cleared == world.levels.count ? "✓ World complete" : "\(cleared)/\(world.levels.count) cleared")
                                            .font(.custom("AvenirNext-DemiBold", size: 13))
                                    }.offset(y: 70)
                                }
                                .frame(width: 160, height: 180)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(world.title), \(cleared) of \(world.levels.count) levels cleared")
                            .position(x: centers[index].x, y: size.height - centers[index].y)
                        }
                    }.frame(width: width, height: size.height)
                }
                Text("Bigger Fish").font(.custom("AvenirNext-Heavy", size: 30))
                    .padding(.leading, 24).padding(.top, 15).allowsHitTesting(false)
                VStack { Spacer(); Text("Choose a world")
                    .font(.custom("AvenirNext-DemiBold", size: 13)).padding(.bottom, 12) }
                    .frame(width: size.width).allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white)
        .background(MapWater())
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
            let width = max(size.width, OceanMapLayout.levelContentWidth(count: world.levels.count))
            let centers = OceanMapLayout.levelCenters(count: world.levels.count, height: size.height)
            let focus = progress.mapFocus(in: world)
            ZStack(alignment: .topLeading) {
                MapArtLayer(size: size, points: [], fishHome: nil, bed: true)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            MapArtLayer(size: CGSize(width: width, height: size.height), points: centers,
                                        fishHome: centers.indices.contains(focus) ? CGPoint(x: centers[focus].x, y: centers[focus].y + 58) : nil,
                                        bed: false)
                            ForEach(world.levels.indices, id: \.self) { index in
                                let open = progress.isOpen(world, index)
                                let cleared = progress.isCleared(world, index)
                                Button { onPlay(index) } label: {
                                    MapLevelStop(number: index + 1, color: world.color, open: open,
                                                 cleared: cleared, current: index == focus,
                                                 best: progress.save.bestTimes[world.levelID(index)])
                                }
                                .buttonStyle(.plain).disabled(!open)
                                .accessibilityLabel("Level \(index + 1), \(open ? (cleared ? "cleared, replay" : "play") : "locked")")
                                .position(x: centers[index].x, y: size.height - centers[index].y)
                            }
                            // Stable scroll targets are separate from the positioned buttons.
                            HStack(spacing: 0) {
                                Color.clear.frame(width: OceanMapLayout.levelStartX - OceanMapLayout.levelSpacing / 2)
                                ForEach(world.levels.indices, id: \.self) { index in
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
                    Text("\(world.levels.indices.filter { progress.isCleared(world, $0) }.count)/\(world.levels.count) cleared")
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
        .background(MapWater())
    }
}

private struct MapLevelStop: View {
    let number: Int
    let color: Color
    let open: Bool
    let cleared: Bool
    let current: Bool
    let best: Double?
    @State private var halo = false

    var body: some View {
        ZStack {
            if current && open && !cleared {
                Circle().stroke(.white.opacity(halo ? 0 : 0.8), lineWidth: 3)
                    .frame(width: 68, height: 68).scaleEffect(halo ? 1.25 : 1)
                    .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { halo = true } }
            }
            Circle().fill(!open ? .white.opacity(0.15) : (cleared ? color : .white))
                .overlay(Circle().stroke(open ? (cleared ? .white : color) : .white.opacity(0.3), lineWidth: 4))
                .frame(width: 56, height: 56)
            Text("\(number)").font(.custom("AvenirNext-Heavy", size: 21))
                .foregroundStyle(!open ? .white.opacity(0.5) : (cleared ? .white : color))
            if cleared {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).offset(y: -43)
            }
            VStack(spacing: 4) {
                Text("Level \(number)").font(.custom("AvenirNext-DemiBold", size: 12))
                if let best { Text("Best \(Int(best))s").font(.custom("AvenirNext-DemiBold", size: 11)) }
                else if !open { Text("Locked").font(.custom("AvenirNext-DemiBold", size: 11)) }
            }.opacity(open ? 0.95 : 0.55).offset(y: 51)
        }
        .frame(width: 108, height: 128).contentShape(Rectangle())
    }
}

private struct MapWater: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.20, green: 0.62, blue: 0.80),
                                Color(red: 0.08, green: 0.35, blue: 0.60),
                                Color(red: 0.03, green: 0.12, blue: 0.30)],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

private struct MapArtLayer: View {
    private let scene: MapDecorationScene
    init(size: CGSize, points: [CGPoint], fishHome: CGPoint?, bed: Bool) {
        scene = MapDecorationScene(size: size, points: points, fishHome: fishHome, bed: bed)
    }
    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 30, options: [.allowsTransparency, .ignoresSiblingOrder])
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private final class MapDecorationScene: SKScene {
    private let marker = FishNode(style: .player, isPlayer: true, tailPhase: 0)
    private let home: CGPoint?
    init(size: CGSize, points: [CGPoint], fishHome: CGPoint?, bed: Bool) {
        home = fishHome
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        if bed { addChild(OceanMapArt.seabed(size: size)) }
        addChild(OceanMapArt.dottedPath(through: points))
        if let fishHome { marker.position = fishHome; addChild(marker) }
        else { isPaused = true }
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
