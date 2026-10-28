import FishKit
import SpriteKit
import SwiftUI

/// The pearl shop: the Open Water's pearls spent on looks for your fish, from the world
/// map's pearl button or a run's result card. A rail down the left of each kind of look, then your outfits (Kraig,
/// 2026-10-25: "Left category rail sounds great"); your fish in the middle; the shelf on the right. Tap something you
/// own to wear it, or something you don't to try it on your fish first and buy it there. Buying puts it on.
struct PearlShopView: View {
    @ObservedObject var progress: ArcadeProgress
    /// The Shop's tutorial over it (`ShopHints`), until it's tapped away (`onHintsSeen`).
    var showsHints = false
    /// A look bought here (for the stats' visit).
    var onBought: (PearlItem) -> Void = { _ in }
    var onHintsSeen: () -> Void = {}
    let onClose: () -> Void
    /// What's on the shelf: a kind's looks, or your saved outfits.
    private enum Shelf: Hashable {
        case kind(PearlItem.Kind)
        case outfits
    }
    @State private var shelf = Shelf.kind(.color)
    /// Something not yet owned, tried on in the preview.
    @State private var trying: PearlItem?
    @State private var shown = false
    /// Looks bought on this visit: each one buzzes.
    @State private var bought = 0
    @State private var preview = PearlShopPreviewScene()
    #if DEBUG
    /// Xcode builds: a season's limited editions on sale, whatever the date (`PearlSeason.pretend`).
    @State private var pretendSeason = PearlSeason.pretend
    /// Footage or a screenshot for the App Store: the Xcode-only buttons stay hidden.
    private var showsForTheStore: Bool { StoreFootage.shopTour || StoreCapture.moment != nil }
    #endif

    private var shownLook: PlayerLook { trying.map(progress.look.wearing) ?? progress.look }

