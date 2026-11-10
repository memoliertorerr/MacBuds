import Testing
@testable import BudsProtocol

@Suite struct CRCTests {
    @Test func standardCheckValue() {
        #expect(CRC16.xmodem(Array("123456789".utf8)) == 0x31C3)
    }

    @Test func capturedSpatialAudioFrame() {
        #expect(CRC16.xmodem(hex("C2 26 00 01")) == 0x7A8B)
    }
}

@Suite struct FrameTests {
    @Test func decodesCapturedExtendedStatus() throws {
        let frame = try Frame(decoding: Capture.extendedStatusFrame)
        #expect(frame.id == 0x61)
        #expect(frame.payload.count == 37)
        #expect(frame.payload.first == 0x0A)
        #expect(frame.headerFlags == 0x0800)
    }

    @Test(arguments: [
        ("FD 03 00 29 4B B5 DD", UInt8(0x29), ""),
        ("FD 04 00 78 00 F0 81 DD", UInt8(0x78), "00"),
        ("FD 04 00 78 01 D1 91 DD", UInt8(0x78), "01"),
        ("FD 04 00 78 02 B2 A1 DD", UInt8(0x78), "02"),
        ("FD 04 00 86 03 5D 81 DD", UInt8(0x86), "03"),
    ])
    func encodesDocumentedVectors(wire: String, id: UInt8, payload: String) throws {
        #expect(try Frame(id: id, payload: hex(payload)).encode() == hex(wire))
    }

    @Test func roundTrips() throws {
        let frame = Frame(id: 0x92, payload: [0x02, 0x04])
        #expect(try Frame(decoding: frame.encode()) == frame)
    }

    @Test func roundTripsLongestPayload() throws {
        let frame = Frame(id: 0x40, payload: Array(repeating: 0xFD, count: Frame.maxPayload))
        #expect(try Frame(decoding: frame.encode()) == frame)
    }

    @Test func rejectsOversizedPayload() {
        let frame = Frame(id: 0x40, payload: Array(repeating: 0, count: Frame.maxPayload + 1))
        #expect(throws: Frame.EncodeError.payloadTooLong(Frame.maxPayload + 1)) { try frame.encode() }
    }

    @Test func rejectsBadCRC() {
        var bytes = Capture.extendedStatusFrame
        bytes[10] ^= 0x01
        #expect(throws: Frame.DecodeError.self) { try Frame(decoding: bytes) }
        #expect(throws: Frame.DecodeError.crcMismatch(expected: 0x7A8B, actual: 0x7A8C)) {
            try Frame(decoding: hex("FD 06 54 C2 26 00 01 8C 7A DD"))
        }
    }

    @Test func rejectsBadMarkersAndLength() {
        #expect(throws: Frame.DecodeError.badStartMarker(0xFE)) {
            try Frame(decoding: hex("FE 03 00 29 4B B5 DD"))
        }
        #expect(throws: Frame.DecodeError.badEndMarker(0xEE)) {
            try Frame(decoding: hex("FD 03 00 29 4B B5 EE"))
        }
        #expect(throws: Frame.DecodeError.lengthMismatch(declared: 4, actual: 3)) {
            try Frame(decoding: hex("FD 04 00 29 4B B5 DD"))
        }
        #expect(throws: Frame.DecodeError.tooShort) { try Frame(decoding: [0xFD, 0x03]) }
    }
}

@Suite struct FrameStreamDecoderTests {
    @Test func decodesWholeCaptureAsDelivered() {
        var decoder = FrameStreamDecoder()
        let frames = Capture.chunks.flatMap { decoder.push($0) }
        #expect(frames.map(\.id) == Capture.frameIDs)
        #expect(decoder.discardedByteCount == 0)
    }

    @Test func decodesCaptureFedOneByteAtATime() {
        var decoder = FrameStreamDecoder()
        let frames = Capture.chunks.joined().flatMap { decoder.push([$0]) }
        #expect(frames.map(\.id) == Capture.frameIDs)
    }

    @Test func reassemblesFrameSplitAcrossThreeChunks() {
        var decoder = FrameStreamDecoder()
        let bytes = Capture.extendedStatusFrame
        #expect(decoder.push(bytes[0..<2]).isEmpty)
        #expect(decoder.push(bytes[2..<30]).isEmpty)
        let frames = decoder.push(bytes[30...])
        #expect(frames.map(\.id) == [0x61])
    }

    /// The first captured frame ends "80 DD DD": the CRC high byte equals the end marker.
    @Test func doesNotStopAtEndMarkerValueInsideCRC() {
        var decoder = FrameStreamDecoder()
        #expect(decoder.push(Capture.chunks[0]).map(\.id) == [0x61, 0xC2])
    }

    @Test func resynchronisesAfterGarbageAndCorruption() {
        var decoder = FrameStreamDecoder()
        var corrupt = hex(Capture.callbacks[2])
        corrupt[5] ^= 0xFF
        let stream = [0x00, 0xDD, 0x13] + corrupt + hex(Capture.callbacks[3])
        #expect(decoder.push(stream).map(\.id) == [0x27])
        #expect(decoder.discardedByteCount == 3 + corrupt.count)
    }

    @Test func survivesStartMarkerWithImpossibleLength() {
        var decoder = FrameStreamDecoder()
        let frames = decoder.push([0xFD, 0x00, 0x00, 0xFD, 0x01, 0x00] + hex(Capture.callbacks[2]))
        #expect(frames.map(\.id) == [0xC2])
    }

    /// A stray FD can announce a long frame that never comes. The decoder waits for that
    /// many bytes, then rejects it and still recovers every real frame behind it.
    @Test func recoversFramesBehindFalseStart() {
        var decoder = FrameStreamDecoder()
        var frames = decoder.push([0xFD, 0x02])
        for chunk in Capture.chunks { frames += decoder.push(chunk) }
        #expect(frames.map(\.id) == Capture.frameIDs)
    }

    @Test func noFramesFromPureNoise() {
        var decoder = FrameStreamDecoder()
        #expect(decoder.push(Array(repeating: 0x55, count: 4096)).isEmpty)
        #expect(decoder.discardedByteCount == 4096)
    }
}
