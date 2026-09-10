import Foundation

public let macOSRemoteProtocolVersion = 1

public struct ClientHello: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let deviceID: UUID
    public let displayName: String
    public let credential: String?

    public init(
        protocolVersion: Int = macOSRemoteProtocolVersion,
        deviceID: UUID,
        displayName: String,
        credential: String?
    ) {
        self.protocolVersion = protocolVersion
        self.deviceID = deviceID
        self.displayName = displayName
        self.credential = credential
    }
}

public struct PairingChallenge: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let expiresAt: Date

    public init(requestID: UUID, expiresAt: Date) {
        self.requestID = requestID
        self.expiresAt = expiresAt
    }
}

public struct PairingResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let code: String

    public init(requestID: UUID, code: String) {
        self.requestID = requestID
        self.code = code
    }
}

public struct ConnectionAccepted: Codable, Equatable, Sendable {
    public let sessionToken: String
    public let serverName: String
    public let remembered: Bool
    public let credential: String?

    public init(
        sessionToken: String,
        serverName: String,
        remembered: Bool,
        credential: String?
    ) {
        self.sessionToken = sessionToken
        self.serverName = serverName
        self.remembered = remembered
        self.credential = credential
    }
}

public struct SessionCommand: Codable, Equatable, Sendable {
    public let sessionToken: String
    public let sequence: UInt64
    public let command: RemoteCommand

    public init(sessionToken: String, sequence: UInt64, command: RemoteCommand) {
        self.sessionToken = sessionToken
        self.sequence = sequence
        self.command = command
    }
}

public enum WireMessage: Codable, Equatable, Sendable {
    case hello(ClientHello)
    case pairingChallenge(PairingChallenge)
    case pairingResponse(PairingResponse)
    case connectionAccepted(ConnectionAccepted)
    case connectionRejected(reason: String)
    case command(SessionCommand)
    case disconnect(sessionToken: String)
    case ping(UUID)
    case pong(UUID)
}

public enum WireCodec {
    public static let maximumMessageSize = 32_768

    public static func encode(_ message: WireMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
        guard data.count <= maximumMessageSize else {
            throw WireCodecError.messageTooLarge
        }
        return data
    }

    public static func decode(_ data: Data) throws -> WireMessage {
        guard data.count <= maximumMessageSize else {
            throw WireCodecError.messageTooLarge
        }
        return try JSONDecoder().decode(WireMessage.self, from: data)
    }
}

public enum WireCodecError: Error, Equatable {
    case messageTooLarge
}
