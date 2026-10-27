import AVFoundation
import SwiftUI
import UIKit

/// What the unlock opens: a clip of each world it adds, The Deep End, its price, and restore. Shown when a player taps
/// a level past the free ones (or plays up to one), taps Unlock on the home screen or the world map, or beats Shallow Reef without it.
struct UnlockView: View {
    @ObservedObject var purchases: ArcadePurchases
    /// The world the player was trying to get into, ringed in its color.
    var featured: ArcadeWorld? = nil
    /// The world just beaten, when this stands in for its "conquered" screen.
    var conquered: ArcadeWorld? = nil
    /// What opened this screen, for counting how buying and restoring go here; nil (a tuner preview) isn't counted.
    var source: ArcadeAnalytics.OfferSource? = nil
    var analytics: ArcadeAnalytics? = nil
    let onClose: () -> Void

    private enum Stage: Equatable {
        case offer, working
        case message(String, String, unlocked: Bool)
    }
    @State private var stage = Stage.offer
    @State private var shown = false

    var body: some View {
        ZStack {
            // Solid deep water, so nothing behind shows through the words.
            LinearGradient(colors: [DeepEndColors.night, DeepEndColors.abyss], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScreenScaled { size, _ in
                switch stage {
                case .offer:
                    offer(in: size)
                case .working:
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Talking to the App Store…").font(.custom("AvenirNext-DemiBold", size: 17))
                    }
                case .message(let title, let line, let unlocked):
                    VStack(spacing: 10) {
                        if unlocked { DeepEndBadge(size: 84) }
                        Text(title).font(.custom("AvenirNext-Heavy", size: 28)).multilineTextAlignment(.center)
                        Text(line).font(.custom("AvenirNext-DemiBold", size: 16)).multilineTextAlignment(.center).opacity(0.85)
                        GoldButton(title: unlocked ? "Let's swim" : "OK") { unlocked ? onClose() : (stage = .offer) }
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 40)
                }
            }
        }
        .foregroundStyle(.white)
        .scaleEffect(shown ? 1 : 0.92).opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { shown = true } }
        // Bought on another device, approved by a parent, or restored while this was open.
        .onChange(of: purchases.isUnlocked) { _, unlocked in
            if unlocked && stage == .offer { stage = Self.unlockedMessage }
        }
        .task { await purchases.loadProduct() }
    }

    /// What the screen says first: a world conquered, the day's free Open Water runs used up, or the unlock itself.
    private var headline: (title: String, line: String) {
        if let conquered { return ("\(conquered.title) conquered!", "Ready for bigger water? Unlock every world.") }
        if source == .openWaterLimit {
            return ("\(GameTuning.freeOpenWaterRunsPerDay) more runs tomorrow",
                    "Or unlock every world, and swim the Open Water as much as you like.")
        }
        return ("Unlock every world", "Swim anywhere you like, whenever you like.")
    }

    /// Spread over the screen's height. On a screen taller than a phone's (an iPad), the clips grow a little and it
    /// sits in the middle, no more spread out than that.
    private func offer(in size: CGSize) -> some View {
        let worlds = ArcadeUnlock.worldsItOpens
        let gap: CGFloat = 14
        let taller = ScreenFit.tallness(of: size)
        let cardWidth = min(232 * taller, (size.width - 48 - gap * CGFloat(max(worlds.count - 1, 0))) / CGFloat(max(worlds.count, 1)))
        let margin: CGFloat = 12
        return VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(headline.title)
                    .font(.custom("AvenirNext-Heavy", size: 27))
                Text(headline.line)
                    .font(.custom("AvenirNext-DemiBold", size: 14)).opacity(0.85)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 8)
            HStack(alignment: .top, spacing: gap) {
                ForEach(worlds) { world in
                    WorldClipCard(world: world, width: cardWidth, featured: world == featured)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                DeepEndBadge(size: 30)
                Text("Plus The Deep End in every world: \(ArcadeUnlock.deepEndLevels) extra-hard levels.")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
            }
            Spacer(minLength: 8)
            GoldButton(title: purchases.displayPrice.map { "Unlock all for \($0)" } ?? "Unlock all", action: buy)
            HStack(spacing: 22) {
                Text("One-time purchase. No ads.").opacity(0.6)
                Button("Restore purchase", action: restore).buttonStyle(.plain).opacity(0.85)
                Button(conquered == nil ? "Not now" : "Maybe later", action: onClose).buttonStyle(.plain).opacity(0.85)
            }
            .font(.custom("AvenirNext-DemiBold", size: 13))
            .padding(.top, 8)
        }
        .frame(width: size.width, height: min(size.height, ScreenFit.largestPhone.height * taller) - margin * 2)
        .frame(width: size.width, height: size.height)
    }

    private static let unlockedMessage = Stage.message("Every world is open!",
                                                       "Swim anywhere you like. Beat a world's level 10 to open its Deep End.",
                                                       unlocked: true)

    private func buy() {
        stage = .working
        Task {
            let outcome = await purchases.purchase()
            if let source { analytics?.purchase(outcome, from: source) }
            switch outcome {
            case .unlocked:
                stage = Self.unlockedMessage
            case .pending:
                stage = .message("Waiting for approval", "Once it's approved, every world opens.", unlocked: false)
            case .cancelled:
                stage = .offer
            case .failed:
                stage = .message("Something went wrong", "The App Store didn't finish the purchase. Try again later.",
                                 unlocked: false)
            }
        }
    }

    private func restore() {
        stage = .working
        Task {
            let found = await purchases.restore()
            if let source { analytics?.restore(found: found, from: source) }
            stage = found ? Self.unlockedMessage
                : .message("Nothing to restore", "No unlock was found for this Apple Account.", unlocked: false)
        }
    }

    private struct GoldButton: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title).font(.custom("AvenirNext-Heavy", size: 19))
                    .foregroundStyle(Color(red: 0.04, green: 0.12, blue: 0.24))
                    .padding(.horizontal, 34).padding(.vertical, 11)
                    .background(DeepEndColors.gold, in: Capsule())
                    .shadow(color: DeepEndColors.gold.opacity(0.45), radius: 12)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One world on the unlock screen: a looping clip of it being played, its name, and its one line.
