/// A setting change: the frame to send and what it does to the snapshot once the buds
/// accept it. The buds do not resend full status after a write, so the snapshot is updated
/// locally from the accepted command. Payload layouts: docs/PROTOCOL.md §4.
public struct Command: Sendable {
    /// How the buds answer a given message. Learned on the device, message by message —
    /// docs/PROTOCOL.md §4 records each one.
    public enum ReplyKind: Sendable, Equatable {
        /// 0x42 echoing the accepted values (or 0x51 with a result code).
        case acknowledgement
        /// 0x42 if the noise control mode changed; otherwise 0x77 reporting the mode in
        /// effect, which is not necessarily the one asked for — the buds keep it off while
        /// they are not being worn.
        case noiseControlsUpdate
        /// Nothing comes back; the change is only visible in the next status.
        case none
    }

    public let frame: Frame
    public let reply: ReplyKind
    public let apply: @Sendable (inout BudsState) -> Void

    init(
        _ id: UInt8,
        _ payload: [UInt8],
        reply: ReplyKind = .acknowledgement,
        apply: @escaping @Sendable (inout BudsState) -> Void
    ) {
        frame = Frame(id: id, payload: payload)
        self.reply = reply
        self.apply = apply
    }

    /// Whether `state` already shows this command's effect.
    public func isReflected(in state: BudsState) -> Bool {
        var expected = state
        apply(&expected)
        return expected == state
    }

    public enum InvalidArgument: Error, Equatable, CustomStringConvertible {
        case outOfRange(what: String, value: Int, range: ClosedRange<Int>)
        case unknownValue(what: String, value: String)
        case badNoiseCycle

        public var description: String {
            switch self {
            case .outOfRange(let what, let value, let range):
                "\(what) must be \(range.lowerBound)–\(range.upperBound), got \(value)."
            case .unknownValue(let what, let value):
                "\(value) is not a known \(what)."
            case .badNoiseCycle:
                "A touch noise cycle needs exactly two of: anc, ambient, off."
            }
        }
    }

    private static func flag(_ on: Bool) -> UInt8 { on ? 1 : 0 }

    // MARK: Noise control — §4.3

    public static func noiseControl(_ mode: NoiseControlMode) throws -> Command {
        guard mode.name != nil else {
            throw InvalidArgument.unknownValue(what: "noise control mode", value: "\(mode)")
        }
        return Command(MessageID.noiseControls, [mode.byte], reply: .noiseControlsUpdate) {
            $0.noiseControl = mode
        }
    }

    /// Buds2 ambient sound level, 0 (low) to 2 (high).
    public static func ambientLevel(_ level: Int) throws -> Command {
        guard (0...2).contains(level) else {
            throw InvalidArgument.outOfRange(what: "Ambient level", value: level, range: 0...2)
        }
        return Command(MessageID.ambientVolume, [UInt8(level)]) { $0.ambientLevel = level }
    }

    public static func noiseControlWithOneEarbud(_ on: Bool) -> Command {
        Command(MessageID.setNoiseControlWithOneEarbud, [flag(on)], reply: .none) {
            $0.noiseControlWithOneEarbud = on
        }
    }

    /// Which two modes touch-and-hold switches between, per earbud.
    public static func touchNoiseCycle(left: NoiseCycle, right: NoiseCycle) throws -> Command {
        for cycle in [left, right] {
            guard [cycle.anc, cycle.ambient, cycle.off].filter({ $0 }).count == 2 else {
                throw InvalidArgument.badNoiseCycle
            }
        }
        let payload = [left, right].flatMap { [flag($0.anc), flag($0.ambient), flag($0.off)] }
        return Command(MessageID.setTouchAndHoldNoiseControls, payload) {
            $0.noiseCycleLeft = left
            $0.noiseCycleRight = right
        }
    }

    // MARK: Experimental on Buds2 — §4.3

    /// ANC strength, a Buds Pro setting. Buds2 firmware acknowledges it and stores the value
    /// (status p24), but whether it changes the cancellation is unproven.
    /// (Extra-high ambient, 0x96, was tried too: the buds ignore it, so it is not sent.)
    public static func noiseReductionLevel(high: Bool) -> Command {
        Command(MessageID.noiseReductionLevel, [flag(high)]) { $0.noiseReductionLevel = high ? 1 : 0 }
    }

