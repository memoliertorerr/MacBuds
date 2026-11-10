import ArgumentParser
import BudsProtocol

private func onOff(_ value: Bool?) -> String {
    switch value {
    case true?: "on"
    case false?: "off"
    case nil: "not reported"
    }
}

struct InEarDetectionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "in-ear-detection",
        abstract: "Route calls to the earbuds only while they are in your ears."
    )
    @Argument var setting: OnOff
    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "In-ear detection for calls", .inEarDetectionForCalls(setting.isOn)) {
            onOff($0.inEarDetectionForCalls)
        }
    }
}

struct CallAmbientCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "call-ambient",
        abstract: "Hear your own voice (ambient sound) during calls."
    )
    @Argument var setting: OnOff
    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "Ambient sound during calls", .ambientDuringCalls(setting.isOn)) {
            onOff($0.ambientDuringCalls)
        }
    }
}

struct SeamlessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seamless",
        abstract: "Seamless earbud connection: let the earbuds switch between your devices."
    )
    @Argument var setting: OnOff
    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "Seamless connection", .seamlessConnection(setting.isOn)) {
            onOff($0.seamlessConnection)
        }
    }
}

struct DoubleTapEdgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "double-tap-edge",
        abstract: "Labs: double-tap the edge of an earbud to change the volume."
    )
    @Argument var setting: OnOff
    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "Double-tap edge volume", .doubleTapEdgeVolume(setting.isOn)) {
            onOff($0.doubleTapEdgeVolume)
        }
    }
}

struct BalanceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "balance",
        abstract: "Left/right sound balance: 0–32, 16 is centre."
    )
    @Argument var value: Int
    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "Balance", try .balance(value)) { "\($0.balance)" }
    }
}

struct CustomAmbientCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "custom-ambient",
        abstract: "Customize ambient sound: per-ear level and tone.",
        discussion: "Options left out keep their current value."
    )

    @Argument(help: "on or off. Omit to keep the current setting.")
    var setting: OnOff?

    @Option(help: "Left level, 0–2.")
    var left: Int?

    @Option(help: "Right level, 0–2.")
    var right: Int?

    @Option(help: "Tone, 0 (soft) to 4 (clear); 2 is neutral.")
    var tone: Int?

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        guard setting != nil || left != nil || right != nil || tone != nil else {
            throw ValidationError("Nothing to change. Give on/off, --left, --right or --tone.")
        }
        func text(_ s: BudsState) -> String {
            guard let c = s.customAmbient else { return "not reported" }
            return "\(c.enabled ? "on" : "off") (left \(c.leftLevel), right \(c.rightLevel), tone \(c.tone))"
        }
        try await withSession(device) { session, before in
            guard var custom = before.customAmbient else {
                throw CLIError("These earbuds do not report a custom ambient setting.")
            }
            if let setting { custom.enabled = setting.isOn }
            if let left { custom.leftLevel = left }
            if let right { custom.rightLevel = right }
            if let tone { custom.tone = tone }
            try await session.perform(try .customAmbient(custom))
            print("Custom ambient: \(text(before)) → \(text(session.state ?? before))")
        }
    }
}

struct ANCLevelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "anc-level",
        abstract: "Experimental: noise cancelling strength, high or low.",
        discussion: "A Galaxy Buds Pro setting. Buds2 accept and remember it, but it is not known whether it changes how strongly they cancel noise."
    )

    enum Level: String, ExpressibleByArgument, CaseIterable { case high, low }

    @Argument var level: Level
    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await change(device, "ANC level", .noiseReductionLevel(high: level == .high)) {
            $0.noiseReductionLevel == 1 ? "high" : "low"
        }
    }
}
