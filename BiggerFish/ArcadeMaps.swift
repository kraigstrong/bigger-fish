import SwiftUI

extension ArcadeWorld {
    var color: Color { self == .shallowReef ? Color(red: 0.18, green: 0.78, blue: 0.72) : Color(red: 0.75, green: 0.52, blue: 1) }
}

struct ArcadeWorldMap: View {
    @ObservedObject var progress: ArcadeProgress
    let onSelect: (ArcadeWorld) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bigger Fish").font(.custom("AvenirNext-Heavy", size: 31))
                Spacer()
                Text("CHOOSE YOUR WORLD").font(.custom("AvenirNext-DemiBold", size: 12)).tracking(2).opacity(0.75)
            }
            .padding(.horizontal, 24).padding(.top, 14)
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let diameter = min(140.0, height * 0.52)
                let centers = [CGPoint(x: width * 0.27, y: height * 0.47),
                               CGPoint(x: width * 0.73, y: height * 0.47)]
                Canvas { context, _ in
                    var trail = Path()
                    trail.move(to: CGPoint(x: centers[0].x, y: centers[0].y - 40))
                    trail.addCurve(to: CGPoint(x: centers[1].x, y: centers[1].y - 40),
                                   control1: CGPoint(x: width * 0.42, y: height * 0.85),
                                   control2: CGPoint(x: width * 0.58, y: height * 0.05))
                    context.stroke(trail, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 3, dash: [2, 10]))
                }
                ForEach(Array(ArcadeWorld.allCases.enumerated()), id: \.element.id) { index, world in
                    let cleared = world.levels.indices.filter { progress.isCleared(world, $0) }.count
                    Button { onSelect(world) } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Circle().fill(world.color.opacity(0.16))
                                    .overlay(Circle().stroke(world.color.opacity(0.65), lineWidth: 2))
                                WorldIllustration(world: world).padding(diameter * 0.14)
                            }
                            .frame(width: diameter, height: diameter)
                            .shadow(color: world.color.opacity(0.3), radius: 18)
                            Text(world.title).font(.custom("AvenirNext-Heavy", size: 23))
                            Text(world.subtitle).font(.custom("AvenirNext-DemiBold", size: 12)).opacity(0.85)
                            Text(cleared == 5 ? "✓ WORLD COMPLETE" : "\(cleared) / 5 LEVELS CLEARED")
                                .font(.custom("AvenirNext-Bold", size: 11)).tracking(1).foregroundStyle(world.color)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(world.title), \(cleared) of 5 levels cleared")
                    .position(centers[index])
                }
            }
            Text("There's always a bigger fish.").font(.custom("AvenirNext-DemiBold", size: 14)).opacity(0.65)
                .padding(.bottom, 13)
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
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Label("Worlds", systemImage: "chevron.left") }
                    .font(.custom("AvenirNext-DemiBold", size: 16)).buttonStyle(.plain)
                    .padding(.vertical, 10)
                Spacer()
                VStack(spacing: 2) {
                    Text(world.title).font(.custom("AvenirNext-Heavy", size: 27))
                    Text(world.subtitle).font(.custom("AvenirNext-DemiBold", size: 12)).opacity(0.75)
                }
                Spacer()
                Text("\(world.levels.indices.filter { progress.isCleared(world, $0) }.count)/5 cleared")
                    .font(.custom("AvenirNext-DemiBold", size: 13)).foregroundStyle(world.color)
            }
            .padding(.horizontal, 24).padding(.top, 10)
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let centers = (0..<5).map { i in
                    CGPoint(x: width * (0.10 + Double(i) * 0.20),
                            y: height * (i.isMultiple(of: 2) ? 0.44 : 0.62))
                }
                Canvas { context, _ in
                    var path = Path()
                    path.move(to: centers[0])
                    for i in 1..<5 {
                        path.addCurve(to: centers[i],
                                      control1: CGPoint(x: (centers[i-1].x + centers[i].x) / 2, y: centers[i-1].y),
                                      control2: CGPoint(x: (centers[i-1].x + centers[i].x) / 2, y: centers[i].y))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 3, dash: [2, 9]))
                }
                ForEach(0..<5, id: \.self) { index in
                    let open = progress.isOpen(world, index)
                    let cleared = progress.isCleared(world, index)
                    let next = index == progress.nextLevel(in: world)
                    Button { onPlay(index) } label: {
                        VStack(spacing: 9) {
                            ZStack {
                                if next && open {
                                    Circle().stroke(world.color.opacity(0.35), lineWidth: 7).frame(width: 75, height: 75)
                                }
                                Circle().fill(open ? world.color : Color.white.opacity(0.09))
                                    .overlay(Circle().stroke(.white.opacity(open ? 0.9 : 0.25), lineWidth: 2.5))
                                    .frame(width: 61, height: 61)
                                if !open {
                                    Image(systemName: "lock.fill").font(.system(size: 21)).foregroundStyle(.white.opacity(0.45))
                                } else {
                                    Text(cleared ? "✓" : "\(index + 1)").font(.custom("AvenirNext-Heavy", size: 27))
                                        .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.24))
                                }
                            }
                            .frame(height: 76)
                            Text(world.levelTitles[index]).font(.custom("AvenirNext-Bold", size: 13))
                                .multilineTextAlignment(.center).frame(width: max(100, width * 0.18), height: 35)
                                .opacity(open ? 1 : 0.45)
                            if let best = progress.save.bestTimes[world.levelID(index)] {
                                Text("Best \(Int(best))s").font(.custom("AvenirNext-DemiBold", size: 11)).foregroundStyle(world.color)
                            } else {
                                Text(open ? (next ? "PLAY" : "REPLAY") : "LOCKED")
                                    .font(.custom("AvenirNext-Bold", size: 10)).tracking(1).opacity(0.6)
                            }
                        }
                    }
                    .buttonStyle(.plain).disabled(!open)
                    .accessibilityLabel("Level \(index + 1), \(world.levelTitles[index]), \(open ? (cleared ? "cleared" : "play") : "locked")")
                    .position(centers[index])
                }
            }
            Text("Clear a level to open the next. Replay any cleared level.")
                .font(.custom("AvenirNext-DemiBold", size: 12)).opacity(0.6).padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        .background(OceanBackdrop(bloom: world == .jellyBloom))
    }
}

private struct OceanBackdrop: View {
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
            if world == .jellyBloom {
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
