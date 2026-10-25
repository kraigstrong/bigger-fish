import FishKit
import SpriteKit
import SwiftUI

/// The pearl shop (Xcode builds only, for now): the Open Water's pearls spent on looks for your fish, from the world
/// map's pearl button or a run's result card. Tap something you own to wear it, or something you don't to try it on
/// your fish first and buy it there. Buying puts it on.
struct PearlShopView: View {
    @ObservedObject var progress: ArcadeProgress
    let onClose: () -> Void
    @State private var kind: PearlItem.Kind = .color
    /// Something not yet owned, tried on in the preview.
    @State private var trying: PearlItem?
    @State private var shown = false
    @State private var preview = PearlShopPreviewScene()
    #if DEBUG
    /// Xcode builds: the season's limited editions on sale, whatever the date (`PearlSeason.pretendItsChristmas`).
    @State private var christmas = PearlSeason.pretendItsChristmas
    #endif

    private var shownLook: PlayerLook { trying.map(progress.look.wearing) ?? progress.look }

    var body: some View {
        ZStack {
            LinearGradient(colors: [DeepEndColors.night, DeepEndColors.abyss], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScreenScaled { size, _ in
                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 20) {
                        fitting.frame(width: min(300, size.width * 0.36))
                        catalog
                    }
                    .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
                    closeButton
                }
            }
        }
        .foregroundStyle(.white)
        .opacity(shown ? 1 : 0)
        .onAppear {
            preview.look = shownLook
            withAnimation(.easeOut(duration: 0.2)) { shown = true }
        }
        .onChange(of: shownLook) { _, look in preview.look = look }
    }

    /// The shop's name, your pearls, your fish in what it's wearing (and what it's trying on), and the way to buy it.
    private var fitting: some View {
        VStack(spacing: 10) {
            Text("Pearl Shop").font(.custom("AvenirNext-Heavy", size: 26))
            HStack(spacing: 8) {
                PearlIcon(size: 18)
                Text("\(progress.pearls)").font(.custom("AvenirNext-Heavy", size: 20)).monospacedDigit()
            }
            .padding(.horizontal, 16).frame(height: 36)
            .background(Capsule().fill(.white.opacity(0.12)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(progress.pearls) pearls")
            SpriteView(scene: preview, options: [.allowsTransparency])
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 18).fill(
                    LinearGradient(colors: [Color(red: 0.12, green: 0.55, blue: 0.66), Color(red: 0.04, green: 0.24, blue: 0.4)],
                                   startPoint: .top, endPoint: .bottom)))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            action
            #if DEBUG
            Button("+\(GameTuning.pearlShopTestGift) pearls (Xcode builds)") { progress.earnPearls(GameTuning.pearlShopTestGift) }
                .font(.custom("AvenirNext-DemiBold", size: 12)).opacity(0.6)
                .buttonStyle(.plain)
            Button(christmas ? "It's Christmas (Xcode builds)" : "Pretend it's Christmas (Xcode builds)") {
                christmas.toggle()
                PearlSeason.pretendItsChristmas = christmas
            }
            .font(.custom("AvenirNext-DemiBold", size: 12)).opacity(0.6)
            .buttonStyle(.plain)
            #endif
        }
    }

    /// Buying what's tried on (a limited edition only in its season), what earns it (one that's never sold), or a word on
    /// what to do.
    @ViewBuilder private var action: some View {
        if let item = trying, !item.onSale(),
           let why = item.earnedBy?.description ?? item.season.map({ "\($0.name) only: \($0.dates)" }) {
            Text(why)
                .font(.custom("AvenirNext-Heavy", size: 15)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 12)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        } else if let item = trying {
            let short = item.price - progress.pearls
            Button {
                if progress.buy(item) { trying = nil }
            } label: {
                HStack(spacing: 8) {
                    Text(short > 0 ? "\(short) more pearls" : "Buy \(item.name)")
                    if short <= 0 {
                        PearlIcon(size: 15)
                        Text("\(item.price)").monospacedDigit()
                    }
                }
                .font(.custom("AvenirNext-Heavy", size: 17))
                .foregroundStyle(short > 0 ? .white.opacity(0.7) : Color(red: 0.05, green: 0.18, blue: 0.35))
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(short > 0 ? Color.white.opacity(0.1) : Color.white))
            }
            .buttonStyle(.plain)
            .disabled(short > 0)
        } else {
            Text("Tap a look to wear it or try it on.")
                .font(.custom("AvenirNext-DemiBold", size: 14)).opacity(0.7)
                .multilineTextAlignment(.center)
                .frame(height: 48)
        }
    }

    /// The kinds of thing, and each one's looks: its plain one first (always yours), then what pearls buy.
    private var catalog: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(PearlItem.Kind.allCases, id: \.self) { each in
                    Button { kind = each } label: {
                        Text(each.title).font(.custom("AvenirNext-Heavy", size: 14))
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(each == kind ? Color.white.opacity(0.28) : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(each == kind ? .isSelected : [])
                }
            }
            .padding(.trailing, 56)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    tile(nil)
                    ForEach(GameTuning.pearlShop.filter { $0.kind == kind }) { item in tile(item) }
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Each kind from its top: one scrolled down, kept for a shorter kind, would hide its first row out of reach.
            .id(kind)
        }
    }

    /// A look (nil for this kind's plain one): your fish in it, its name, and its price, or that it's yours or on.
    private func tile(_ item: PearlItem?) -> some View {
        let owned = item.map(progress.owns) ?? true
        let worn = progress.look[kind]?.id == item?.id
        let tried = item != nil && trying == item
        // A limited edition out of its season, or a look not yet earned: shown, dimmed, to try on but not to buy.
        let locked = !owned && item?.onSale() == false
        return Button {
            guard let item else {
                trying = nil
                progress.wear(progress.look.without(kind))
                return
            }
            if owned {
                trying = nil
                progress.wear(progress.look.wearing(item))
            } else {
                trying = tried ? nil : item
            }
        } label: {
            VStack(spacing: 4) {
                PearlShopThumbnail(look: item.map(PlayerLook().wearing) ?? PlayerLook())
                    .frame(height: 50)
                Text(item?.name ?? "Plain").font(.custom("AvenirNext-DemiBold", size: 13)).lineLimit(1)
                Group {
                    if worn {
                        Label("On", systemImage: "checkmark")
                    } else if owned {
                        Text("Yours")
                    } else if locked, let goal = item?.earnedBy {
                        Text(goal.short)
                    } else if locked, let season = item?.season {
                        Text("\(season.name) only")
                    } else if let item {
                        HStack(spacing: 4) { PearlIcon(size: 11); Text("\(item.price)").monospacedDigit() }
                    }
                }
                .font(.custom("AvenirNext-Heavy", size: 12)).opacity(worn ? 1 : 0.75)
            }
            .opacity(locked ? 0.5 : 1)
            .padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(worn || tried ? 0.16 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                worn ? DeepEndColors.gold : tried ? .white : .white.opacity(0.15), lineWidth: worn || tried ? 2.5 : 1))
            .overlay(alignment: .topTrailing) {
                // A look that's earned has a trophy; a limited edition, its season's mark (Christmas's snowflake).
                if let symbol = item?.earnedBy != nil ? "trophy.fill" : item?.season?.symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .bold)).opacity(0.85).padding(8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(item, owned: owned, worn: worn, locked: locked))
    }

    private func accessibility(_ item: PearlItem?, owned: Bool, worn: Bool, locked: Bool) -> String {
        let name = item?.name ?? "Plain"
        if worn { return "\(name), wearing" }
        if owned { return "\(name), yours, tap to wear" }
        if locked, let goal = item?.earnedBy { return "\(name), earned: \(goal.description), tap to try on" }
        let limited = item?.season.map { ", \($0.name) only, \($0.dates)" } ?? ""
        if locked { return "\(name)\(limited), tap to try on" }
        return "\(name), \(item?.price ?? 0) pearls\(limited), tap to try on"
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 17, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.12)))
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20).padding(.top, 12)
        .accessibilityLabel("Close the pearl shop")
    }
}

