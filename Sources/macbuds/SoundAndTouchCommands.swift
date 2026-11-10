import ArgumentParser
import BudsProtocol

struct EqualizerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eq",
        abstract: "Choose an equalizer preset.",
        discussion: "Presets: \(EqualizerPreset.allNames.joined(separator: ", ")). 'normal' is the equalizer off."
    )

    @Argument var preset: String

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        guard let preset = EqualizerPreset(name: preset) else {
            throw ValidationError("Preset must be one of: \(EqualizerPreset.allNames.joined(separator: ", ")).")
        }
        try await change(device, "Equalizer", try .equalizer(preset)) { "\($0.equalizer)" }
    }
}

struct TouchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "touch",
        abstract: "Touch controls: lock, per-gesture switches, touch-and-hold actions.",
        subcommands: [Lock.self, Gesture.self, Hold.self]
    )

    struct Lock: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Lock (on) or unlock (off) every touch control."
        )

        @Argument var setting: OnOff

        @OptionGroup var device: DeviceOptions

        @MainActor
        func run() async throws {
            try await withSession(device) { session, before in
                var touch = before.touch
                touch.enabled = !setting.isOn
                try await session.perform(.touch(touch))
                let after = session.state ?? before
                print("Touch controls: \(before.touch.enabled ? "enabled" : "locked") → \(after.touch.enabled ? "enabled" : "locked")")
            }
        }
    }

    enum GestureName: String, ExpressibleByArgument, CaseIterable {
        case singleTap = "single-tap"
        case doubleTap = "double-tap"
        case tripleTap = "triple-tap"
        case hold
        case doubleTapInCall = "double-tap-in-call"
        case holdInCall = "hold-in-call"

        var keyPath: WritableKeyPath<TouchSettings, Bool> {
            switch self {
            case .singleTap: \.singleTap
            case .doubleTap: \.doubleTap
            case .tripleTap: \.tripleTap
            case .hold: \.touchAndHold
            case .doubleTapInCall: \.doubleTapInCall
            case .holdInCall: \.touchAndHoldInCall
            }
        }
    }

    struct Gesture: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Turn one gesture on or off."
        )

        @Argument var gesture: GestureName
        @Argument var setting: OnOff

        @OptionGroup var device: DeviceOptions

        @MainActor
        func run() async throws {
            try await withSession(device) { session, before in
                var touch = before.touch
                touch[keyPath: gesture.keyPath] = setting.isOn
                try await session.perform(.touch(touch))
                let after = session.state ?? before
                func text(_ s: BudsState) -> String { s.touch[keyPath: gesture.keyPath] ? "on" : "off" }
                print("\(gesture.rawValue): \(text(before)) → \(text(after))")
            }
        }
    }

    struct Hold: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Choose what touch-and-hold does on each earbud.",
            discussion: """
            Actions: \(Command.assignableHoldActions.map(\.description).joined(separator: ", ")).
            A side left out keeps its current action. 'volume' is a pair — left turns it down, \
            right turns it up — so it has to be set on both sides or neither. 'voice-assistant' \
            and 'spotify' rely on a phone app and do nothing useful with a Mac.
            """
        )

        @Option(help: "Action for the left earbud.")
        var left: String?

        @Option(help: "Action for the right earbud.")
        var right: String?

        @OptionGroup var device: DeviceOptions

        @MainActor
        func run() async throws {
            func parse(_ text: String?) throws -> TouchHoldAction? {
                guard let text else { return nil }
                guard let action = TouchHoldAction(name: text), Command.assignableHoldActions.contains(action) else {
                    throw ValidationError("'\(text)' is not an action. Use one of: \(Command.assignableHoldActions.map(\.description).joined(separator: ", ")).")
                }
                return action
            }
            let newLeft = try parse(left), newRight = try parse(right)
            guard newLeft != nil || newRight != nil else {
                throw ValidationError("Give --left, --right or both.")
            }
            try await withSession(device) { session, before in
                let l = newLeft ?? before.holdActionLeft
                let r = newRight ?? before.holdActionRight
                let volume = TouchHoldAction(byte: 3)
                guard (l == volume) == (r == volume) else {
                    throw CLIError("'volume' has to be set on both earbuds or neither: left turns it down, right turns it up.")
                }
                try await session.perform(try .touchAndHold(left: l, right: r))
                let after = session.state ?? before
                print("Touch and hold: left \(before.holdActionLeft), right \(before.holdActionRight) → left \(after.holdActionLeft), right \(after.holdActionRight)")
            }
        }
    }
}