    var body: some View {
        ZStack {
            LinearGradient(colors: [DeepEndColors.night, DeepEndColors.abyss], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScreenScaled { size, _ in
                ZStack(alignment: .topTrailing) {
                    HStack(alignment: .top, spacing: 16) {
                        rail.frame(width: 100).shopHintPart(.rail)
                        fitting.frame(width: min(270, size.width * 0.3))
                        shelfView.shopHintPart(.shelf)
                    }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
                    closeButton
                }
                .overlayPreferenceValue(ShopHintFrames.self) { anchors in
                    if showsHints {
                        GeometryReader { proxy in
                            ShopHints(frames: anchors.mapValues { proxy[$0] }, onDone: onHintsSeen)
                        }
                        .transition(.opacity)
                    }
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
        // Here, not on the buy button, which a purchase replaces.
        .sensoryFeedback(.success, trigger: bought) { _, _ in ArcadeSettings.shared.vibrationOn }
        .onDisappear { sawShelf() }
        #if DEBUG
        .task { if StoreFootage.shopTour { await tour() } }
        #endif
    }

    #if DEBUG
    /// Footage of the shop (`StoreFootage.shopTour`): each look's shelf, the look tried on, then bought.
    private func tour() async {
        for step in StoreFootage.shopTourSteps {
            try? await Task.sleep(for: .seconds(step.wait))
            guard let item = PearlItem.item(step.item) else { continue }
            if step.buys {
                if progress.buy(item) { trying = nil }
            } else {
                if shelf != .kind(item.kind) { shelf = .kind(item.kind) }
                trying = item
            }
        }
    }
    #endif

    // MARK: The rail

    /// Each kind of look, then your outfits. A kind with looks you haven't seen here has a dot. It scrolls on a screen too
    /// short for it all.
    private var rail: some View {
        ScrollView {
            railButtons
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var railButtons: some View {
        VStack(spacing: 6) {
            ForEach(PearlItem.Kind.allCases, id: \.self) { kind in
                railButton(.kind(kind), title: kind.title, symbol: kind.symbol,
                           hasNew: progress.shelf(kind).contains(where: progress.isNew))
            }
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 10)
            railButton(.outfits, title: "Outfits", symbol: "hanger", hasNew: false)
        }
        .padding(.top, 4)
    }

    private func railButton(_ target: Shelf, title: String, symbol: String, hasNew: Bool) -> some View {
        let selected = shelf == target
        return Button {
            guard !selected else { return }
            sawShelf()
            shelf = target
            // What was tried on comes off: its button would stay, about a look on another shelf (Kraig, 2026-10-27:
            // the heart glasses' "Valentine's only" still showed on Trails).
            trying = nil
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                Text(title).font(.custom("AvenirNext-Heavy", size: 13))
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(selected ? 0.24 : 0.07)))
            .overlay(alignment: .topTrailing) {
                if hasNew { Circle().fill(DeepEndColors.gold).frame(width: 9, height: 9).padding(7) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasNew ? "\(title), new looks" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The kind on the shelf, seen: its looks are no longer new (marked as you leave it, so you see what was).
    private func sawShelf() {
        guard case .kind(let kind) = shelf else { return }
        progress.sawLooks(progress.shelf(kind))
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
            .shopHintPart(.pearls)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(progress.pearls) pearls")
            // As often as the game draws: SpriteView's own 60 looked choppy on a 120 Hz screen.
            SpriteView(scene: preview, preferredFramesPerSecond: PearlShopPreviewScene.framesPerSecond,
                       options: [.allowsTransparency])
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 18).fill(
                    LinearGradient(colors: [Color(red: 0.12, green: 0.55, blue: 0.66), Color(red: 0.04, green: 0.24, blue: 0.4)],
                                   startPoint: .top, endPoint: .bottom)))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            // Out of the way of the Shop's tutorial's words.
            action.opacity(showsHints ? 0 : 1)
            #if DEBUG
            Button("+\(GameTuning.pearlShopTestGift) pearls (Xcode builds)") { progress.earnPearls(GameTuning.pearlShopTestGift) }
                .font(.custom("AvenirNext-DemiBold", size: 12)).opacity(showsHints || showsForTheStore ? 0 : 0.6)
                .buttonStyle(.plain)
            // Round the seasons, then back to the real date.
            Button("Season: \(pretendSeason?.name ?? "today's date") (Xcode builds)") {
                let seasons = PearlSeason.all
                let next = pretendSeason.flatMap { seasons.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                pretendSeason = next < seasons.count ? seasons[next] : nil
                PearlSeason.pretend = pretendSeason
            }
            .font(.custom("AvenirNext-DemiBold", size: 12)).opacity(showsHints || showsForTheStore ? 0 : 0.6)
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
                if progress.buy(item) {
                    trying = nil
                    ArcadeAudio.shared.play(.buy)
                    bought += 1
                    onBought(item)
                }
            } label: {
                // Not "Buy Mint chocolate chip": a long name wrapped to two lines (Kraig, 2026-10-27: "Let's just say
                // 'Buy'"). The tile tried on says what it is.
                HStack(spacing: 8) {
                    Text(short > 0 ? "\(short) more pearls" : "Buy")
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
            .accessibilityLabel(short > 0 ? "\(item.name): \(short) more pearls" : "Buy \(item.name) for \(item.price) pearls")
        } else {
            Text("Tap a look to wear it or try it on.")
                .font(.custom("AvenirNext-DemiBold", size: 14)).opacity(0.7)
                .multilineTextAlignment(.center)
                .frame(height: 48)
        }
    }

    // MARK: The shelf

    /// The shelf's name (beside the close button), and on it a kind's looks (its plain one first, always yours, then
    /// what pearls buy and what's earned) or your outfits.
    private var shelfView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shelfTitle).font(.custom("AvenirNext-Heavy", size: 22))
                .frame(height: 44)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                switch shelf {
                case .kind(let kind):
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        tile(nil, kind: kind)
                        ForEach(progress.shelf(kind)) { item in tile(item, kind: kind) }
                    }
                    .padding(.bottom, 8)
                case .outfits:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(1...GameTuning.pearlShopOutfits, id: \.self) { slot in outfitTile(slot) }
                    }
                    .padding(.bottom, 8)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Each shelf from its top: one scrolled down, kept for a shorter shelf, would hide its first row out of reach.
            .id(shelf)
        }
    }

    private var shelfTitle: String {
        switch shelf {
        case .kind(let kind): kind.title
        case .outfits: "Outfits"
        }
    }

    /// A saved outfit: your fish in it (tap to wear it all at once), and a button to save what you're wearing there.
    private func outfitTile(_ slot: Int) -> some View {
        let look = progress.outfit(slot)
        let worn = look != nil && look == progress.look
        return VStack(spacing: 8) {
            Button {
                guard let look else { return }
                trying = nil
                progress.wear(look)
            } label: {
                VStack(spacing: 4) {
                    if let look {
                        PearlShopThumbnail(look: look).frame(height: 56)
                    } else {
                        Image(systemName: "plus.circle").font(.system(size: 26, weight: .semibold)).opacity(0.5)
                            .frame(height: 56)
                    }
                    Text("Outfit \(slot)").font(.custom("AvenirNext-DemiBold", size: 13))
                    Group {
                        if worn { Label("On", systemImage: "checkmark") } else { Text(look == nil ? "Empty" : "Tap to wear") }
                    }
                    .font(.custom("AvenirNext-Heavy", size: 12)).opacity(worn ? 1 : 0.75)
                }
                .padding(.vertical, 10).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(worn ? 0.16 : 0.07)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(worn ? DeepEndColors.gold : .white.opacity(0.15),
                                                                   lineWidth: worn ? 2.5 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(look == nil ? "Outfit \(slot), empty" : worn ? "Outfit \(slot), wearing" : "Outfit \(slot), tap to wear")
            Button {
                trying = nil
                progress.saveOutfit(slot)
            } label: {
                Text("Save what I'm wearing").font(.custom("AvenirNext-DemiBold", size: 12))
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save what you're wearing as outfit \(slot)")
        }
    }

    /// A look (nil for this kind's plain one): your fish in it, its name, and its price, or that it's yours or on, or new.
    private func tile(_ item: PearlItem?, kind: PearlItem.Kind) -> some View {
        let owned = item.map(progress.owns) ?? true
        let new = item.map(progress.isNew) ?? false
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
                // Long names ("Mint chocolate chip") shrink to fit the narrowest tile rather than lose their end.
                Text(item?.name ?? "Plain").font(.custom("AvenirNext-DemiBold", size: 13)).lineLimit(1)
                    .minimumScaleFactor(0.7).padding(.horizontal, 6)
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
            .overlay(alignment: .topLeading) {
                // New since you were last here.
                if new {
                    Text("New").font(.custom("AvenirNext-Heavy", size: 10))
                        .foregroundStyle(Color(red: 0.25, green: 0.17, blue: 0.02))
                        .padding(.horizontal, 6).frame(height: 16)
                        .background(Capsule().fill(DeepEndColors.gold)).padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((new ? "New: " : "") + accessibility(item, owned: owned, worn: worn, locked: locked))
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
                node.position = CGPoint(x: -66 - CGFloat(i) * 16, y: sin(CGFloat(i) * 2.4) * 7 + ([.bubbles, .cropDuster, .notes, .hearts].contains(trail) ? CGFloat(i) * 4 : 0))
                node.alpha = 1 - CGFloat(i) * 0.2
                // Colored as in the water (a rainbow's hues spread wide, to show four of them), where the tile had drawn
                // confetti and comets white. A comet's motes cool along its tail.
                PearlShopArt.dress(node, as: trail, number: trail == .rainbow ? i * 4 : i)
                if trail == .comet { node.color = PearlShopArt.cometColor(CGFloat(i) / 4) }
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
    /// The last frame's time, for a fish dressed between frames.
    private var time: CGFloat = 0
    /// How fast the water seems to pass (points a second), as your fish swims.
    private static let swim: CGFloat = 170
    static let framesPerSecond = 120

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
        // In its place now: left to the next frame, a new look flashed in the scene's corner first.
        swim(node)
    }

    /// Your fish in its place at `time`, swimming: where it is, and its radius.
    @discardableResult private func swim(_ fish: FishNode) -> (spot: CGPoint, radius: CGFloat) {
        let radius = min(size.height * 0.24, 40)
        let spot = CGPoint(x: size.width * 0.6, y: size.height / 2 + sin(time * 2) * 5)
        fish.position = spot
        fish.apply(radius: radius, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1, mouthOpen: 0,
                   time: time, tailRate: 14)
        return (spot, radius)
    }

    override func update(_ currentTime: TimeInterval) {
        guard let fish else { return }
        time = CGFloat(currentTime)
        let (spot, radius) = swim(fish)
        // The water goes by: where your fish is in it, and where a mote let go there is now.
        let swum = time * Self.swim
        if let trail = look.trail {
            motes.release(trail, position: CGPoint(x: swum, y: spot.y), radius: radius, facing: 1, time: time, into: self, z: 5)
        }
        motes.render(look.trail, time: time, scale: 1) { point in CGPoint(x: spot.x + point.x - swum, y: point.y) }
    }
}
