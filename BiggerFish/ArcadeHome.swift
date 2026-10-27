import FishKit
import SpriteKit
import SwiftUI

/// The first screen: the game's two ways to play on the right, under your right thumb (Adventure, through the worlds,
/// and the Open Water, the endless run), each with where you are in it; your fish on the left in what it wears, with
/// the Shop under it. Kraig picked it from four mockups (2026-10-26): "It leaves room on that card to display info
/// without it feeling awkward, and it's easy to hit with your right hand."
struct ArcadeHome: View {
    @ObservedObject var progress: ArcadeProgress
    /// The unlock is bought (or not on sale): no Unlock button.
    let unlocked: Bool
    /// The day's free Open Water runs left, without the unlock (`OpenWaterRuns`); nil with it.
    var openWaterRunsLeft: Int? = nil
    /// Into the worlds, at the one you're on.
    let onAdventure: () -> Void
    let onOpenWater: () -> Void
    let onShop: () -> Void
    let onUnlock: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ScreenScaled { size, _ in
            // A small phone (an iPhone SE) or the iPhone Duo's outer screen: everything a size smaller, so the modes
            // keep their names on one line.
            let compact = size.width < Self.compactWidth
            ZStack(alignment: .top) {
                HStack(spacing: compact ? 18 : 28) {
                    VStack(spacing: 4) {
                        Text("Bigger Fish").font(.custom("AvenirNext-Heavy", size: compact ? 38 : 46))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                            .accessibilityAddTraits(.isHeader)
                        // Your fish is a way into the Shop too: it's what you'd shop for.
                        Button(action: onShop) {
                            HomeFish(look: progress.look, radius: compact ? 42 : 54)
                                .frame(width: compact ? 220 : 280, height: compact ? 150 : 190)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityHidden(true)
                        ShopButton(pearls: progress.pearls, action: onShop)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: compact ? 12 : 16) {
                        adventure(compact: compact)
                        openWater(compact: compact)
                    }
                    .frame(width: compact ? 320 : 392)
                    .padding(.top, 36)
                }
                .padding(.horizontal, 12)
                .frame(width: size.width, height: size.height)
                HStack(spacing: 12) {
                    Spacer()
                    if !unlocked { UnlockAllButton(action: onUnlock) }
                    SettingsButton(action: onSettings)
                }
                .padding(.horizontal, 6).padding(.top, 10)
            }
            .frame(width: size.width, height: size.height)
        }
        .foregroundStyle(.white)
        .background(OceanBackdrop(bloom: false))
    }

    /// Narrower than this (an iPhone SE's 667, the Duo's outer 594), the compact layout.
    static let compactWidth: CGFloat = 700

    /// A crown for each world, earned or not, and until your first win, how a level is won.
    private func adventure(compact: Bool) -> some View {
        let crowns = ArcadeWorld.campaign.map { progress.crown(in: $0, unlocked: unlocked) }
        let conquered = crowns.filter { $0 != .none }.count
        let deepEnds = crowns.filter { $0 == .gold }.count
        let firstTime = Self.isFirstTime(progress)
        return ModeButton(title: "Adventure", icon: "ModeAdventure", colors: Self.adventureColors, compact: compact,
                          badge: firstTime ? "Start here" : nil, action: onAdventure) {
            HStack(spacing: 5) {
                ForEach(crowns.indices, id: \.self) { index in
                    Image(systemName: crowns[index] == .none ? "crown" : "crown.fill")
                        .font(.system(size: compact ? 13 : 15, weight: .bold))
                        .foregroundStyle(crowns[index].color ?? .white.opacity(0.55))
                }
            }
            if firstTime { Self.detail(Self.winRule, compact: compact) }
        }
        .accessibilityLabel(["Adventure", "\(conquered) of \(crowns.count) worlds conquered",
                             deepEnds > 0 ? "\(deepEnds) Deep \(deepEnds == 1 ? "End" : "Ends") conquered" : nil,
                             firstTime ? Self.winRule : nil].compactMap { $0 }.joined(separator: ". "))
    }

    /// Your best run (or, before one, the question the mode asks), and without the unlock, today's runs left.
    private func openWater(compact: Bool) -> some View {
        let lines = Self.openWaterLines(best: progress.openWaterBest, runsLeft: openWaterRunsLeft)
        return ModeButton(title: "Open Water", symbol: "infinity", icon: "ModeOpenWater", colors: Self.openWaterColors,
                          compact: compact, action: onOpenWater) {
            ForEach(lines, id: \.self) { Self.detail($0, compact: compact) }
        }
        .accessibilityLabel((["Open Water, endless run"] + lines).joined(separator: ". "))
    }

    private static func detail(_ text: String, compact: Bool) -> some View {
        Text(text).font(.custom("AvenirNext-DemiBold", size: compact ? 12 : 13)).opacity(0.85).lineLimit(1).fixedSize()
    }