/// A pearl, drawn as the Open Water's are: white with a pale rim and a glint.
struct PearlIcon: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white, Color(red: 0.93, green: 0.9, blue: 0.95)], center: .init(x: 0.35, y: 0.35),
                                 startRadius: 0, endRadius: size * 0.6))
            .overlay(Circle().stroke(Color(red: 0.8, green: 0.76, blue: 0.86), lineWidth: max(1, size * 0.1)))
            .overlay(Circle().fill(.white).frame(width: size * 0.3, height: size * 0.3).offset(x: -size * 0.18, y: -size * 0.18))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A look on your fish, still, for a shop tile (a trail shown as a few of its motes behind).
private struct PearlShopThumbnail: View {
    let look: PlayerLook

    var body: some View {
        if let image = PearlShopThumbnails.image(look) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "fish.fill").font(.system(size: 28)).foregroundStyle(.orange)
        }
    }
}

/// Shop tiles' pictures, drawn once each by a SpriteKit view that's never on screen. The view is paused except while it
/// draws one: left running after its first picture, it slowed every level for the rest of the session (Kraig's phone,
/// 2026-10-24: 60 frames a second instead of 120, and a 31-second freeze in Jelly Bloom).
@MainActor private enum PearlShopThumbnails {
    private static var images: [[String: String]: UIImage] = [:]
    private static let renderer: SKView = {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        view.isPaused = true
        return view
    }()

