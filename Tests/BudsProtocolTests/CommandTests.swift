import Testing
@testable import BudsProtocol

@Suite struct CommandTests {
    static let baseline = try! BudsState(extendedStatus: BudsStateTests.payload)

    private func applied(_ command: Command) -> BudsState {
        var state = Self.baseline
        command.apply(&state)
        return state
    }

    @Test func noiseControlMatchesDocumentedVectors() throws {
        #expect(try Command.noiseControl(.off).frame.encode() == hex("FD 04 00 78 00 F0 81 DD"))
        #expect(try Command.noiseControl(.anc).frame.encode() == hex("FD 04 00 78 01 D1 91 DD"))
        #expect(try Command.noiseControl(.ambient).frame.encode() == hex("FD 04 00 78 02 B2 A1 DD"))
        #expect(applied(try .noiseControl(.anc)).noiseControl == .anc)
    }

    @Test func noiseControlRefusesModesBuds2DoesNotHave() {
        #expect(throws: Command.InvalidArgument.self) {
            try Command.noiseControl(NoiseControlMode(byte: 3))
        }
    }

    @Test func ambientLevel() throws {
        let command = try Command.ambientLevel(2)
        #expect(command.frame == Frame(id: 0x84, payload: [0x02]))
        #expect(applied(command).ambientLevel == 2)
        #expect(throws: Command.InvalidArgument.outOfRange(what: "Ambient level", value: 3, range: 0...2)) {
            try Command.ambientLevel(3)
        }
        #expect(throws: Command.InvalidArgument.self) { try Command.ambientLevel(-1) }
    }

    @Test func noiseControlWithOneEarbud() {
        #expect(Command.noiseControlWithOneEarbud(true).frame == Frame(id: 0x6F, payload: [0x01]))
        #expect(Command.noiseControlWithOneEarbud(false).frame == Frame(id: 0x6F, payload: [0x00]))
        #expect(applied(.noiseControlWithOneEarbud(true)).noiseControlWithOneEarbud == true)
    }

    @Test func touchNoiseCycle() throws {
        let ancAmbient = NoiseCycle(anc: true, ambient: true, off: false)
        let ambientOff = NoiseCycle(anc: false, ambient: true, off: true)
        let command = try Command.touchNoiseCycle(left: ancAmbient, right: ambientOff)
        #expect(command.frame == Frame(id: 0x79, payload: [1, 1, 0, 0, 1, 1]))
        #expect(applied(command).noiseCycleRight == ambientOff)
        #expect(throws: Command.InvalidArgument.badNoiseCycle) {
            try Command.touchNoiseCycle(left: ancAmbient, right: NoiseCycle(anc: true, ambient: true, off: true))
        }
        #expect(NoiseCycle(parsing: "off+anc") == NoiseCycle(anc: true, ambient: false, off: true))
        #expect(NoiseCycle(parsing: "anc+loud") == nil)
    }

    /// Learned on the device: 0x78 is answered by 0x77, 0x6F by nothing, the rest by 0x42.
    @Test func replyKinds() throws {
        #expect(try Command.noiseControl(.anc).reply == .noiseControlsUpdate)
        #expect(Command.noiseControlWithOneEarbud(true).reply == .none)
        #expect(try Command.ambientLevel(1).reply == .acknowledgement)
        #expect(Command.inEarDetectionForCalls(true).reply == .none)
        #expect(Command.ambientDuringCalls(true).reply == .none)
        #expect(Command.seamlessConnection(true).reply == .acknowledgement)  // not yet sent to the device
        #expect(try Command.balance(16).reply == .acknowledgement)
        #expect(Command.doubleTapEdgeVolume(true).reply == .acknowledgement)
    }

    @Test func isReflected() throws {
        #expect(try Command.noiseControl(.ambient).isReflected(in: Self.baseline))
        #expect(try !Command.noiseControl(.anc).isReflected(in: Self.baseline))
    }

    @Test func equalizer() throws {
        #expect(try Command.equalizer(EqualizerPreset(byte: 3)).frame.encode() == hex("FD 04 00 86 03 5D 81 DD"))
        let soft = EqualizerPreset(name: "soft")!
        #expect(applied(try .equalizer(soft)).equalizer == soft)
        #expect(throws: Command.InvalidArgument.self) { try Command.equalizer(EqualizerPreset(byte: 7)) }
    }

    @Test func touchLockAndGestures() {
        var settings = Self.baseline.touch
        #expect(Command.touch(settings).frame == Frame(id: 0x90, payload: [1, 1, 1, 1, 1, 1, 1]))
        settings.enabled = false
        #expect(Command.touch(settings).frame.payload == [0, 1, 1, 1, 1, 1, 1])
        settings.enabled = true
        settings.tripleTap = false
        settings.touchAndHoldInCall = false
        let command = Command.touch(settings)
        // order: enabled, single, double, triple, hold, double-in-call, hold-in-call
        #expect(command.frame.payload == [1, 1, 1, 0, 1, 1, 0])
        #expect(applied(command).touch == settings)
    }

    @Test func touchAndHold() throws {
        let noise = TouchHoldAction(name: "noise-control")!
        let spotify = TouchHoldAction(name: "spotify")!
        let command = try Command.touchAndHold(left: noise, right: spotify)
        #expect(command.frame == Frame(id: 0x92, payload: [0x02, 0x04]))
        #expect(applied(command).holdActionLeft == noise)
        #expect(applied(command).holdActionRight == spotify)
        #expect(throws: Command.InvalidArgument.self) {
            try Command.touchAndHold(left: TouchHoldAction(byte: 5), right: noise)
        }
    }

    @Test func invertedSettingsSendZeroForOn() {
        #expect(Command.inEarDetectionForCalls(true).frame == Frame(id: 0x6E, payload: [0x00]))
        #expect(Command.inEarDetectionForCalls(false).frame == Frame(id: 0x6E, payload: [0x01]))
        #expect(Command.seamlessConnection(true).frame == Frame(id: 0xAF, payload: [0x00]))
        #expect(Command.seamlessConnection(false).frame == Frame(id: 0xAF, payload: [0x01]))
        #expect(applied(.inEarDetectionForCalls(false)).inEarDetectionForCalls == false)
        #expect(applied(.seamlessConnection(false)).seamlessConnection == false)
    }

    @Test func plainToggles() {
        #expect(Command.ambientDuringCalls(true).frame == Frame(id: 0x8B, payload: [0x01]))
        #expect(Command.doubleTapEdgeVolume(true).frame == Frame(id: 0x95, payload: [0x01]))
        #expect(applied(.ambientDuringCalls(true)).ambientDuringCalls == true)
        #expect(applied(.doubleTapEdgeVolume(true)).doubleTapEdgeVolume == true)
    }

    @Test func balance() throws {
        #expect(try Command.balance(16).frame == Frame(id: 0x8F, payload: [0x10]))
        #expect(applied(try .balance(0)).balance == 0)
        #expect(throws: Command.InvalidArgument.self) { try Command.balance(33) }
    }

    @Test func customAmbient() throws {
        let settings = CustomAmbient(enabled: true, leftLevel: 2, rightLevel: 0, tone: 4)
        let command = try Command.customAmbient(settings)
        #expect(command.frame == Frame(id: 0x82, payload: [1, 2, 0, 4]))
        #expect(applied(command).customAmbient == settings)
        #expect(throws: Command.InvalidArgument.self) {
            try Command.customAmbient(CustomAmbient(enabled: true, leftLevel: 3, rightLevel: 0, tone: 2))
        }
        #expect(throws: Command.InvalidArgument.self) {
            try Command.customAmbient(CustomAmbient(enabled: true, leftLevel: 1, rightLevel: 1, tone: 5))
        }
    }

    @Test func deviceInfoHelpers() throws {
        #expect(DeviceInfo.ascii([0x52, 0x31, 0x37, 0x37, 0x00, 0x00]) == "R177")
        let pair = DeviceInfo.leftRight(Array("ABCDEFGH".utf8), width: 4)
        #expect(pair.left == "ABCD")
        #expect(pair.right == "EFGH")
        #expect(DeviceInfo.leftRight(Array("ABCD".utf8), width: 4).right == nil)
        #expect(FitResult(byte: 1) == .good)
        #expect(FitResult(byte: 9) == .unknown(9))
    }

    @Test func noiseReductionLevel() {
        #expect(Command.noiseReductionLevel(high: true).frame == Frame(id: 0x83, payload: [0x01]))
        #expect(Command.noiseReductionLevel(high: false).frame == Frame(id: 0x83, payload: [0x00]))
        #expect(applied(.noiseReductionLevel(high: true)).noiseReductionLevel == 1)
        // Extra-high ambient is ignored by Buds2 firmware and must stay unsendable.
        #expect(!MessageID.sendable.contains(0x96))
    }

    @Test func everyCommandIsOnTheAllowlist() throws {
        let cycle = NoiseCycle(anc: true, ambient: true, off: false)
        let commands: [Command] = [
            try .noiseControl(.anc), try .ambientLevel(1), .noiseControlWithOneEarbud(true),
            try .touchNoiseCycle(left: cycle, right: cycle),
            try .equalizer(EqualizerPreset(byte: 1)), .touch(Self.baseline.touch),
            try .touchAndHold(left: TouchHoldAction(byte: 2), right: TouchHoldAction(byte: 2)),
        ]
        for command in commands {
            #expect(MessageID.sendable.contains(command.frame.id))
        }
    }
}