    /// How a level is won, said on Adventure until Shallow Reef's first level is beaten.
    static let winRule = "Eat every fish to win"

    /// No level beaten yet: Adventure says where to start and how a level is won.
    static func isFirstTime(_ progress: ArcadeProgress) -> Bool {
        !progress.isCleared(.shallowReef, 0)
    }

    /// Open Water's lines: your best run in fish eaten (before one, what the mode asks), then without the unlock, the
    /// day's free runs left.
    static func openWaterLines(best: Int, runsLeft: Int?) -> [String] {
        let runs = runsLeft.map { left in
            switch left {
            case 0: "More runs tomorrow"
            case 1: "1 run left today"
            default: "\(left) runs left today"
            }
        }
        return [best > 0 ? "Best \(best) fish" : "How far can you get?", runs].compactMap { $0 }
    }

    private static let adventureColors = [Color(red: 0.12, green: 0.55, blue: 0.56), Color(red: 0.05, green: 0.27, blue: 0.36)]
    private static let openWaterColors = [Color(red: 0.10, green: 0.30, blue: 0.62), Color(red: 0.03, green: 0.09, blue: 0.30)]
}

/// A way to play: its picture in a ring, its name, where you are in it, and a chevron to say it opens.
private struct ModeButton<Detail: View>: View {
    let title: String
    var symbol: String? = nil
    /// The picture (`IconographyTests` draws it from the game's art).
    let icon: String
    let colors: [Color]
    let compact: Bool
    /// A word on the button's top edge ("Start here").
    var badge: String? = nil
    let action: () -> Void
    @ViewBuilder let detail: Detail

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 10 : 16) {
                Image(icon).resizable().scaledToFit()
                    .frame(width: compact ? 68 : 80, height: compact ? 68 : 80)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
                VStack(alignment: .leading, spacing: compact ? 4 : 5) {
                    Group {
                        if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
                    }
                    .font(.custom("AvenirNext-Heavy", size: compact ? 22 : 25)).lineLimit(1).fixedSize()
                    detail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: compact ? 15 : 18, weight: .heavy)).opacity(0.7)
            }
            .padding(.horizontal, 14).frame(height: compact ? 96 : 108)
            .background(RoundedRectangle(cornerRadius: 28).fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.55), lineWidth: 2))
            .shadow(color: colors[0].opacity(0.5), radius: 14)
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge).font(.custom("AvenirNext-Heavy", size: 12))
                        .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.24))
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .offset(x: 24, y: -11)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
    }
}

/// Under your fish: the pearl shop, with how many pearls you have (as the Open Water's run card says it).
private struct ShopButton: View {
    let pearls: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("Shop").font(.custom("AvenirNext-Heavy", size: 16))
                HStack(spacing: 5) {
                    PearlIcon(size: 15)
                    Text("\(pearls)").font(.custom("AvenirNext-Heavy", size: 15)).monospacedDigit()
                }.opacity(0.9)
            }
            .padding(.horizontal, 20).frame(height: 44)
            .background(Capsule().fill(.white.opacity(0.18)))
            .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shop, \(pearls) pearls")
    }
}

/// Without the unlock, on the home screen and the world map: a quiet gold way to see what it opens.
struct UnlockAllButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Unlock all", systemImage: "lock.open.fill")
                .font(.custom("AvenirNext-Heavy", size: 14))
                .foregroundStyle(DeepEndColors.gold)
                .padding(.horizontal, 14).frame(height: 36)
                .overlay(Capsule().stroke(DeepEndColors.gold.opacity(0.8), lineWidth: 1.5))
                .frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock every world")
    }
}

/// On the home screen: the gear that opens Settings.
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

/// Your fish in what it wears, swimming in place: what's bought or put on in the Shop shows as soon as it's closed.
private struct HomeFish: View {
    let look: PlayerLook
    let radius: CGFloat
    @State private var scene = HomeFishScene()

    var body: some View {
        MapArtView(scene: scene)
            .allowsHitTesting(false).accessibilityHidden(true)
            .onChange(of: look, initial: true) { _, look in scene.wear(look) }
            .onChange(of: radius, initial: true) { _, radius in scene.radius = radius }
    }
}

private final class HomeFishScene: SKScene {
    var radius: CGFloat = 54
    private var fish: FishNode?

    override init(size: CGSize = CGSize(width: 100, height: 100)) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func wear(_ look: PlayerLook) {
        fish?.removeFromParent()
        let node = look.fish()
        addChild(node)
        fish = node
    }

    override func update(_ currentTime: TimeInterval) {
        guard let fish else { return }
        let time = CGFloat(currentTime)
        // A little low in its frame, so a tall hat stays inside it.
        fish.position = CGPoint(x: size.width / 2, y: size.height * 0.42 + sin(time * 2) * 5)
        fish.apply(radius: radius, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1, mouthOpen: 0,
                   time: time, tailRate: 9)
    }
}
