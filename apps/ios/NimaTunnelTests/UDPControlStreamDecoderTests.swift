import XCTest

final class UDPControlStreamDecoderTests: XCTestCase {
    private let maxFrame = 9000

    func testResponseFrameCodecBuildsPlainResponseFrame() throws {
        let header: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35]
        let response = Data([0xaa, 0xbb, 0xcc])

        let framed = try XCTUnwrap(
            UDPControlFrameCodec.buildResponseFrame(
                mode: .plain,
                headerBytes: header,
                responsePayload: response,
                maxFrameSize: maxFrame
            )
        )

        XCTAssertEqual([UInt8](framed), [0x00, 0x03] + header + [0xaa, 0xbb, 0xcc])
    }

    func testResponseFrameCodecBuildsControlPrefixedResponseFrame() throws {
        let header: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x04, 0x04, 0x00, 0x35]
        let response = Data([0xde, 0xad])

        let framed = try XCTUnwrap(
            UDPControlFrameCodec.buildResponseFrame(
                mode: .controlPrefixed,
                headerBytes: header,
                responsePayload: response,
                maxFrameSize: maxFrame
            )
        )

        XCTAssertEqual([UInt8](framed), [0x00, 0x01, 0x00, 0x02] + header + [0xde, 0xad])
    }

    func testResponseFrameCodecBuildsRawPayloadResponseWithoutLengthPrefix() throws {
        let header: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x04, 0x04, 0x00, 0x35]
        let response = Data([0xde, 0xad])

        let framed = try XCTUnwrap(
            UDPControlFrameCodec.buildResponseFrame(
                mode: .rawPayload,
                headerBytes: header,
                responsePayload: response,
                maxFrameSize: maxFrame
            )
        )

        XCTAssertEqual([UInt8](framed), header + [0xde, 0xad])
    }

    func testSOCKSRequestParserPreservesFwdUDPTailBytes() throws {
        let udpPayload = rawUDPControlPayload(port: 53)
        let request = Data([0x05, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00] + udpPayload)

        let parsed = try XCTUnwrap(SOCKSProxyServer.parseSOCKSRequestMetadata(from: request))

        XCTAssertEqual(parsed.command, 0x05)
        XCTAssertEqual(parsed.host, "0.0.0.0")
        XCTAssertEqual(parsed.port, 0)
        XCTAssertEqual(parsed.headerEndOffset, 10)
        XCTAssertEqual([UInt8](parsed.requestTail), udpPayload)
    }

    func testSOCKSRequestParserProducesEmptyTailForExactFwdUDPRequest() throws {
        let request = Data([0x05, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        let parsed = try XCTUnwrap(SOCKSProxyServer.parseSOCKSRequestMetadata(from: request))

        XCTAssertEqual(parsed.headerEndOffset, request.count)
        XCTAssertTrue(parsed.requestTail.isEmpty)
    }

    func testFastLaneDecodesFramedDNSTailAsSingleRequest() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let dnsPayload = Array(repeating: UInt8(0x11), count: 12)
        let payload = rawUDPControlPayload(port: 53, dnsPayload: dnsPayload)
        let data = framedPlainData(payload: payload, datagramPayloadLength: dnsPayload.count)

        switch SOCKSProxyServer.decodeDNSFastLaneInput(data: data, decoder: decoder) {
        case .frame(let frame, let trailingFrameCount):
            XCTAssertEqual(frame.mode, .plain)
            XCTAssertEqual(frame.payload, payload)
            XCTAssertEqual(trailingFrameCount, 0)
        default:
            XCTFail("Expected one framed DNS fast-lane frame")
        }
    }

    func testFastLaneAcceptsRawDNSPayloadWhenModeIsUnlocked() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let payload = rawUDPControlPayload(port: 53)

        XCTAssertTrue(SOCKSProxyServer.isParseableRawUDPControlPayload(Data(payload)))
        switch SOCKSProxyServer.decodeDNSFastLaneInput(data: Data(payload), decoder: decoder) {
        case .frame(let frame, let trailingFrameCount):
            XCTAssertEqual(frame.mode, .rawPayload)
            XCTAssertEqual(frame.payload, payload)
            XCTAssertEqual(trailingFrameCount, 0)
        default:
            XCTFail("Expected raw DNS fast-lane frame")
        }
    }

    func testFastLaneAcceptsSOCKS5UDPFallbackPayloadWhenModeIsUnlocked() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let payload = socks5UDPControlPayload(port: 53)

        XCTAssertTrue(SOCKSProxyServer.isParseableRawUDPControlPayload(Data(payload)))
        switch SOCKSProxyServer.decodeDNSFastLaneInput(data: Data(payload), decoder: decoder) {
        case .frame(let frame, let trailingFrameCount):
            XCTAssertEqual(frame.mode, .rawPayload)
            XCTAssertEqual(frame.payload, payload)
            XCTAssertEqual(trailingFrameCount, 0)
        default:
            XCTFail("Expected SOCKS5 UDP fallback payload as raw DNS fast-lane frame")
        }
    }

    func testFastLaneMalformedFrameFailsWithoutDecoderRecovery() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let payload = rawUDPControlPayload(port: 53)
        let malformed = Data([0x63, 0x08] + payload)

        switch SOCKSProxyServer.decodeDNSFastLaneInput(data: malformed, decoder: decoder) {
        case .failed(let error):
            XCTAssertEqual(error, .badLength)
        default:
            XCTFail("Expected malformed fast-lane frame to fail")
        }
        XCTAssertEqual(decoder.drainDiagnostics().resyncAttempts, 0)
    }

    func testPlainSingleFrame() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let dnsPayload: [UInt8] = [0xaa, 0xbb]
        let payload = rawUDPControlPayload(port: 53, dnsPayload: dnsPayload)
        let data = framedPlainData(payload: payload, datagramPayloadLength: dnsPayload.count)

        let frames = tryUnwrapFrames(decoder.append(data))
        XCTAssertEqual(frames.count, 1)
        guard frames.count == 1 else { return }
        XCTAssertEqual(frames[0].mode, .plain)
        XCTAssertEqual(frames[0].payload, payload)
    }

    func testPlainBackToBackFrames() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let d1: [UInt8] = [0x11, 0x22]
        let d2: [UInt8] = [0xaa, 0xbb]
        let p1: [UInt8] = [0x0a, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x35] + d1
        let p2: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x04, 0x04, 0x00, 0x35] + d2
        let stream = framedPlainData(payload: p1, datagramPayloadLength: d1.count) +
            framedPlainData(payload: p2, datagramPayloadLength: d2.count)

        let frames = tryUnwrapFrames(decoder.append(stream))
        XCTAssertEqual(frames.map(\.mode), [.plain, .plain])
        guard frames.count == 2 else { return }
        XCTAssertEqual(frames[0].payload, p1)
        XCTAssertEqual(frames[1].payload, p2)
    }

    func testControlPrefixedBackToBackFrames() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let d1: [UInt8] = [0x11]
        let d2: [UInt8] = [0xbb, 0xcc]
        let p1: [UInt8] = [0x0a, 0x01, 0x7f, 0x00, 0x00, 0x01, 0x00, 0x35] + d1
        let p2: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35] + d2
        let stream = framedControlPrefixedData(payload: p1, datagramPayloadLength: d1.count) +
            framedControlPrefixedData(payload: p2, datagramPayloadLength: d2.count)

        let frames = tryUnwrapFrames(decoder.append(stream))
        XCTAssertEqual(frames.map(\.mode), [.controlPrefixed, .controlPrefixed])
        XCTAssertEqual(frames[0].payload, p1)
        XCTAssertEqual(frames[1].payload, p2)
    }

    func testChunkedOneByteReadsAcrossBoundaries() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let dnsPayload: [UInt8] = [0xde, 0xad, 0xbe, 0xef]
        let payload = rawUDPControlPayload(port: 53, dnsPayload: dnsPayload)
        let bytes = [UInt8](framedPlainData(payload: payload, datagramPayloadLength: dnsPayload.count))

        var allFrames: [UDPControlFrame] = []
        for b in bytes {
            let frames = tryUnwrapFrames(decoder.append(Data([b])))
            allFrames.append(contentsOf: frames)
        }

        XCTAssertEqual(allFrames.count, 1)
        XCTAssertEqual(allFrames[0].payload, payload)
        XCTAssertEqual(allFrames[0].mode, .plain)
    }

    func testCapturedGoogleDNSPayloadLengthFrameDecodesWholeFrame() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let data = hexData("00200a0108080808003514c4010000010000000000000377777706676f6f676c6503636f6d0000010001")

        let result = decoder.append(data)

        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.frames.count, 1)
        assertDNSFrame(result.frames[0], header: [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35], dnsPayloadLength: 32)
        XCTAssertEqual(decoder.diagnosticSnapshot().bufferedBytes, 0)
        XCTAssertEqual(decoder.drainDiagnostics().resyncAttempts, 0)
    }

    func testCapturedBackToBackGoogleFramesDecodeWithoutRecovery() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let first = hexData("00200a0108080808003514c4010000010000000000000377777706676f6f676c6503636f6d0000010001")
        let second = hexData("00200a0101010101003514c4010000010000000000000377777706676f6f676c6503636f6d0000010001")

        let result = decoder.append(first + second)

        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.frames.count, 2)
        assertDNSFrame(result.frames[0], header: [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35], dnsPayloadLength: 32)
        assertDNSFrame(result.frames[1], header: [0x0a, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x35], dnsPayloadLength: 32)
        XCTAssertEqual(decoder.diagnosticSnapshot().bufferedBytes, 0)
        XCTAssertEqual(decoder.drainDiagnostics().resyncAttempts, 0)
    }

    func testCapturedMobileMapsPayloadLengthFrameDecodesWholeFrame() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let data = hexData("002b0a01010101010035b12a010000010000000000000a6d6f62696c656d6170730a676f6f676c656170697303636f6d0000010001")

        let result = decoder.append(data)

        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.frames.count, 1)
        assertDNSFrame(result.frames[0], header: [0x0a, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x35], dnsPayloadLength: 43)
        XCTAssertEqual(decoder.diagnosticSnapshot().bufferedBytes, 0)
        XCTAssertEqual(decoder.drainDiagnostics().resyncAttempts, 0)
    }

    func testCapturedGoogleFrameCanArriveOneByteAtATime() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let bytes = [UInt8](hexData("00200a0108080808003514c4010000010000000000000377777706676f6f676c6503636f6d0000010001"))

        var allFrames: [UDPControlFrame] = []
        for (index, byte) in bytes.enumerated() {
            let result = decoder.append(Data([byte]))
            if index < bytes.count - 1 {
                XCTAssertTrue(result.frames.isEmpty)
                XCTAssertEqual(result.status, .needMoreBytes)
            }
            allFrames.append(contentsOf: result.frames)
        }

        XCTAssertEqual(allFrames.count, 1)
        assertDNSFrame(allFrames[0], header: [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35], dnsPayloadLength: 32)
        XCTAssertEqual(decoder.diagnosticSnapshot().bufferedBytes, 0)
    }

    func testNeedMoreBytesStatusForPartialFrame() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame)
        let partial = decoder.append(Data([0x00]))
        XCTAssertEqual(partial.frames.count, 0)
        XCTAssertEqual(partial.status, .needMoreBytes)
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
        let controlPayload = rawUDPControlPayload(port: 53, dnsPayload: [0xaa, 0xbb])
        let controlFrame = framedControlPrefixedData(payload: controlPayload, datagramPayloadLength: 2)
        _ = tryUnwrapFrames(decoder.append(controlFrame))

        let plainPayload: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x04, 0x04, 0x00, 0x35, 0xbb, 0xcc]
        let plainFrame = framedPlainData(payload: plainPayload, datagramPayloadLength: 2)
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
        let dnsPayload: [UInt8] = [0x12, 0x34]
        let firstPayload = rawUDPControlPayload(port: 53, dnsPayload: dnsPayload)
        let validFrame = framedPlainData(payload: firstPayload, datagramPayloadLength: dnsPayload.count)

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
        let dnsPayload: [UInt8] = [0xaa, 0xbb]
        let payload = rawUDPControlPayload(port: 53, dnsPayload: dnsPayload)
        // invalid high byte followed by valid short frame length in low byte
        let stream = Data([0x63, UInt8(dnsPayload.count)] + payload)
        let result = decoder.append(stream)
        guard case .recovered(let err) = result.status else {
            return XCTFail("Expected recovered result")
        }
        XCTAssertEqual(err, .badLength)
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertEqual(result.frames[0].payload, payload)
    }

    func testFastLaneDecoderDoesNotAttemptRecovery() {
        let decoder = UDPControlStreamDecoder(maxFrameSize: maxFrame, maxResyncAttempts: 0)
        let payload: [UInt8] = [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, 0x00, 0x35]
        let stream = Data([0x63, 0x08] + payload)

        let result = decoder.append(stream)
        guard case .failed(let err) = result.status else {
            return XCTFail("Expected fast-lane hard failure without recovery")
        }
        XCTAssertEqual(err, .badLength)
        XCTAssertEqual(result.frames.count, 0)
        XCTAssertEqual(decoder.drainDiagnostics().resyncAttempts, 0)
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
        case .ok, .recovered, .needMoreBytes:
            return result.frames
        case .failed(let err):
            XCTFail("Unexpected decoder failure: \(err)", file: file, line: line)
            return []
        }
    }

    private func rawUDPControlPayload(port: UInt16) -> [UInt8] {
        let dnsPayload = Array(repeating: UInt8(0x11), count: 12)
        return rawUDPControlPayload(port: port, dnsPayload: dnsPayload)
    }

    private func rawUDPControlPayload(port: UInt16, dnsPayload: [UInt8]) -> [UInt8] {
        [0x0a, 0x01, 0x08, 0x08, 0x08, 0x08, UInt8(port >> 8), UInt8(port & 0xff)] + dnsPayload
    }

    private func socks5UDPControlPayload(port: UInt16) -> [UInt8] {
        let dnsPayload = Array(repeating: UInt8(0x22), count: 12)
        return [0x00, 0x00, 0x00, 0x01, 0x08, 0x08, 0x04, 0x04, UInt8(port >> 8), UInt8(port & 0xff)] + dnsPayload
    }

    private func framedPlainData(payload: [UInt8], datagramPayloadLength: Int) -> Data {
        Data(lengthPrefix(datagramPayloadLength) + payload)
    }

    private func framedControlPrefixedData(payload: [UInt8], datagramPayloadLength: Int) -> Data {
        Data([0x00, 0x01] + lengthPrefix(datagramPayloadLength) + payload)
    }

    private func lengthPrefix(_ length: Int) -> [UInt8] {
        [UInt8(length >> 8), UInt8(length & 0xff)]
    }

    private func assertDNSFrame(
        _ frame: UDPControlFrame,
        header: [UInt8],
        dnsPayloadLength: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frame.mode, .plain, file: file, line: line)
        XCTAssertEqual(Array(frame.payload.prefix(header.count)), header, file: file, line: line)
        XCTAssertEqual(frame.payload.count, header.count + dnsPayloadLength, file: file, line: line)
        XCTAssertEqual(frame.payload.dropFirst(header.count).count, dnsPayloadLength, file: file, line: line)
    }

    private func hexData(_ hex: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        XCTAssertEqual(hex.count % 2, 0, "Hex strings must have an even number of characters", file: file, line: line)
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                XCTFail("Invalid hex byte", file: file, line: line)
                return Data()
            }
            bytes.append(byte)
            index = nextIndex
        }
        return Data(bytes)
    }
}
