import SwiftUI

/// Where the app's links go. The privacy policy has to be easy to find from inside the app (App Review 5.1.1),
/// since the game sends anonymous gameplay counts.
enum ArcadeLinks {
    static let privacy = URL(string: "https://biggerfish.app/privacy")!
    static let support = URL(string: "https://biggerfish.app/support")!
}

/// Settings, from the gear on the home screen: sound, music, and vibration; replaying the tutorial; restoring the
/// unlock; the privacy policy and support; the credits, played as a little game (`CreditsScene`); and the version.
struct SettingsView: View {
    @ObservedObject var settings = ArcadeSettings.shared
    @ObservedObject var purchases: ArcadePurchases
    /// Counts how a restore here goes (the paywall funnel).
    var analytics: ArcadeAnalytics? = nil
    let onReplayTutorial: () -> Void
    let onPlayCredits: () -> Void
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var restoring: RestoreState = .idle
    @State private var shown = false

    enum RestoreState: Equatable { case idle, working, restored, nothing }

    var body: some View {
        ZStack {
            LinearGradient(colors: [DeepEndColors.night, DeepEndColors.abyss], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            ScreenScaled { size, _ in
                ZStack(alignment: .topTrailing) {
                    content(height: size.height)
                    closeButton
                }
            }
        }
        .foregroundStyle(.white)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
    }

    /// Scrolls only if it has to (large text, a small phone); the close button stays put. On a screen taller than a
    /// phone's (an iPad), it sits in the middle.
    private func content(height: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Settings").font(.custom("AvenirNext-Heavy", size: 26))
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        heading("Sound")
                        toggle("Sound effects", symbol: "speaker.wave.2.fill", isOn: $settings.soundEffectsOn)
                        toggle("Music", symbol: "music.note", isOn: $settings.musicOn)
                        toggle("Vibration", symbol: "iphone.radiowaves.left.and.right", isOn: $settings.vibrationOn)
                        heading("Play").padding(.top, 6)
                        row("Replay the tutorial", symbol: "arrow.counterclockwise", action: onReplayTutorial)
                    }
                    .frame(maxWidth: 320)
                    VStack(alignment: .leading, spacing: 8) {
                        if Self.showsRestore(selling: ArcadeUnlock.isSelling, unlocked: purchases.isUnlocked) {
                            heading("Purchases")
                            row(restoreTitle, symbol: "arrow.down.circle", action: restore)
                                .disabled(restoring == .working)
                        }
                        heading("Help")
                        row("Privacy policy", symbol: "hand.raised.fill", trailing: "arrow.up.right") { openURL(ArcadeLinks.privacy) }
                        row("Support", symbol: "questionmark.circle.fill", trailing: "arrow.up.right") { openURL(ArcadeLinks.support) }
                        heading("Credits").padding(.top, 6)
                        row("Play the credits", symbol: "fish.fill", action: onPlayCredits)
                        Text(Self.versionLine(Bundle.main.infoDictionary ?? [:]))
                            .font(.custom("AvenirNext-DemiBold", size: 12)).opacity(0.55)
                    }
                    .frame(maxWidth: 320)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height > ScreenFit.largestPhone.height ? height : nil)
        }
        .scrollBounceBehavior(.basedOnSize)
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
        .accessibilityLabel("Close settings")
    }

    /// Restoring only means something while the unlock is on sale and not yet bought.
    static func showsRestore(selling: Bool, unlocked: Bool) -> Bool { selling && !unlocked }

    /// "Version 0.3 (12)", from the app's Info.plist.
    static func versionLine(_ info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String
        return "Version \(version)" + (build.map { " (\($0))" } ?? "")
    }

    private var restoreTitle: String {
        switch restoring {
        case .idle: "Restore purchase"
        case .working: "Checking with the App Store…"
        case .restored: "Every world is open!"
        case .nothing: "No unlock found for this Apple Account"
        }
    }

    private func restore() {
        restoring = .working
        Task {
            let found = await purchases.restore()
            analytics?.restoreInSettings(found: found)
            restoring = found ? .restored : .nothing
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title.uppercased()).font(.custom("AvenirNext-Heavy", size: 12)).tracking(1.2).opacity(0.6)
    }

    private func toggle(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol).font(.custom("AvenirNext-DemiBold", size: 16))
        }
        .tint(DeepEndColors.gold)
        .frame(minHeight: 40)
    }

    private func row(_ title: String, symbol: String, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol).font(.custom("AvenirNext-DemiBold", size: 16))
                Spacer(minLength: 8)
                if let trailing { Image(systemName: trailing).font(.system(size: 13, weight: .bold)).opacity(0.6) }
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
