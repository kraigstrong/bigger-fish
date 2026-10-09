import SwiftUI

// The Deep End: each world's optional extra-hard levels after its tenth, for players who want more.

private enum DeepEndColors {
    static let gold = Color(red: 1, green: 0.8, blue: 0.32)
    static let surface = Color(red: 0.13, green: 0.52, blue: 0.66)
    static let abyss = Color(red: 0.02, green: 0.05, blue: 0.14)
    static let night = Color(red: 0.03, green: 0.07, blue: 0.2)
}

/// The Deep End's emblem: a gold-ringed porthole into deep water, with a fish diving down and bubbles rising.
struct DeepEndBadge: View {
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvas in
                let rect = CGRect(origin: .zero, size: canvas).insetBy(dx: size * 0.05, dy: size * 0.05)
                let porthole = Path(ellipseIn: rect)
                context.fill(porthole, with: .linearGradient(Gradient(colors: [DeepEndColors.surface, DeepEndColors.abyss]),
                                                             startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                             endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                var inside = context
                inside.clip(to: porthole)
                // Light from the surface, fading as it goes down.
                for index in 0..<3 {
                    let x = rect.minX + rect.width * (0.25 + 0.25 * CGFloat(index))
                    var ray = Path()
                    ray.move(to: CGPoint(x: x - rect.width * 0.05, y: rect.minY))
                    ray.addLine(to: CGPoint(x: x + rect.width * 0.05, y: rect.minY))
                    ray.addLine(to: CGPoint(x: x + rect.width * 0.16, y: rect.maxY))
                    ray.addLine(to: CGPoint(x: x - rect.width * 0.02, y: rect.maxY))
                    inside.fill(ray, with: .linearGradient(Gradient(colors: [.white.opacity(0.14), .clear]),
                                                           startPoint: CGPoint(x: x, y: rect.minY), endPoint: CGPoint(x: x, y: rect.maxY)))
                }
                // Bubbles rising past the diving fish.
                for index in 0..<7 {
                    let seed = Double(index)
                    let rise = (time * (0.12 + 0.03 * seed.truncatingRemainder(dividingBy: 3)) + seed * 0.37)
                        .truncatingRemainder(dividingBy: 1)
                    let x = rect.minX + rect.width * (0.18 + 0.64 * CGFloat((seed * 0.618).truncatingRemainder(dividingBy: 1)))
                        + sin(time * 2 + seed) * size * 0.015
                    let y = rect.maxY - rect.height * CGFloat(rise)
                    let r = size * (0.018 + 0.01 * CGFloat(index % 3))
                    inside.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                  with: .color(.white.opacity(0.55)), lineWidth: max(1, size * 0.012))
                }
                // The fish, nose down, bobbing on its way into the deep.
                let bob = CGFloat(sin(time * 1.6)) * size * 0.025
                let fish = DeepEndBadge.divingFish(center: CGPoint(x: rect.midX, y: rect.midY + size * 0.05 + bob), length: size * 0.42)
                inside.fill(fish.body, with: .color(DeepEndColors.gold))
                inside.fill(fish.eye, with: .color(DeepEndColors.abyss))
                // Gold rim.
                context.stroke(porthole, with: .color(DeepEndColors.gold), lineWidth: size * 0.05)
                context.stroke(Path(ellipseIn: rect.insetBy(dx: size * 0.055, dy: size * 0.055)),
                               with: .color(.white.opacity(0.25)), lineWidth: max(1, size * 0.012))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// A simple fish pointing down and to the right: body, tail, and eye.
    private static func divingFish(center: CGPoint, length: CGFloat) -> (body: Path, eye: Path) {
        let angle = Angle.degrees(58)
        var body = Path(ellipseIn: CGRect(x: -length * 0.32, y: -length * 0.17, width: length * 0.64, height: length * 0.34))
        var tail = Path()
        tail.move(to: CGPoint(x: -length * 0.26, y: 0))
        tail.addLine(to: CGPoint(x: -length * 0.5, y: -length * 0.17))
        tail.addLine(to: CGPoint(x: -length * 0.46, y: 0))
        tail.addLine(to: CGPoint(x: -length * 0.5, y: length * 0.17))
        tail.closeSubpath()
        body.addPath(tail)
        let eye = Path(ellipseIn: CGRect(x: length * 0.14, y: -length * 0.08, width: length * 0.07, height: length * 0.07))
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle.radians)
        return (body.applying(transform), eye.applying(transform))
    }
}

