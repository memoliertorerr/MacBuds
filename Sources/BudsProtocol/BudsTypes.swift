/// Value types for the settings the buds report. Each wraps the wire byte so an unexpected
/// value from newer firmware is carried through and shown, never a decode failure.

public enum Side: String, Sendable, Encodable {
    case left, right
}

/// A wire byte with a known set of named values.
public protocol WireValue: Hashable, Sendable, Encodable, CustomStringConvertible {
    var byte: UInt8 { get }
    init(byte: UInt8)
    static var names: [UInt8: String] { get }
}

extension WireValue {
    public var name: String? { Self.names[byte] }
    public var description: String {
        if let name { return name }
        let hex = String(byte, radix: 16, uppercase: true)
        return "unknown(0x\(byte < 0x10 ? "0" : "")\(hex))"
    }

    /// Looks a value up by its name, as typed on the command line.
    public init?(name: String) {
        guard let match = Self.names.first(where: { $0.value == name }) else { return nil }
        self.init(byte: match.key)
    }

    public static var allNames: [String] {
        names.sorted { $0.key < $1.key }.map(\.value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Where an earbud is. docs/PROTOCOL.md §4.2.
public struct Placement: WireValue {
    public var byte: UInt8
    public init(byte: UInt8) { self.byte = byte }
    public static let names: [UInt8: String] = [
        0: "disconnected", 1: "wearing", 2: "idle", 3: "in-open-case", 4: "in-closed-case",
    ]
    public static let wearing = Placement(byte: 1)
    public var isInCase: Bool { byte == 3 || byte == 4 }
}

/// docs/PROTOCOL.md §4.3.
public struct NoiseControlMode: WireValue {
    public var byte: UInt8
    public init(byte: UInt8) { self.byte = byte }
    public static let names: [UInt8: String] = [0: "off", 1: "anc", 2: "ambient"]
    public static let off = NoiseControlMode(byte: 0)
    public static let anc = NoiseControlMode(byte: 1)
    public static let ambient = NoiseControlMode(byte: 2)
}

/// docs/PROTOCOL.md §4.6.
public struct EqualizerPreset: WireValue {
    public var byte: UInt8
    public init(byte: UInt8) { self.byte = byte }
    public static let names: [UInt8: String] = [
        0: "normal", 1: "bass-boost", 2: "soft", 3: "dynamic", 4: "clear", 5: "treble-boost",
    ]
}

/// What touch-and-hold does on one earbud. docs/PROTOCOL.md §4.8.
public struct TouchHoldAction: WireValue {
    public var byte: UInt8
    public init(byte: UInt8) { self.byte = byte }
    public static let names: [UInt8: String] = [
        1: "voice-assistant", 2: "noise-control", 3: "volume", 4: "spotify",
        5: "other-left", 6: "other-right",
    ]
}

/// Touch lock and per-gesture enables. docs/PROTOCOL.md §4.7.
public struct TouchSettings: Equatable, Sendable, Encodable {
    /// False means every touch control is locked.
    public var enabled: Bool
    public var singleTap: Bool
    public var doubleTap: Bool
    public var tripleTap: Bool
    public var touchAndHold: Bool
    public var doubleTapInCall: Bool
    public var touchAndHoldInCall: Bool

    /// Status byte p10.
    public init(statusByte b: UInt8) {
        touchAndHold = b & 0x01 != 0
        tripleTap = b & 0x02 != 0
        doubleTap = b & 0x04 != 0
        singleTap = b & 0x08 != 0
        doubleTapInCall = b & 0x10 != 0
        touchAndHoldInCall = b & 0x20 != 0
        enabled = b & 0x80 != 0
    }
}

/// Which noise-control modes touch-and-hold cycles through on one earbud.
/// docs/PROTOCOL.md §4.5.
public struct NoiseCycle: Hashable, Sendable, Encodable, CustomStringConvertible {
    public var anc: Bool
    public var ambient: Bool
    public var off: Bool

    public init(anc: Bool, ambient: Bool, off: Bool) {
        self.anc = anc
        self.ambient = ambient
        self.off = off
    }

    /// One nibble of status byte p21: bit 0 off, bit 1 ambient, bit 2 ANC.
    init(nibble: UInt8) {
        self.init(anc: nibble & 0x4 != 0, ambient: nibble & 0x2 != 0, off: nibble & 0x1 != 0)
    }

    public var description: String {
        let parts = [anc ? "anc" : nil, ambient ? "ambient" : nil, off ? "off" : nil]
        return parts.compactMap { $0 }.joined(separator: "+")
    }
}

public struct CustomAmbient: Equatable, Sendable, Encodable {
    public var enabled: Bool
    public var leftLevel: Int
    public var rightLevel: Int
    /// 0–4, 2 is neutral.
    public var tone: Int

    public init(enabled: Bool, leftLevel: Int, rightLevel: Int, tone: Int) {
        self.enabled = enabled
        self.leftLevel = leftLevel
        self.rightLevel = rightLevel
        self.tone = tone
    }
}
