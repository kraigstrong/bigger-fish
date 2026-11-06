import FishKit
import SpriteKit
import UIKit

// Settings and the grown-ups' screens behind it (the parental gate, then privacy, support, and purchases), drawn like
// Bigger Fish's Settings with FishKit's menu controls, in the reef's colors: the unlock screen's deep water and the
// reef's gold.

extension MenuTheme {
    static let reef = MenuTheme(
        accent: ReefStyle.gold, onAccent: ReefStyle.ink,
        backdropTop: SKColor(red: 0.05, green: 0.19, blue: 0.38, alpha: 1),
        backdropBottom: SKColor(red: 0.02, green: 0.08, blue: 0.20, alpha: 1)
    )
}

/// One of Settings' screens, over the whole scene: a title (and a line under it), then columns of settings or the
/// parental gate's keypad, centered on the screen, with a close button where the map's gear is. Laid out at its natural
/// size on every phone; on an iPad the scene is drawn bigger (ReefScreen.swift). Every node has its own depth: the scene
/// ignores sibling order.
final class SettingsMenu: SKNode {
    /// Something in a column, top to bottom.
    enum Item {
        case heading(String)
        /// A switch. `toggle` changes the setting and says what it is now.
        case toggle(String, symbol: String, isOn: Bool, toggle: () -> Bool)
        /// A button row; `trailing` is a symbol at its end (a link's arrow).
        case row(String, symbol: String, trailing: String? = nil, action: () -> Void)
        /// Small buttons, two to a row: Xcode builds' shortcuts.
        case shortcuts([(title: String, action: () -> Void)])
        /// A line or two of small text.
        case note(String)
    }

    enum Body {
        case columns([[Item]])
        /// The parental gate: its question, the answer so far, and a keypad.
        case keypad(question: String, entry: String, digit: (Int) -> Void, delete: () -> Void, cancel: () -> Void)
    }

    /// The screen's buttons, in the scene's coordinates (this node sits at the scene's origin), for the scene's touches.
    /// On the keypad, the last is the rest of the screen, which does nothing: a tap between keys doesn't close the gate.
    private(set) var buttons: [(frame: CGRect, action: () -> Void)] = []

    static let columnWidth = MenuSwitchRow.size.width
    static let columnGap: CGFloat = 40
    private static let itemGap: CGFloat = 8
    /// Above a heading that follows other items, on top of `itemGap`.
    private static let headingGap: CGFloat = 6
    private static let shortcutHeight: CGFloat = 34
    private static let key = CGSize(width: 64, height: 46)
    private static let keyGap: CGFloat = 10

    /// The content, drawn over the backdrop: positioned once its height is known, so it sits in the middle.
    private let content = SKNode()

