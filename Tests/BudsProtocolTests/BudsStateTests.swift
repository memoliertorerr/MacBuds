import Testing
@testable import BudsProtocol

@Suite struct BudsStateTests {
    static let payload = Array(Capture.extendedStatusFrame[4..<41])

    @Test func decodesCapturedExtendedStatus() throws {
        let s = try BudsState(extendedStatus: Self.payload)
        #expect(s.revision == 10)
        #expect(s.batteryLeft == 55)
        #expect(s.batteryRight == 96)
        #expect(s.batteryCase == 0)
        #expect(!s.caseBatteryKnown)
        #expect(s.coupled)
        #expect(s.primary == .right)
        #expect(s.placementLeft == .wearing)
        #expect(s.placementRight == .wearing)
        #expect(s.equalizer.description == "dynamic")
        #expect(s.touch.enabled)
        #expect(s.touch.singleTap && s.touch.doubleTap && s.touch.tripleTap && s.touch.touchAndHold)
        #expect(s.touch.doubleTapInCall && s.touch.touchAndHoldInCall)
        #expect(s.holdActionLeft.description == "spotify")
        #expect(s.holdActionRight.description == "noise-control")
        #expect(s.noiseControl == .ambient)
        #expect(s.ambientLevel == 1)
        #expect(s.noiseCycleLeft == NoiseCycle(anc: true, ambient: true, off: false))
        #expect(s.noiseCycleRight == NoiseCycle(anc: true, ambient: true, off: false))
        #expect(s.seamlessConnection)
        #expect(s.balance == 16)
        #expect(!s.extraHighAmbient)
        #expect(s.noiseControlWithOneEarbud == false)
        #expect(s.customAmbient == CustomAmbient(enabled: true, leftLevel: 1, rightLevel: 1, tone: 2))
        #expect(s.doubleTapEdgeVolume == false)
        #expect(s.ambientDuringCalls == false)
        #expect(s.inEarDetectionForCalls == true)
        #expect(!s.chargingLeft && !s.chargingRight && !s.chargingCase)
    }

    @Test func toleratesTrailingBytesFromNewerFirmware() throws {
        let s = try BudsState(extendedStatus: Self.payload + [0xAA, 0xBB, 0xCC])
        #expect(s == (try BudsState(extendedStatus: Self.payload)))
    }

    @Test func olderRevisionLeavesLaterFieldsUnset() throws {
        var p = Array(Self.payload.prefix(29))
        p[0] = 3
        let s = try BudsState(extendedStatus: p)
        #expect(s.noiseControlWithOneEarbud == false)
        #expect(s.customAmbient == nil)
        #expect(s.ambientDuringCalls == nil)
        #expect(s.inEarDetectionForCalls == nil)
    }

    @Test func revisionGateWinsOverPayloadLength() throws {
        var p = Self.payload
        p[0] = 5
        let s = try BudsState(extendedStatus: p)
        #expect(s.customAmbient != nil)
        #expect(s.ambientDuringCalls == nil)
    }

    @Test func rejectsTruncatedPayload() {
        #expect(throws: BudsState.DecodeError.truncated(needed: 27, got: 10)) {
            try BudsState(extendedStatus: Array(Self.payload.prefix(10)))
        }
        #expect(throws: BudsState.DecodeError.self) { try BudsState(extendedStatus: []) }
    }

    @Test func unknownEnumByteIsCarriedNotRejected() throws {
        var p = Self.payload
        p[9] = 0x07
        p[12] = 0x03
        let s = try BudsState(extendedStatus: p)
        #expect(s.equalizer.description == "unknown(0x07)")
        #expect(s.noiseControl.name == nil)
    }

    @Test func appliesStatusUpdate() throws {
        var s = try BudsState(extendedStatus: Self.payload)
        // revision 10, L 54 %, R 95 %, coupled, left primary, left in open case / right
        // wearing, case 80 %, left + case charging
        try s.apply(statusUpdate: [0x0A, 0x36, 0x5F, 0x01, 0x01, 0x31, 0x50, 0x11])
        #expect(s.batteryLeft == 54)
        #expect(s.batteryRight == 95)
        #expect(s.primary == .left)
        #expect(s.placementLeft.description == "in-open-case")
        #expect(s.placementRight == .wearing)
        #expect(s.batteryCase == 80)
        #expect(s.caseBatteryKnown)
        #expect(s.chargingLeft && s.chargingCase && !s.chargingRight)
        #expect(s.equalizer.description == "dynamic")  // untouched
        #expect(throws: BudsState.DecodeError.self) { try s.apply(statusUpdate: [0x0A, 0x36]) }
    }

    @Test func appliesNoiseControlsUpdate() throws {
        var s = try BudsState(extendedStatus: Self.payload)
        try s.apply(noiseControlsUpdate: [0x01, 0x11])
        #expect(s.noiseControl == .anc)
        #expect(throws: BudsState.DecodeError.self) { try s.apply(noiseControlsUpdate: []) }
    }

    @Test func decodesCapturedVersionInfo() throws {
        let v = try VersionInfo(payload: hex("00 00 01 81 01 01 81 01 00 00"))
        #expect(v.firmwareLeft == "R177XXU0AWB1")
        #expect(v.firmwareRight == "R177XXU0AWB1")
        #expect(v.hardwareLeft == "rev0.0")
        #expect(throws: BudsState.DecodeError.self) { try VersionInfo(payload: [0, 0]) }
    }

    @Test func wireValueNameLookup() {
        #expect(EqualizerPreset(name: "bass-boost")?.byte == 1)
        #expect(EqualizerPreset(name: "nope") == nil)
        #expect(NoiseControlMode.allNames == ["off", "anc", "ambient"])
    }

    @Test func allowlistExcludesDangerousIDs() {
        let forbidden: [UInt8] = Array(0xB0...0xBE) + Array(0x30...0x3D)
            + [0x50, 0x52, 0x53, 0x56, 0x27, 0x72, 0x70, 0x71, 0x10, 0xAB, 0x12, 0x13, 0xD4, 0xAA, 0xAC, 0xCF]
        for id in forbidden {
            #expect(!MessageID.sendable.contains(id), "0x\(String(id, radix: 16)) must never be sendable")
        }
    }
}
