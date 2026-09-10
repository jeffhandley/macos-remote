@testable import MacOSRemote
import XCTest

final class InputModelTests: XCTestCase {
    func testModifierCyclesAndConsumesOnlyOneShotValues() {
        var latch = ModifierLatch()

        XCTAssertEqual(latch.cycle(.shift), .oneShot)
        XCTAssertEqual(latch.cycle(.command), .oneShot)
        XCTAssertEqual(latch.cycle(.command), .sticky)
        XCTAssertEqual(latch.activeFlags, [.shift, .command])

        latch.consumeOneShotModifiers()
        XCTAssertEqual(latch.activation(for: .shift), .off)
        XCTAssertEqual(latch.activation(for: .command), .sticky)
        XCTAssertEqual(latch.activeFlags, .command)

        XCTAssertEqual(latch.cycle(.command), .off)
        XCTAssertTrue(latch.activeFlags.isEmpty)
    }

    func testCommercialSkipSequenceMatchesRequiredTiming() {
        guard case let .keySequence(steps) = MLBControls.skipCommercials else {
            return XCTFail("Expected a key sequence")
        }

        XCTAssertEqual(steps.count, 14)
        XCTAssertEqual(steps.first?.stroke, KeyStroke(key: .escape))
        XCTAssertEqual(steps[1].stroke, KeyStroke(key: .rightArrow))
        XCTAssertEqual(steps[1].delayMilliseconds, 0)
        XCTAssertEqual(
            steps.filter { $0.stroke.key == .rightArrow }.count,
            12
        )
        XCTAssertTrue(
            steps[2 ... 12].allSatisfy {
                $0.stroke == KeyStroke(key: .rightArrow)
                    && $0.delayMilliseconds == 1_000
            }
        )
        XCTAssertEqual(steps.last?.stroke, KeyStroke(key: .f))
        XCTAssertEqual(steps.last?.delayMilliseconds, 3_000)
    }

    func testPairingCodeRequiresFourASCIIDigits() {
        XCTAssertEqual(PairingCode("0042")?.value, "0042")
        XCTAssertNil(PairingCode("123"))
        XCTAssertNil(PairingCode("12345"))
        XCTAssertNil(PairingCode("12a4"))
        XCTAssertNil(PairingCode("１２３４"))
    }

    func testGeneratedPairingCodesPreserveLeadingZeroWidth() {
        for _ in 0 ..< 100 {
            let code = PairingCode.generate().value
            XCTAssertEqual(code.utf8.count, 4)
            XCTAssertTrue(code.utf8.allSatisfy { (48 ... 57).contains($0) })
        }
    }

    func testSecureTokenHasRequestedEntropyWidth() {
        let token = SecureToken.generate(byteCount: 32)
        XCTAssertEqual(token.count, 64)
        XCTAssertTrue(token.allSatisfy(\.isHexDigit))
    }
}
