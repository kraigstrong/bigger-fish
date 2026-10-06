import SwiftUI

/// Shown at launch while levels load: art from the game's own fish, the title fading in, and a short bar
/// sliding back and forth along a track (Keepsake's startup screen, in Bigger Fish's water).
struct LaunchView: View {
    var art = Image("LaunchArt")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleShown = false
    @State private var sliding = false

    private static let track: CGFloat = 140
    private static let fill: CGFloat = track * 0.4

    var body: some View {
        ZStack {
            OceanBackdrop(bloom: false)
            VStack(spacing: 18) {
                art.resizable().scaledToFit().frame(height: 150)
                Text("Bigger Fish")
                    .font(.custom("AvenirNext-Heavy", size: 34))
                    .foregroundStyle(.white)
                    .opacity(titleShown ? 1 : 0)
                    .offset(y: titleShown ? 0 : 8)
                Capsule().fill(.white.opacity(0.18))
                    .frame(width: Self.track, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white)
                            .frame(width: Self.fill, height: 6)
                            .offset(x: reduceMotion ? 0 : (sliding ? Self.track - Self.fill : 0))
                    }
                    .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bigger Fish, loading")
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.4)) { titleShown = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sliding = true }
        }
    }
}
