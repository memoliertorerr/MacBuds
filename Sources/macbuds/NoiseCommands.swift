import ArgumentParser
import BudsProtocol
import BudsTransport

struct NoiseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "noise",
        abstract: "Set noise control: anc, ambient or off."
    )

    @Argument(help: "anc, ambient or off.")
    var mode: String

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        guard let mode = NoiseControlMode(name: mode) else {
            throw ValidationError("Mode must be one of: \(NoiseControlMode.allNames.joined(separator: ", ")).")
        }
        do {
            try await change(device, "Noise control", try .noiseControl(mode)) { "\($0.noiseControl)" }
        } catch BudsSession.SessionError.notApplied {
            throw CLIError(
                "The earbuds stayed on a different mode. Noise control only engages while they are worn — "
                    + "both of them, unless one-earbud noise control is on (macbuds one-earbud-noise on)."
            )
        }
    }
}

struct AmbientLevelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ambient-level",
        abstract: "Set how much outside sound ambient mode lets in: 0 (low) to 2 (high)."
    )

    @Argument var level: Int

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "Ambient level", try .ambientLevel(level)) { "\($0.ambientLevel)" }
    }
}

struct OneEarbudNoiseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "one-earbud-noise",
        abstract: "Allow noise control while wearing a single earbud."
    )

    @Argument var setting: OnOff

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "One-earbud noise control", .noiseControlWithOneEarbud(setting.isOn)) {
            $0.noiseControlWithOneEarbud == true ? "on" : "off"
        }
    }
}

struct NoiseCycleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "noise-cycle",
        abstract: "Choose the two noise modes touch-and-hold switches between.",
        discussion: "Each side takes two of anc, ambient, off joined with '+', e.g. anc+ambient. A side left out keeps its current pair."
    )

    @Option(help: "Left earbud, e.g. anc+ambient.")
    var left: String?

    @Option(help: "Right earbud, e.g. ambient+off.")
    var right: String?

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        func parse(_ text: String?) throws -> NoiseCycle? {
            guard let text else { return nil }
            guard let cycle = NoiseCycle(parsing: text) else {
                throw ValidationError("'\(text)' is not a noise cycle. Use two of anc, ambient, off joined with '+'.")
            }
            return cycle
        }
        let newLeft = try parse(left), newRight = try parse(right)
        guard newLeft != nil || newRight != nil else {
            throw ValidationError("Give --left, --right or both.")
        }
        try await withSession(device) { session, before in
            let command = try Command.touchNoiseCycle(
                left: newLeft ?? before.noiseCycleLeft,
                right: newRight ?? before.noiseCycleRight
            )
            try await session.perform(command)
            let after = session.state ?? before
            print("Touch noise cycle: left \(before.noiseCycleLeft), right \(before.noiseCycleRight) → left \(after.noiseCycleLeft), right \(after.noiseCycleRight)")
        }
    }
}