private struct WorldClipCard: View {
    let world: ArcadeWorld
    let width: CGFloat
    let featured: Bool

    var body: some View {
        // The clips are cut to the playfield's shape.
        let height = (width * GameTuning.playfieldSize.height / GameTuning.playfieldSize.width).rounded()
        VStack(spacing: 4) {
            WorldClip(world: world)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(world.color.opacity(featured ? 1 : 0.6), lineWidth: featured ? 3 : 1.5))
                .shadow(color: world.color.opacity(featured ? 0.7 : 0.3), radius: featured ? 16 : 8)
            Text(world.title).font(.custom("AvenirNext-Heavy", size: 17)).foregroundStyle(world.color)
                .padding(.top, 4)
            Text(world.subtitle).font(.custom("AvenirNext-DemiBold", size: 12)).opacity(0.85)
                .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(world.title): \(world.subtitle)")
    }
}

/// A world's clip (WorldClips/clip-<world ID>.mp4), silent and looping; its first frame stands still with Reduce
/// Motion on. A world without a clip shows its map picture.
struct WorldClip: View {
    let world: ArcadeWorld
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let url = Bundle.main.url(forResource: "clip-\(world.rawValue)", withExtension: "mp4") {
            LoopingVideo(url: url, plays: !reduceMotion).accessibilityHidden(true)
        } else {
            ZStack {
                world.color.opacity(0.15)
                WorldIllustration(world: world).padding(12)
            }
        }
    }
}

private struct LoopingVideo: UIViewRepresentable {
    let url: URL
    let plays: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        // Silent clips: never take over the game's music.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        view.looper = AVPlayerLooper(player: player, templateItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        if plays { player.play() }
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard let player = view.playerLayer.player else { return }
        if plays && player.rate == 0 { player.play() } else if !plays { player.pause() }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
        view.looper?.disableLooping()
        view.looper = nil
        view.playerLayer.player = nil
    }

    final class PlayerView: UIView {
        var looper: AVPlayerLooper?
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