    static func image(_ look: PlayerLook) -> UIImage? {
        if let image = images[look.ids] { return image }
        let picture = SKNode()
        let fish = look.fish()
        fish.apply(radius: 30, facing: 1, tilt: 0, stretchX: 1, stretchY: 1, mouthOpen: 0, time: 0, tailRate: 0)
        picture.addChild(fish)
        if let trail = look.trail {
            let mote = PearlShopArt.mote(trail)
            for i in 0..<4 {
                let node = SKSpriteNode(texture: mote.texture)
                let side = mote.size * 30 * (1 - CGFloat(i) * 0.15)
                node.size = CGSize(width: side, height: side)
                node.position = CGPoint(x: -66 - CGFloat(i) * 16, y: sin(CGFloat(i) * 2.4) * 7 + (trail == .bubbles || trail == .cropDuster ? CGFloat(i) * 4 : 0))
                node.alpha = 1 - CGFloat(i) * 0.2
                if trail == .rainbow {
                    node.color = SKColor(hue: CGFloat(i) * 0.18, saturation: 0.85, brightness: 1, alpha: 1)
                    node.colorBlendFactor = 1
                }
                node.zPosition = -10 - CGFloat(i)
                picture.addChild(node)
            }
        }
        // Wide enough for the longest trail and tall enough for the tallest hat; the fish faces right, right of center.
        let crop = CGRect(x: -140, y: -45, width: 220, height: 104)
        renderer.isPaused = false
        let drawn = renderer.texture(from: picture, crop: crop)
        renderer.isPaused = true
        guard let texture = drawn else { return nil }
        let image = UIImage(cgImage: texture.cgImage())
        images[look.ids] = image
        return image
    }
}

/// The shop's preview: your fish swimming in place in what it's wearing and trying on, its trail streaming behind.
final class PearlShopPreviewScene: SKScene {
    var look = PlayerLook.plain {
        didSet { if look != oldValue { dress() } }
    }
    private var fish: FishNode?
    private let motes = PearlTrailMotes()
    /// How fast the water seems to pass (points a second), as your fish swims.
    private static let swim: CGFloat = 170

    override init() {
        super.init(size: CGSize(width: 300, height: 150))
        backgroundColor = .clear
        scaleMode = .resizeFill
        dress()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func dress() {
        fish?.removeFromParent()
        motes.removeAll()
        let node = look.fish()
        node.zPosition = 10
        addChild(node)
        fish = node
    }

    override func update(_ currentTime: TimeInterval) {
        guard let fish else { return }
        let time = CGFloat(currentTime)
        let radius = min(size.height * 0.24, 40)
        let spot = CGPoint(x: size.width * 0.6, y: size.height / 2 + sin(time * 2) * 5)
        fish.position = spot
        fish.apply(radius: radius, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1, mouthOpen: 0,
                   time: time, tailRate: 14)
        // The water goes by: where your fish is in it, and where a mote let go there is now.
        let swum = time * Self.swim
        if let trail = look.trail {
            motes.release(trail, position: CGPoint(x: swum, y: spot.y), radius: radius, facing: 1, time: time, into: self, z: 5)
        }
        motes.render(look.trail, time: time, scale: 1) { point in CGPoint(x: spot.x + point.x - swum, y: point.y) }
    }
}
