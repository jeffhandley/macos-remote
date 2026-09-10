import Foundation
@testable import MacOSRemote
import XCTest

final class WireProtocolTests: XCTestCase {
    func testAllWireMessagesRoundTrip() throws {
        let deviceID = UUID(uuidString: "b3b0e78f-afb6-4cff-98e2-c25fbcef8179")!
        let requestID = UUID(uuidString: "c22f783f-5300-464e-b5fb-fb9c172a2573")!
        let messages: [WireMessage] = [
            .hello(ClientHello(
                deviceID: deviceID,
                displayName: "Test iPhone",
                credential: "credential"
            )),
            .pairingChallenge(PairingChallenge(
                requestID: requestID,
                expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
            )),
            .pairingResponse(PairingResponse(
                requestID: requestID,
                code: "0427"
            )),
            .connectionAccepted(ConnectionAccepted(
                sessionToken: "session",
                serverName: "Test Mac",
                remembered: true,
                credential: "new credential"
            )),
            .connectionRejected(reason: "No"),
            .command(SessionCommand(
                sessionToken: "session",
                sequence: 9,
                command: .pointer(.move(deltaX: 1.5, deltaY: -2.5))
            )),
            .disconnect(sessionToken: "session"),
            .ping(requestID),
            .pong(requestID),
        ]

        for message in messages {
            XCTAssertEqual(try WireCodec.decode(WireCodec.encode(message)), message)
        }
    }

    func testEndToEndMessageFraming() throws {
        let message = WireMessage.command(SessionCommand(
            sessionToken: "test-session",
            sequence: 42,
            command: .text("Swipe typing ⚾️")
        ))
        let encoded = try WireCodec.encode(message)
        let frames = try BLEFrameCodec.frames(
            for: encoded,
            maximumFrameSize: 37
        )

        var assembler = BLEFrameAssembler()
        var decoded: WireMessage?
        for frame in frames {
            if let payload = try assembler.accept(frame) {
                decoded = try WireCodec.decode(payload)
            }
        }
        XCTAssertEqual(decoded, message)
    }

    func testWireCodecRejectsOversizedPayload() {
        let data = Data(repeating: 0, count: WireCodec.maximumMessageSize + 1)
        XCTAssertThrowsError(try WireCodec.decode(data)) { error in
            XCTAssertEqual(error as? WireCodecError, .messageTooLarge)
        }
    }
}
