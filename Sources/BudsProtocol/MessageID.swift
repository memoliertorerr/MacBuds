/// Message IDs this project reads or sends. See docs/PROTOCOL.md §4.
/// IDs on the never-send list (§5) are deliberately absent.
public enum MessageID {
    // Buds → host
    public static let usageReport: UInt8 = 0x40
    public static let meteringReport: UInt8 = 0x41
    public static let acknowledgement: UInt8 = 0x42
    public static let response: UInt8 = 0x51
    public static let statusUpdated: UInt8 = 0x60
    public static let extendedStatusUpdated: UInt8 = 0x61
    public static let versionInfo: UInt8 = 0x63
    public static let noiseControlsUpdate: UInt8 = 0x77
    public static let touchUpdated: UInt8 = 0x91
    public static let spatialAudioData: UInt8 = 0xC2
    public static let debugEvent: UInt8 = 0xF2

    // Host → buds
    public static let setCallPathControl: UInt8 = 0x6E
    public static let setNoiseControlWithOneEarbud: UInt8 = 0x6F
    public static let noiseControls: UInt8 = 0x78
    public static let setTouchAndHoldNoiseControls: UInt8 = 0x79
    public static let customizeAmbientSound: UInt8 = 0x82
    public static let noiseReductionLevel: UInt8 = 0x83
    public static let ambientVolume: UInt8 = 0x84
    public static let equalizer: UInt8 = 0x86
    public static let setSidetone: UInt8 = 0x8B
    public static let setHearingEnhancements: UInt8 = 0x8F
    public static let lockTouchpad: UInt8 = 0x90
    public static let setTouchpadOption: UInt8 = 0x92
    public static let outsideDoubleTap: UInt8 = 0x95
    public static let setSeamlessConnection: UInt8 = 0xAF
    public static let checkFit: UInt8 = 0x9D
    public static let findMyEarbudsStart: UInt8 = 0xA0
    public static let findMyEarbudsStop: UInt8 = 0xA1
    public static let findMyEarbudsOnWearingStart: UInt8 = 0xA6

    // Read-only information requests; the reply carries the same ID.
    // (Build info 0x28 and battery type 0x94 go unanswered on this firmware, and the sensor
    // dump 0x26 comes back zeroed, so they are not sent. docs/PROTOCOL.md §4.11.)
    public static let debugSKU: UInt8 = 0x22
    public static let debugSerialNumber: UInt8 = 0x29

    // Buds → host
    public static let checkFitResult: UInt8 = 0x9E
}

extension MessageID {
    /// The only message IDs the transport will put on the wire. An allowlist rather than a
    /// blocklist: anything not named here — firmware update, factory reset, reboot, factory
    /// and debug commands, and every undocumented ID — is refused. Add an ID only after its
    /// host→buds row exists in docs/PROTOCOL.md §4.
    public static let sendable: Set<UInt8> = [
        setCallPathControl, setNoiseControlWithOneEarbud, noiseControls,
        setTouchAndHoldNoiseControls, customizeAmbientSound, ambientVolume, equalizer,
        setSidetone, setHearingEnhancements, lockTouchpad, setTouchpadOption,
        outsideDoubleTap, setSeamlessConnection, noiseReductionLevel,
        checkFit, findMyEarbudsStart, findMyEarbudsStop, findMyEarbudsOnWearingStart,
        debugSKU, debugSerialNumber,
    ]
}
