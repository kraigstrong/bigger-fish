import SwiftUI

/// The Shop's tutorial (`ArcadeTutorial.Course.shop`): the first time the shop opens, its three parts lit and the rest
/// dimmed, each with a word and an arrow: your pearls, the rail of kinds of look, and the shelf. One tap anywhere and
/// it's gone. (Kraig, 2026-10-27: "this one can likely just be some text and an arrow or two".)
struct ShopHints: View {
    /// Where each part is, in this view's space.
    let frames: [ShopHints.Part: CGRect]
    let onDone: () -> Void
    @State private var shown = false

    enum Part: Hashable { case pearls, rail, shelf }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                dim(size)
                if let pearls = frames[.pearls] {
                    // Under your pearls, across the middle column.
                    callout("Your pearls", detail: "Gather them in Open Water", arrow: "arrow.up", arrowFirst: true)
                        .frame(width: 260)
                        .position(x: pearls.midX, y: pearls.maxY + 52)
                    let below = pearls.maxY + 52 + 40
                    if let shelf = frames[.shelf] {
                        callout("Tap a look to try it on", arrow: "arrow.right", arrowFirst: false)
                            .fixedSize()
                            .frame(width: 0, alignment: .trailing)
                            .position(x: shelf.minX - 10, y: below + (size.height - below) * 0.22)
                    }
                    if let rail = frames[.rail] {
                        callout("Pick a kind", detail: "Hats, colors, and more", arrow: "arrow.left", arrowFirst: true)
                            .fixedSize()
                            .frame(width: 0, alignment: .leading)
                            .position(x: rail.maxX + 10, y: below + (size.height - below) * 0.55)
                    }
                }
                Text("Tap anywhere to start")
                    .font(.custom("AvenirNext-DemiBold", size: 14)).opacity(0.75)
                    .frame(width: size.width)
                    .position(x: frames[.pearls]?.midX ?? size.width / 2, y: size.height - 18)
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.3).delay(0.25)) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your pearls, gathered in Open Water, are at the top. Pick a kind of look on the left, "
            + "then tap a look to try it on.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Start shopping", onDone)
    }

    /// Everything dimmed but the three parts.
    private func dim(_ size: CGSize) -> some View {
        Rectangle().fill(.black.opacity(0.62))
            .mask {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                    ForEach(Array(frames.values.enumerated()), id: \.offset) { _, frame in
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: frame.width + 12, height: frame.height + 12)
                            .position(x: frame.midX, y: frame.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .frame(width: size.width, height: size.height)
    }

    /// A line (and a smaller one under it), with a gold arrow before or after it.
    private func callout(_ line: String, detail: String? = nil, arrow: String, arrowFirst: Bool) -> some View {
        let pointer = Image(systemName: arrow).font(.system(size: 22, weight: .heavy)).foregroundStyle(DeepEndColors.gold)
        let words = VStack(spacing: 2) {
            Text(line).font(.custom("AvenirNext-Heavy", size: 18))
            if let detail { Text(detail).font(.custom("AvenirNext-DemiBold", size: 14)).opacity(0.85) }
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        return Group {
            if arrow == "arrow.up" {
                VStack(spacing: 6) { pointer; words }
            } else {
                HStack(spacing: 8) {
                    if arrowFirst { pointer }
                    words
                    if !arrowFirst { pointer }
                }
            }
        }
    }
}

/// Where each of the shop's parts is, for its tutorial's arrows.
struct ShopHintFrames: PreferenceKey {
    static let defaultValue: [ShopHints.Part: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ShopHints.Part: Anchor<CGRect>], nextValue: () -> [ShopHints.Part: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this as one of the shop's parts, for its tutorial.
    func shopHintPart(_ part: ShopHints.Part) -> some View {
        anchorPreference(key: ShopHintFrames.self, value: .bounds) { [part: $0] }
    }
}
