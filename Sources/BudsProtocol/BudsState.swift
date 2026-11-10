/// Everything the buds report about themselves, as a snapshot.
///
/// Built from an extended status message (0x61) and kept current by applying the smaller
/// updates (0x60, 0x77) as they arrive. Layout: docs/PROTOCOL.md §3.1 and §4.2 — Buds2 only.
public struct BudsState: Equatable, Sendable, Encodable {
    public var revision: Int

    public var batteryLeft: Int
    public var batteryRight: Int
    /// Reported as 0 while neither earbud is in the case; see `caseBatteryKnown`.
    public var batteryCase: Int
    public var chargingLeft = false
    public var chargingRight = false
    public var chargingCase = false

    public var coupled: Bool
    public var primary: Side
    public var placementLeft: Placement
    public var placementRight: Placement

    public var noiseControl: NoiseControlMode
    public var ambientLevel: Int
    public var noiseCycleLeft: NoiseCycle
    public var noiseCycleRight: NoiseCycle
    public var noiseControlWithOneEarbud: Bool?
    public var customAmbient: CustomAmbient?
    public var extraHighAmbient: Bool
    /// Status byte p24. 1 is "high" on models that have ANC levels.
    public var noiseReductionLevel: Int

    public var equalizer: EqualizerPreset
    public var balance: Int

    public var touch: TouchSettings
    public var holdActionLeft: TouchHoldAction
    public var holdActionRight: TouchHoldAction
    public var doubleTapEdgeVolume: Bool?

    public var seamlessConnection: Bool
    public var ambientDuringCalls: Bool?
    public var inEarDetectionForCalls: Bool?

    public enum DecodeError: Error, Equatable {
        /// The payload ends before a field every Buds2 revision carries.
        case truncated(needed: Int, got: Int)
    }

    /// Bytes every Buds2 extended status has, whatever its revision (p0…p26).
    static let extendedStatusBaseLength = 27

    /// The case only reports its charge through an earbud sitting in it.
    public var caseBatteryKnown: Bool {
        batteryCase > 0 || placementLeft.isInCase || placementRight.isInCase
    }

    /// Decodes the payload of EXTENDED_STATUS_UPDATED (0x61).
    ///
    /// Fields added by later revisions are optional and gated on both the revision byte and
    /// the payload actually being long enough. Trailing bytes beyond the known layout are
    /// ignored, so newer firmware that appends fields still decodes.
    public init(extendedStatus p: [UInt8]) throws {
        guard p.count >= Self.extendedStatusBaseLength else {
            throw DecodeError.truncated(needed: Self.extendedStatusBaseLength, got: p.count)
        }
        let rev = Int(p[0])
        func gated(_ offset: Int, minRevision: Int) -> UInt8? {
            rev >= minRevision && offset < p.count ? p[offset] : nil
        }

        revision = rev
        batteryLeft = Int(p[2])
        batteryRight = Int(p[3])
        coupled = p[4] != 0
        primary = p[5] == 1 ? .left : .right
        placementLeft = Placement(byte: p[6] >> 4)
        placementRight = Placement(byte: p[6] & 0x0F)
        batteryCase = Int(p[7])
        equalizer = EqualizerPreset(byte: p[9])
        touch = TouchSettings(statusByte: p[10])
        holdActionLeft = TouchHoldAction(byte: p[11] >> 4)
        holdActionRight = TouchHoldAction(byte: p[11] & 0x0F)
        noiseControl = NoiseControlMode(byte: p[12])
        seamlessConnection = p[19] == 0  // inverted on the wire
        noiseCycleLeft = NoiseCycle(nibble: p[21] >> 4)
        noiseCycleRight = NoiseCycle(nibble: p[21] & 0x0F)
        ambientLevel = Int(p[23])
        noiseReductionLevel = Int(p[24])
        balance = Int(p[25])
        extraHighAmbient = p[26] != 0

        noiseControlWithOneEarbud = gated(28, minRevision: 3).map { $0 != 0 }
        if let enabled = gated(29, minRevision: 5), let volume = gated(30, minRevision: 5),
           let tone = gated(31, minRevision: 5) {
            customAmbient = CustomAmbient(
                enabled: enabled != 0,
                leftLevel: Int(volume >> 4),
                rightLevel: Int(volume & 0x0F),
                tone: Int(tone)
            )
        }
        doubleTapEdgeVolume = gated(32, minRevision: 5).map { $0 != 0 }
        ambientDuringCalls = gated(33, minRevision: 6).map { $0 != 0 }
        inEarDetectionForCalls = gated(34, minRevision: 7).map { $0 == 0 }  // inverted
        if let charging = gated(36, minRevision: 10) {
            setCharging(charging)
        }
    }

    private mutating func setCharging(_ bits: UInt8) {
        chargingLeft = bits & 0x10 != 0
        chargingRight = bits & 0x04 != 0
        chargingCase = bits & 0x01 != 0
    }

    /// Applies the payload of STATUS_UPDATED (0x60): battery, link and placement only.
    public mutating func apply(statusUpdate p: [UInt8]) throws {
        guard p.count >= 7 else { throw DecodeError.truncated(needed: 7, got: p.count) }
        batteryLeft = Int(p[1])
        batteryRight = Int(p[2])
        coupled = p[3] != 0
        primary = p[4] == 1 ? .left : .right
        placementLeft = Placement(byte: p[5] >> 4)
        placementRight = Placement(byte: p[5] & 0x0F)
        batteryCase = Int(p[6])
        if p[0] >= 10, p.count > 7 {
            setCharging(p[7])
        }
    }

    /// Applies the payload of NOISE_CONTROLS_UPDATE (0x77), sent when the mode is changed on
    /// the earbuds themselves.
    public mutating func apply(noiseControlsUpdate p: [UInt8]) throws {
        guard let mode = p.first else { throw DecodeError.truncated(needed: 1, got: 0) }
        noiseControl = NoiseControlMode(byte: mode)
    }
}

/// Firmware and hardware revisions from VERSION_INFO (0x63). docs/PROTOCOL.md §3.3.
public struct VersionInfo: Equatable, Sendable, Encodable {
    public var firmwareLeft: String
    public var firmwareRight: String
    public var hardwareLeft: String
    public var hardwareRight: String

    public init(payload p: [UInt8]) throws {
        guard p.count >= 8 else { throw BudsState.DecodeError.truncated(needed: 8, got: p.count) }
        hardwareLeft = Self.hardware(p[0])
        hardwareRight = Self.hardware(p[1])
        firmwareLeft = Self.firmware(variant: p[2], date: p[3], release: p[4])
        firmwareRight = Self.firmware(variant: p[5], date: p[6], release: p[7])
    }

    private static func hardware(_ byte: UInt8) -> String {
        "rev\(byte >> 4).\(byte & 0x0F)"
    }

    /// Rebuilds Samsung's build name, e.g. R177XXU0AWB1, from three bytes.
    private static func firmware(variant: UInt8, date: UInt8, release: UInt8) -> String {
        let years = Array("OPQRSTUVWXYZ")
        let months = Array("ABCDEFGHIJKL")
        let releases = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        func pick(_ table: [Character], _ index: Int) -> String {
            index < table.count ? String(table[index]) : "?"
        }
        return "R177XX" + (variant == 0 ? "E" : "U") + "0A"
            + pick(years, Int(date >> 4)) + pick(months, Int(date & 0x0F))
            + pick(releases, Int(release))
    }
}
