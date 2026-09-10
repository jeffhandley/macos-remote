import MacOSRemote
import SwiftUI
import UIKit

struct MacBookKeyboardView: View {
    @ObservedObject var model: RemoteAppModel
    @State private var modifiers = ModifierLatch()

    var body: some View {
        VStack(spacing: 0) {
            ModeHeaderView(model: model, currentMode: .macBookKeyboard)

            VStack(spacing: 5) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                    KeyboardRow(
                        keys: row,
                        modifiers: $modifiers,
                        send: send
                    )
                }
            }
            .padding(6)
            .background(Color(uiColor: .systemBackground))
        }
        .onAppear {
            AppOrientation.request(.landscape)
        }
    }

    private func send(_ key: RemoteKey) {
        model.send(.key(KeyStroke(
            key: key,
            modifiers: modifiers.activeFlags
        )))
        modifiers.consumeOneShotModifiers()
    }

    private static let rows: [[KeyboardKeySpec]] = [
        [
            .key("esc", .escape),
            .key("F1", .f1), .key("F2", .f2), .key("F3", .f3),
            .key("F4", .f4), .key("F5", .f5), .key("F6", .f6),
            .key("F7", .f7), .key("F8", .f8), .key("F9", .f9),
            .key("F10", .f10), .key("F11", .f11), .key("F12", .f12),
        ],
        [
            .key("`", .grave),
            .key("1", .one), .key("2", .two), .key("3", .three),
            .key("4", .four), .key("5", .five), .key("6", .six),
            .key("7", .seven), .key("8", .eight), .key("9", .nine),
            .key("0", .zero), .key("-", .minus), .key("=", .equal),
            .key("delete", .delete, units: 1.7),
        ],
        [
            .key("tab", .tab, units: 1.5),
            .key("Q", .q), .key("W", .w), .key("E", .e), .key("R", .r),
            .key("T", .t), .key("Y", .y), .key("U", .u), .key("I", .i),
            .key("O", .o), .key("P", .p),
            .key("[", .leftBracket), .key("]", .rightBracket),
            .key("\\", .backslash, units: 1.5),
        ],
        [
            .key("caps lock", .capsLock, units: 1.8),
            .key("A", .a), .key("S", .s), .key("D", .d), .key("F", .f),
            .key("G", .g), .key("H", .h), .key("J", .j), .key("K", .k),
            .key("L", .l), .key(";", .semicolon), .key("'", .quote),
            .key("return", .return, units: 2.1),
        ],
        [
            .modifier("shift", .shift, units: 2.3),
            .key("Z", .z), .key("X", .x), .key("C", .c), .key("V", .v),
            .key("B", .b), .key("N", .n), .key("M", .m),
            .key(",", .comma), .key(".", .period), .key("/", .slash),
            .modifier("shift", .shift, units: 2.3),
        ],
        [
            .modifier("fn", .function),
            .modifier("control", .control, units: 1.35),
            .modifier("option", .option, units: 1.25),
            .modifier("⌘", .command, units: 1.25),
            .key("space", .space, units: 5.5),
            .modifier("⌘", .command, units: 1.25),
            .modifier("option", .option, units: 1.25),
            .key("◀", .leftArrow),
            .key("▼", .downArrow),
            .key("▶", .rightArrow),
        ],
    ]
}

private struct KeyboardKeySpec {
    enum Kind {
        case key(RemoteKey)
        case modifier(ModifierKey)
    }

    let label: String
    let kind: Kind
    let units: CGFloat

    static func key(
        _ label: String,
        _ key: RemoteKey,
        units: CGFloat = 1
    ) -> KeyboardKeySpec {
        KeyboardKeySpec(label: label, kind: .key(key), units: units)
    }

    static func modifier(
        _ label: String,
        _ modifier: ModifierKey,
        units: CGFloat = 1
    ) -> KeyboardKeySpec {
        KeyboardKeySpec(label: label, kind: .modifier(modifier), units: units)
    }
}

private struct KeyboardRow: View {
    let keys: [KeyboardKeySpec]
    @Binding var modifiers: ModifierLatch
    let send: (RemoteKey) -> Void

    private let spacing: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(
                0,
                geometry.size.width - spacing * CGFloat(keys.count - 1)
            )
            let totalUnits = keys.reduce(CGFloat.zero) { $0 + $1.units }

            HStack(spacing: spacing) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Button {
                        activate(key)
                    } label: {
                        Text(key.label)
                            .font(.system(
                                size: key.label.count > 4 ? 10 : 13,
                                weight: .medium,
                                design: .rounded
                            ))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(foreground(for: key))
                    .frame(width: usableWidth * key.units / totalUnits)
                    .background(background(for: key))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.primary.opacity(0.12))
                    }
                    .accessibilityLabel(accessibilityLabel(for: key))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func activate(_ key: KeyboardKeySpec) {
        switch key.kind {
        case let .key(remoteKey):
            send(remoteKey)
        case let .modifier(modifier):
            modifiers.cycle(modifier)
        }
    }

    private func activation(for key: KeyboardKeySpec) -> ModifierActivation {
        guard case let .modifier(modifier) = key.kind else {
            return .off
        }
        return modifiers.activation(for: modifier)
    }

    private func background(for key: KeyboardKeySpec) -> Color {
        switch activation(for: key) {
        case .off: Color(uiColor: .secondarySystemBackground)
        case .oneShot: Color.blue
        case .sticky: Color.green
        }
    }

    private func foreground(for key: KeyboardKeySpec) -> Color {
        activation(for: key) == .off ? .primary : .white
    }

    private func accessibilityLabel(for key: KeyboardKeySpec) -> String {
        let state = activation(for: key)
        guard state != .off else {
            return key.label
        }
        return "\(key.label), \(state == .oneShot ? "next key" : "sticky")"
    }
}
