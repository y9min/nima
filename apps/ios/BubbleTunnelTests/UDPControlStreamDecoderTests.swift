import XCTest
@testable import BubbleTunnel

final class UDPControlStreamDecoderTests: XCTestCase {
    private let maxFrame = 9000

    func testPlainSingleFrame() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let payload: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35]
        let data = Data([0x00, UInt8(payload.count)] + payload)

        let frames = tryUnwrapFrames(decoder.append(data))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].mode, .plain)
        XCTAssertEqual(frames[0].payload, payload)
    }

    func testPlainBackToBackFrames() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let p1: [UInt8] = [0x0a, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x35]
        let p2: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x04, 0x04, 0x00, 0x35, 0xaa]
        let stream = Data([0x00, UInt8(p1.count)] + p1 + [0x00, UInt8(p2.count)] + p2)

        let frames = tryUnwrapFrames(decoder.append(stream))
        XCTAssertEqual(frames.map(\.mode), [.plain, .plain])
        XCTAssertEqual(frames[0].payload, p1)
        XCTAssertEqual(frames[1].payload, p2)
    }

    func testControlPrefixedBackToBackFrames() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let p1: [UInt8] = [0x0a, 0x01, 0x7f, 0x00, 0x00, 0x01, 0x00, 0x35]
        let p2: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35, 0xbb, 0xcc]
        let stream = Data(
            [0x00, 0x01, 0x00, UInt8(p1.count)] + p1 +
            [0x00, 0x01, 0x00, UInt8(p2.count)] + p2
        )

        let frames = tryUnwrapFrames(decoder.append(stream))
        XCTAssertEqual(frames.map(\.mode), [.controlPrefixed, .controlPrefixed])
        XCTAssertEqual(frames[0].payload, p1)
        XCTAssertEqual(frames[1].payload, p2)
    }

    func testChunkedOneByteReadsAcrossBoundaries() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let payload: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35, 0xde, 0xad, 0xbe, 0xef]
        let bytes = [0x00, UInt8(payload.count)] + payload

        var allFrames: [UDPControlFrame] = []
        for b in bytes {
            let frames = tryUnwrapFrames(decoder.append(Data([b])))
            allFrames.append(contentsOf: frames)
        }

        XCTAssertEqual(allFrames.count, 1)
        XCTAssertEqual(allFrames[0].payload, payload)
        XCTAssertEqual(allFrames[0].mode, .plain)
    }

    func testInvalidLengthClosesOnlyStream() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let result = decoder.append(Data([0xff, 0xff]))
        guard case .failed(let err) = result.status else {
            return XCTFail("Expected hard badLength error")
        }
        XCTAssertEqual(err, .badLength)
    }

    func testModeMismatchAfterControlLockFails() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let controlFrame = Data([0x00, 0x01, 0x00, 0x08, 0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35])
        _ = tryUnwrapFrames(decoder.append(controlFrame))

        let plainFrame = Data([0x00, 0x08, 0x0a, 0x01, 0x08, 0x08, 0x04, 0x04, 0x00, 0x35])
        let result = decoder.append(plainFrame)
        guard case .failed(let err) = result.status else {
            return XCTFail("Expected hard badPrefix error")
        }
        XCTAssertEqual(err, .badPrefix)
    }

    func testReplay636fPatternNoResyncSkip() {
        // Captured style: valid frame then bytes that start with 'co' (0x636f),
        // previously mis-read as a new frame length and caused parser churn.
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let firstPayload: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35, 0x12, 0x34]
        let validFrame = Data([0x00, UInt8(firstPayload.count)] + firstPayload)

        let first = tryUnwrapFrames(decoder.append(validFrame))
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].payload, firstPayload)

        let badTail = Data([0x63, 0x6f, 0x6d, 0x00])
        let second = decoder.append(badTail)
        guard case .recovered(let err) = second.status else {
            return XCTFail("Expected recovered badLength for 0x636f")
        }
        XCTAssertEqual(err, .badLength)
    }

    func testResyncCanRecoverThenParseNextFrame() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let payload: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35]
        // invalid high byte followed by valid short frame length in low byte
        let stream = Data([0x63, 0x08] + payload)
        let result = decoder.append(stream)
        guard case .recovered(let err) = result.status else {
            return XCTFail("Expected recovered result")
        }
        XCTAssertEqual(err, .badLength)
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.frames[0].payload, payload)
    }

    func testHardFailureAfterResyncBudgetExhausted() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 1)
        // two impossible prefixes without valid frame in-between
        let result = decoder.append(Data([0x63, 0x6f, 0x70, 0x71]))
        guard case .failed(let err) = result.status else {
            return XCTFail("Expected hard failure after resync budget")
        }
        XCTAssertEqual(err, .badLength)
    }

    private func tryUnwrapFrames(_ result: UDPControlAppendResult, file: StaticString = #filePath, line: UInt = #line) -> [UDPControlFrame] {
        switch result.status {
        case .ok, .recovered:
            return result.frames
        case .failed(let err):
            XCTFail("Unexpected decoder failure: \(err)", file: file, line: line)
            return []
        }
    }
}
