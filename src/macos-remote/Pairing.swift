import Foundation

public struct PairingCode: Codable, Equatable, Sendable, CustomStringConvertible {
    public let value: String

    public init?(_ value: String) {
        guard value.count == 4, value.allSatisfy(\.isNumber) else {
            return nil
        }
        self.value = value
    }

    public static func generate() -> PairingCode {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    public static func generate<R: RandomNumberGenerator>(using generator: inout R) -> PairingCode {
        let number = Int.random(in: 0 ... 9_999, using: &generator)
        return PairingCode(String(format: "%04d", number))!
    }

    public var description: String {
        value
    }
}

public enum SecureToken {
    public static func generate(byteCount: Int = 32) -> String {
        precondition(byteCount > 0)
        var generator = SystemRandomNumberGenerator()
        return (0 ..< byteCount)
            .map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