    init(size: CGSize, title: String, subtitle: String? = nil, closeAt: CGPoint, onClose: @escaping () -> Void,
         body: Body) {
        super.init()
        let backdrop = MenuBackdrop.node(size: size, theme: .reef)
        // Opaque, as Bigger Fish's Settings and the unlock screen are: the map's names would read through the settings.
        backdrop.alpha = 1
        // Over the map, as the panel's scrim was; everything else sits on it.
        backdrop.zPosition = -2
        addChild(backdrop)
        content.zPosition = 3
        addChild(content)

        var y: CGFloat = 0
        let heading = reefLabel(title, fontSize: 26, heavy: true)
        heading.position = CGPoint(x: size.width / 2, y: y - 15)
        content.addChild(heading)
        y -= 30
        if let subtitle {
            let line = reefLabel(subtitle, fontSize: 14, heavy: false, color: SKColor(white: 1, alpha: 0.65))
            line.position = CGPoint(x: size.width / 2, y: y - 12)
            content.addChild(line)
            y -= 22
        }
        y -= 14

        var controls: [(frame: CGRect, action: () -> Void)] = []
        switch body {
        case .columns(let columns):
            let total = CGFloat(columns.count) * Self.columnWidth + CGFloat(max(0, columns.count - 1)) * Self.columnGap
            var bottom = y
            for (index, column) in columns.enumerated() {
                let x = (size.width - total) / 2 + Self.columnWidth / 2 + CGFloat(index) * (Self.columnWidth + Self.columnGap)
                bottom = min(bottom, layOut(column, x: x, top: y, controls: &controls))
            }
            y = bottom
        case let .keypad(question, entry, digit, delete, cancel):
            y = layOutKeypad(question: question, entry: entry, centerX: size.width / 2, top: y, digit: digit,
                             delete: delete, cancel: cancel, controls: &controls)
        }

        // In the middle of the screen, top to bottom.
        content.position.y = ((size.height - y) / 2).rounded()
        buttons = controls.map { ($0.frame.offsetBy(dx: 0, dy: content.position.y), $0.action) }

        let close = MenuCloseButton()
        close.position = closeAt
        close.zPosition = 3
        addChild(close)
        buttons.append((close.hitFrame, onClose))
        if case .keypad = body { buttons.append((CGRect(origin: .zero, size: size), {})) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// "Version 1.1.0 (2)", from the app's Info.plist.
    static func versionLine(_ info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String
        return "Version \(version)" + (build.map { " (\($0))" } ?? "")
    }

    // MARK: Layout

    /// Lays out a column centered on `x` from `top` down, and returns where it ends.
    private func layOut(_ items: [Item], x: CGFloat, top: CGFloat,
                        controls: inout [(frame: CGRect, action: () -> Void)]) -> CGFloat {
        let width = Self.columnWidth, left = x - width / 2
        var y = top
        for (index, item) in items.enumerated() {
            if index > 0 { y -= Self.itemGap }
            switch item {
            case .heading(let title):
                if index > 0 { y -= Self.headingGap }
                let heading = menuHeading(title)
                heading.position = CGPoint(x: left, y: y - 7)
                content.addChild(heading)
                y -= 14
            case let .toggle(title, symbol, isOn, toggle):
                let row = MenuSwitchRow(title: title, symbol: symbol, isOn: isOn, theme: .reef)
                row.position = CGPoint(x: x, y: y - MenuSwitchRow.size.height / 2)
                content.addChild(row)
                controls.append((row.hitFrame, { [weak row] in row?.setOn(toggle(), animated: true) }))
                y -= MenuSwitchRow.size.height
            case let .row(title, symbol, trailing, action):
                let row = MenuButtonRow(title: title, symbol: symbol, style: .secondary, theme: .reef, trailing: trailing)
                row.position = CGPoint(x: x, y: y - row.size.height / 2)
                content.addChild(row)
                controls.append((row.hitFrame, action))
                y -= row.size.height
            case .shortcuts(let shortcuts):
                let size = CGSize(width: (width - Self.itemGap) / 2, height: Self.shortcutHeight)
                for (number, shortcut) in shortcuts.enumerated() {
                    if number > 0 && number.isMultiple(of: 2) { y -= size.height + Self.itemGap }
                    // One alone on its row is as wide as the column.
                    let alone = number == shortcuts.count - 1 && number.isMultiple(of: 2)
                    let keySize = alone ? CGSize(width: width, height: size.height) : size
                    let button = MenuButtonRow(title: shortcut.title, symbol: nil, style: .key, theme: .reef,
                                               size: keySize, fontSize: 14)
                    let column = alone ? 0 : CGFloat(number % 2)
                    button.position = CGPoint(x: left + keySize.width / 2 + column * (size.width + Self.itemGap),
                                              y: y - size.height / 2)
                    content.addChild(button)
                    controls.append((button.hitFrame, shortcut.action))
                }
                if !shortcuts.isEmpty { y -= size.height }
            case .note(let text):
                let note = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
                note.text = text
                note.fontSize = 12
                note.fontColor = SKColor(white: 1, alpha: 0.55)
                note.numberOfLines = 0
                note.lineBreakMode = .byWordWrapping
                note.preferredMaxLayoutWidth = width
                note.horizontalAlignmentMode = .left
                note.verticalAlignmentMode = .top
                note.position = CGPoint(x: left, y: y)
                content.addChild(note)
                y -= note.frame.height
            }
        }
        return y
    }

    /// The gate's question and answer so far, over a keypad: 1 to 5, 6 to 9 and 0, then Delete and Cancel, the same on
    /// every screen size. Returns where it ends.
    private func layOutKeypad(question: String, entry: String, centerX: CGFloat, top: CGFloat,
                              digit: @escaping (Int) -> Void, delete: @escaping () -> Void,
                              cancel: @escaping () -> Void,
                              controls: inout [(frame: CGRect, action: () -> Void)]) -> CGFloat {
        var y = top
        let asked = reefLabel(question, fontSize: 20, heavy: false)
        asked.position = CGPoint(x: centerX, y: y - 12)
        content.addChild(asked)
        y -= 30
        let answer = reefLabel(entry, fontSize: 30, heavy: true)
        answer.position = CGPoint(x: centerX, y: y - 18)
        content.addChild(answer)
        y -= 36 + 14

        let key = Self.key, gap = Self.keyGap
        let rowWidth = key.width * 5 + gap * 4
        let rows: [[(title: String, symbol: String?, width: CGFloat, action: () -> Void)]] = [
            (1...5).map { number in ("\(number)", nil, key.width, { digit(number) }) },
            [6, 7, 8, 9, 0].map { number in ("\(number)", nil, key.width, { digit(number) }) },
            [("Delete", "delete.left", (rowWidth - gap) / 2, delete), ("Cancel", "xmark", (rowWidth - gap) / 2, cancel)],
        ]
        for (index, row) in rows.enumerated() {
            if index > 0 { y -= gap }
            var x = centerX - rowWidth / 2
            for item in row {
                let button = MenuButtonRow(title: item.title, symbol: item.symbol, style: .key, theme: .reef,
                                           size: CGSize(width: item.width, height: key.height),
                                           fontSize: item.symbol == nil ? 22 : 17)
                button.position = CGPoint(x: x + item.width / 2, y: y - key.height / 2)
                content.addChild(button)
                controls.append((button.hitFrame, item.action))
                x += item.width + gap
            }
            y -= key.height
        }
        return y
    }
}
