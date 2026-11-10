import ArgumentParser
import BudsProtocol
import BudsTransport
import Foundation

struct FindCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find my earbuds: make them beep loudly.",
        subcommands: [Start.self, Stop.self]
    )

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Beep for a while, then stop.",
            discussion: "The tone is loud. It refuses to start while an earbud is in an ear unless --force is given."
        )

        @Option(help: "How long to beep before stopping.")
        var seconds: Double = 15

        @Flag(help: "Beep even though an earbud is being worn.")
        var force = false

        @OptionGroup var device: DeviceOptions

        @MainActor
        func run() async throws {
            guard (1...180).contains(seconds) else {
                throw ValidationError("--seconds must be between 1 and 180.")
            }
            try await withSession(device) { session, state in
                let worn = state.placementLeft == .wearing || state.placementRight == .wearing
                guard !worn || force else {
                    throw CLIError("An earbud is being worn (left \(state.placementLeft), right \(state.placementRight)). Take them out, or pass --force.")
                }
                // The on-wearing variant is the one that still beeps with an earbud in an ear.
                let id = worn ? MessageID.findMyEarbudsOnWearingStart : MessageID.findMyEarbudsStart
                try session.send(Frame(id: id))
                print("Beeping for \(Int(seconds)) s…")
                // The buds send a stop of their own if someone ends the search on the earbuds.
                let stoppedOnBuds = (try? await session.waitFor(MessageID.findMyEarbudsStop, timeout: seconds)) != nil
                if stoppedOnBuds {
                    print("Stopped from the earbuds.")
                } else if session.isOpen {
                    try session.send(Frame(id: MessageID.findMyEarbudsStop))
                    try await Task.sleep(for: .milliseconds(300))
                    print("Stopped.")
                }
            }
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop the beeping.")

        @OptionGroup var device: DeviceOptions

        @MainActor
        func run() async throws {
            try await withSession(device) { session, _ in
                try session.send(Frame(id: MessageID.findMyEarbudsStop))
                try await Task.sleep(for: .milliseconds(300))
                print("Stop sent.")
            }
        }
    }
}

struct FitTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fit-test",
        abstract: "Check how well the earbuds seal. Plays a short tone; wear both earbuds."
    )

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await withSession(device) { session, state in
            guard state.placementLeft == .wearing, state.placementRight == .wearing else {
                throw CLIError("Put both earbuds in your ears first (left \(state.placementLeft), right \(state.placementRight)).")
            }
            print("Testing fit — stay still and quiet for a few seconds…")
            let start = Frame(id: MessageID.checkFit, payload: [0x01])
            let stop = Frame(id: MessageID.checkFit, payload: [0x00])
            let result: [UInt8]
            do {
                result = try await session.waitFor(MessageID.checkFitResult, sending: start, timeout: 20)
            } catch {
                if session.isOpen { try? session.send(stop) }
                throw error
            }
            try session.send(stop)
            try await Task.sleep(for: .milliseconds(300))
            guard result.count >= 2 else {
                throw CLIError("The earbuds sent a fit result this tool cannot read.")
            }
            print("Left:  \(FitResult(byte: result[0]))")
            print("Right: \(FitResult(byte: result[1]))")
        }
    }
}

struct InfoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Firmware, hardware revision, serial numbers and model. Read-only."
    )

    @OptionGroup var device: DeviceOptions

    @MainActor
    func run() async throws {
        try await withSession(device) { session, _ in
            var rows: [(String, String)] = [("Device", session.deviceName)]
            func pair(_ label: String, _ value: (left: String, right: String?)) {
                rows.append((label, value.right.map { "left \(value.left), right \($0)" } ?? value.left))
            }
            /// A request the buds do not answer is reported, not fatal.
            func ask(_ id: UInt8) async -> [UInt8]? {
                try? await session.query(id, timeout: 2)
            }

            if let version = await session.versionInfo() {
                pair("Firmware", (version.firmwareLeft, version.firmwareRight))
                pair("Hardware", (version.hardwareLeft, version.hardwareRight))
            }
            if let serial = await ask(MessageID.debugSerialNumber) {
                pair("Serial number", DeviceInfo.leftRight(serial, width: 11))
            }
            if let sku = await ask(MessageID.debugSKU) {
                pair("SKU", DeviceInfo.leftRight(sku, width: 14))
            }

            let width = rows.map(\.0.count).max() ?? 0
            for row in rows {
                print(row.0.padding(toLength: width + 2, withPad: " ", startingAt: 0) + row.1)
            }
        }
    }
}
