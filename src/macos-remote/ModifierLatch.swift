import Foundation

public enum ModifierActivation: String, Codable, Equatable, Sendable {
    case off
    case oneShot
    case sticky
}

public struct ModifierLatch: Equatable, Sendable {
    private var activations: [ModifierKey: ModifierActivation] = [:]

    public init() {}

    public func activation(for key: ModifierKey) -> ModifierActivation {
        activations[key, default: .off]
    }

    @discardableResult
    public mutating func cycle(_ key: ModifierKey) -> ModifierActivation {
        let next: ModifierActivation = switch activation(for: key) {
        case .off: .oneShot
        case .oneShot: .sticky
        case .sticky: .off
        }
        activations[key] = next
        return next
    }

    public var activeFlags: ModifierKeys {
        activations.reduce(into: ModifierKeys()) { flags, entry in
            if entry.value != .off {
                flags.insert(entry.key.flag)
            }
        }
    }

    public mutating func consumeOneShotModifiers() {
        for key in ModifierKey.allCases where activation(for: key) == .oneShot {
            activations[key] = .off
        }
    }

    public mutating func reset() {
        activations.removeAll()
    }
}
