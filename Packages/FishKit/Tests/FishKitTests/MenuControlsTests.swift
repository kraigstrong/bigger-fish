import SpriteKit
import Testing
import UIKit
@testable import FishKit

@MainActor
struct MenuControlsTests {
    private let theme = MenuTheme(accent: .yellow, onAccent: .blue, backdropTop: .cyan, backdropBottom: .black)

    private func labels(in node: SKNode) -> [SKLabelNode] { node.children.compactMap { $0 as? SKLabelNode } }

    /// A title too long for its row shrinks to fit between the icon and the link's arrow, rather than running past.
    @Test func longTitlesFitTheirRow() {
        let row = MenuButtonRow(title: "A title far too long for any settings row to hold", symbol: "lock.fill",
                                style: .secondary, theme: theme, trailing: "arrow.up.right")
        let title = labels(in: row)[0]
        #expect(title.frame.maxX <= row.size.width / 2 - 14)
        #expect(title.frame.minX >= -row.size.width / 2)

        let short = MenuButtonRow(title: "Support", symbol: "questionmark.circle.fill", style: .secondary, theme: theme)
        #expect(labels(in: short)[0].xScale == 1)
    }

    /// A key's icon and title sit together in its middle.
    @Test func keysCenterTheirContent() {
        let key = MenuButtonRow(title: "Delete", symbol: "delete.left", style: .key, theme: theme,
                                size: CGSize(width: 175, height: 46))
        let content = key.children.filter { !($0 is SKShapeNode) }.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        #expect(abs(content.midX) < 0.5)
        #expect(key.hitFrame.size == CGSize(width: 175, height: 46))
    }

    @Test func switchesTurnOnAndOff() {
        let toggle = MenuSwitchRow(title: "Music", symbol: "music.note", isOn: true, theme: theme)
        toggle.setOn(false, animated: false)
        #expect(!toggle.isOn)
        toggle.position = CGPoint(x: 100, y: 50)
        // The whole row toggles, not just the switch.
        #expect(toggle.hitFrame == CGRect(x: 100 - MenuSwitchRow.size.width / 2, y: 50 - MenuSwitchRow.size.height / 2,
                                          width: MenuSwitchRow.size.width, height: MenuSwitchRow.size.height))
    }
}