    // MARK: Equalizer — §4.6

    public static func equalizer(_ preset: EqualizerPreset) throws -> Command {
        guard preset.name != nil else {
            throw InvalidArgument.unknownValue(what: "equalizer preset", value: "\(preset)")
        }
        return Command(MessageID.equalizer, [preset.byte]) { $0.equalizer = preset }
    }

    // MARK: Touch — §4.7, §4.8

    /// Touch lock and the per-gesture switches, sent together as one message. To change one
    /// of them, start from the current `BudsState.touch` and alter that field.
    public static func touch(_ settings: TouchSettings) -> Command {
        let payload = [
            settings.enabled, settings.singleTap, settings.doubleTap, settings.tripleTap,
            settings.touchAndHold, settings.doubleTapInCall, settings.touchAndHoldInCall,
        ].map(flag)
        return Command(MessageID.lockTouchpad, payload) { $0.touch = settings }
    }

    /// Actions a Mac can meaningfully assign. "other" (05/06) asks the host app to react to
    /// the hold, which nothing here does.
    public static let assignableHoldActions: [TouchHoldAction] = [1, 2, 3, 4].map(TouchHoldAction.init(byte:))

    public static func touchAndHold(left: TouchHoldAction, right: TouchHoldAction) throws -> Command {
        for action in [left, right] where !assignableHoldActions.contains(action) {
            throw InvalidArgument.unknownValue(what: "touch-and-hold action", value: "\(action)")
        }
        return Command(MessageID.setTouchpadOption, [left.byte, right.byte]) {
            $0.holdActionLeft = left
            $0.holdActionRight = right
        }
    }

    // MARK: Custom ambient — §4.3

    /// Per-ear ambient levels (0–2) and tone (0–4, 2 neutral).
    public static func customAmbient(_ settings: CustomAmbient) throws -> Command {
        for (what, value) in [("Left level", settings.leftLevel), ("Right level", settings.rightLevel)] {
            guard (0...2).contains(value) else {
                throw InvalidArgument.outOfRange(what: what, value: value, range: 0...2)
            }
        }
        guard (0...4).contains(settings.tone) else {
            throw InvalidArgument.outOfRange(what: "Tone", value: settings.tone, range: 0...4)
        }
        let payload = [flag(settings.enabled), UInt8(settings.leftLevel), UInt8(settings.rightLevel), UInt8(settings.tone)]
        return Command(MessageID.customizeAmbientSound, payload, reply: .none) { $0.customAmbient = settings }
    }

    // MARK: Calls, connection, balance, Labs — §4.4

    /// Wire value is inverted: 00 means enabled.
    public static func inEarDetectionForCalls(_ on: Bool) -> Command {
        Command(MessageID.setCallPathControl, [flag(!on)], reply: .none) { $0.inEarDetectionForCalls = on }
    }

    public static func ambientDuringCalls(_ on: Bool) -> Command {
        Command(MessageID.setSidetone, [flag(on)], reply: .none) { $0.ambientDuringCalls = on }
    }

    /// Wire value is inverted: 00 means enabled.
    public static func seamlessConnection(_ on: Bool) -> Command {
        Command(MessageID.setSeamlessConnection, [flag(!on)]) { $0.seamlessConnection = on }
    }

    /// Left/right balance, 0–32 with 16 in the centre.
    public static func balance(_ value: Int) throws -> Command {
        guard (0...32).contains(value) else {
            throw InvalidArgument.outOfRange(what: "Balance", value: value, range: 0...32)
        }
        return Command(MessageID.setHearingEnhancements, [UInt8(value)]) { $0.balance = value }
    }

    public static func doubleTapEdgeVolume(_ on: Bool) -> Command {
        Command(MessageID.outsideDoubleTap, [flag(on)]) { $0.doubleTapEdgeVolume = on }
    }
}

extension NoiseCycle {
    /// Parses "anc+ambient", "ambient+off" and so on.
    public init?(parsing text: String) {
        let parts = Set(text.lowercased().split(separator: "+").map(String.init))
        guard parts.isSubset(of: ["anc", "ambient", "off"]) else { return nil }
        self.init(anc: parts.contains("anc"), ambient: parts.contains("ambient"), off: parts.contains("off"))
    }
}
