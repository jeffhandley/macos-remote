import Foundation
@testable import MacOSRemote
import XCTest

final class BLEFrameCodecTests: XCTestCase {
    func testRoundTripsAcrossLegacyTwentyByteFramesOutOfOrder() throws {
        let payload = Data((0 ..< 251).map { UInt8($0 % 256) })
        let frames = try BLEFrameCodec.frames(
            for: payload,
            maximumFrameSize: 20,
            messageID: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        )
        XCTAssertGreaterThan(frames.count, 1)
        XCTAssertTrue(frames.allSatisfy { $0.count <= 20 })

        var assembler = BLEFrameAssembler()
        var completed: Data?
        for frame in frames.reversed() {
            if let data = try assembler.accept(frame) {
                completed = data
            }
        }
        XCTAssertEqual(completed, payload)
    }

    func testAcceptsDataSliceWithNonzeroStartIndex() throws {
        let expected = Data("slice payload".utf8)
        let storage = Data([0xff]) + expected + Data([0xee])
        let slice = storage[1 ..< storage.index(before: storage.endIndex)]

        let frames = try BLEFrameCodec.frames(
            for: slice,
            maximumFrameSize: 20
        )
        var assembler = BLEFrameAssembler()
        var completed: Data?
        for frame in frames {
            completed = try assembler.accept(frame) ?? completed
        }
        XCTAssertEqual(completed, expected)
    }

    func testRejectsConflictingDuplicateFrame() throws {
        let frames = try BLEFrameCodec.frames(
            for: Data(repeating: 7, count: 30),
            maximumFrameSize: 20
        )
        var assembler = BLEFrameAssembler()
        XCTAssertNil(try assembler.accept(frames[0]))

        var conflicting = frames[0]
        conflicting[conflicting.index(before: conflicting.endIndex)] ^= 0xff
        XCTAssertThrowsError(try assembler.accept(conflicting)) { error in
            XCTAssertEqual(error as? BLEFrameError, .duplicateFrame)
        }
    }

    func testCapsConcurrentAssemblies() throws {
        var assembler = BLEFrameAssembler(maximumAssemblies: 1)
        let first = try BLEFrameCodec.frames(
            for: Data(repeating: 1, count: 30),
            maximumFrameSize: 20,
            messageID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let second = try BLEFrameCodec.frames(
            for: Data(repeating: 2, count: 30),
            maximumFrameSize: 20,
            messageID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )

        XCTAssertNil(try assembler.accept(first[0]))
        XCTAssertThrowsError(try assembler.accept(second[0])) { error in
            XCTAssertEqual(error as? BLEFrameError, .tooManyAssemblies)
        }
    }

    func testRejectsFrameSizeWithoutPayloadCapacity() {
        XCTAssertThrowsError(
            try BLEFrameCodec.frames(for: Data(), maximumFrameSize: BLEFrameCodec.headerSize)
        ) { error in
            XCTAssertEqual(error as? BLEFrameError, .frameTooSmall)
        }
    }
}