/// The level map past a world's tenth level: a reef drop-off into darker water, with its name and how to get in.
struct DeepEndZone: View {
    let open: Bool
    let cleared: Int
    let count: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            DropOff()
                .fill(LinearGradient(colors: [DeepEndColors.night.opacity(0.88), DeepEndColors.abyss.opacity(0.96)],
                                     startPoint: .top, endPoint: .bottom))
            DropOff().stroke(DeepEndColors.surface.opacity(0.55), lineWidth: 3)
            HStack(spacing: 10) {
                DeepEndBadge(size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE DEEP END").font(.custom("AvenirNext-Heavy", size: 19)).tracking(2)
                        .foregroundStyle(DeepEndColors.gold)
                    Group {
                        if open {
                            Text("Need more challenge?\nGo into the deep.")
                            Text("\(cleared)/\(count) cleared").opacity(0.7)
                        } else {
                            Label("Beat level \(ArcadeWorld.mainLevelCount) to dive in.", systemImage: "lock.fill")
                        }
                    }
                    .font(.custom("AvenirNext-DemiBold", size: 12)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.leading, 44).padding(.top, 60)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(open ? "The Deep End, \(cleared) of \(count) cleared" : "The Deep End, locked until level \(ArcadeWorld.mainLevelCount) is beaten")
    }

    /// Water past a jagged reef edge on the left.
    private struct DropOff: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 18, y: rect.minY))
            let steps = 10
            for index in 1...steps {
                let y = rect.minY + rect.height * CGFloat(index) / CGFloat(steps)
                let x = rect.minX + (index.isMultiple(of: 2) ? 6 : 26) + CGFloat(index % 3) * 4
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }
}

/// Shown when you beat a world's tenth level: the next world (or news that more are coming) and the
/// world's Deep End, each with its picture and a way in.
struct WorldConqueredView: View {
    let world: ArcadeWorld
    let onNextWorld: (ArcadeWorld) -> Void
    let onDeepEnd: () -> Void
    let onLater: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
                .onTapGesture(perform: onLater)
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("\(world.title) conquered!").font(.custom("AvenirNext-Heavy", size: 28))
                    Text("You ate your way to the top.").font(.custom("AvenirNext-DemiBold", size: 14)).opacity(0.85)
                }
                HStack(alignment: .top, spacing: 18) {
                    if let next = world.nextWorld {
                        UnlockCard(title: "\(next.title) is open!", line: next.subtitle, button: "Swim there",
                                   color: next.color, action: { onNextWorld(next) }) {
                            WorldIllustration(world: next).frame(width: 86, height: 86)
                        }
                    } else {
                        UnlockCard(title: "More worlds are on the way", line: "Keep your fins ready.", button: nil,
                                   color: .white.opacity(0.6), action: {}) {
                            Image(systemName: "questionmark").font(.system(size: 44, weight: .heavy)).opacity(0.7)
                                .frame(width: 86, height: 86)
                        }
                    }
                    if world.deepEndCount > 0 {
                        UnlockCard(title: "The Deep End is open", line: "Need more challenge?\nGo into the deep.",
                                   button: "Dive in", color: DeepEndColors.gold, action: onDeepEnd) {
                            DeepEndBadge(size: 88)
                        }
                    }
                }
                Button("Maybe later", action: onLater)
                    .font(.custom("AvenirNext-DemiBold", size: 15)).buttonStyle(.plain).opacity(0.8)
                    .padding(.top, 2)
            }
            .foregroundStyle(.white)
            .scaleEffect(shown ? 1 : 0.85).opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { shown = true } }
    }

    private struct UnlockCard<Picture: View>: View {
        let title: String
        let line: String
        let button: String?
        let color: Color
        let action: () -> Void
        @ViewBuilder let picture: Picture

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 106, height: 106)
                        .shadow(color: color.opacity(0.6), radius: 22)
                    picture
                }
                Text(title).font(.custom("AvenirNext-Heavy", size: 17)).multilineTextAlignment(.center)
                Text(line).font(.custom("AvenirNext-DemiBold", size: 13)).multilineTextAlignment(.center).opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let button {
                    Button(action: action) {
                        Text(button).font(.custom("AvenirNext-Heavy", size: 16))
                            .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.24))
                            .padding(.horizontal, 22).padding(.vertical, 9)
                            .background(color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(width: 230, height: 250)
            .background(RoundedRectangle(cornerRadius: 22).fill(.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(color.opacity(0.55), lineWidth: 1.5))
        }
    }
}
