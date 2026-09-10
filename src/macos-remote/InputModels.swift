import Foundation

public struct ModifierKeys: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = ModifierKeys(rawValue: 1 << 0)
    public static let control = ModifierKeys(rawValue: 1 << 1)
    public static let option = ModifierKeys(rawValue: 1 << 2)
    public static let command = ModifierKeys(rawValue: 1 << 3)
    public static let function = ModifierKeys(rawValue: 1 << 4)
}

public enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case shift
    case control
    case option
    case command
    case function

    public var flag: ModifierKeys {
        switch self {
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        case .function: .function
        }
    }
}

public enum RemoteKey: String, Codable, CaseIterable, Sendable {
    case escape
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case grave
    case one, two, three, four, five, six, seven, eight, nine, zero
    case minus, equal, delete
    case tab
    case q, w, e, r, t, y, u, i, o, p
    case leftBracket, rightBracket, backslash
    case capsLock
    case a, s, d, f, g, h, j, k, l
    case semicolon, quote, `return`
    case z, x, c, v, b, n, m
    case comma, period, slash
    case space
    case leftArrow, downArrow, upArrow, rightArrow
    case home, end, pageUp, pageDown
    case forwardDelete
}

public struct KeyStroke: Codable, Equatable, Sendable {
    public let key: RemoteKey
    public let modifiers: ModifierKeys

    public init(key: RemoteKey, modifiers: ModifierKeys = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum PointerButton: String, Codable, Sendable {
    case primary
    case secondary
}

public enum SwipeDirection: String, Codable, Sendable {
    case up
    case down
    case left
    case right
}

public enum PointerAction: Codable, Equatable, Sendable {
    case move(deltaX: Double, deltaY: Double)
    case scroll(deltaX: Double, deltaY: Double)
    case click(button: PointerButton, count: Int)
    case drag(deltaX: Double, deltaY: Double)
    case endDrag
    case magnify(scale: Double)
    case threeFingerSwipe(SwipeDirection)
}

public struct KeySequenceStep: Codable, Equatable, Sendable {
    public let delayMilliseconds: UInt32
    public let stroke: KeyStroke

    public init(delayMilliseconds: UInt32 = 0, stroke: KeyStroke) {
        self.delayMilliseconds = delayMilliseconds
        self.stroke = stroke
    }
}

public enum RemoteCommand: Codable, Equatable, Sendable {
    case key(KeyStroke)
    case text(String)
    case pointer(PointerAction)
    case keySequence([KeySequenceStep])
}
