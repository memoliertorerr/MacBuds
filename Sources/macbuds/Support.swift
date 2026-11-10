import ArgumentParser
import BudsProtocol
import BudsTransport

struct DeviceOptions: ParsableArguments {
    @Option(help: "Bluetooth address of the earbuds. Only needed when several Galaxy Buds2 are paired; MACBUDS_ADDRESS works too.")
    var address: String?

    @Flag(help: "Print raw frames received from the earbuds (telemetry excluded).")
    var verbose = false
}

enum OnOff: String, ExpressibleByArgument, CaseIterable {
    case on, off
    var isOn: Bool { self == .on }
}

/// Connects, waits for the first status, runs `body`, and always closes the channel.
@MainActor
func withSession<T>(_ options: DeviceOptions, _ body: (BudsSession, BudsState) async throws -> T) async throws -> T {
    let session = BudsSession(address: options.address)
    if options.verbose {
        session.onFrame = { frame in
            // Telemetry the buds stream constantly; see docs/PROTOCOL.md §4.12.
            let noise: Set<UInt8> = [0x27, 0x40, 0x41, 0xC2, 0xF2, 0xF4, MessageID.extendedStatusUpdated, MessageID.versionInfo]
            guard !noise.contains(frame.id) else { return }
            let bytes = ([frame.id] + frame.payload).map { String($0, radix: 16, uppercase: true) }
            print("rx: \(bytes.joined(separator: " "))")
        }
    }
    try await session.connect()
    defer { session.disconnect() }
    let state = try await session.currentState()
    return try await body(session, state)
}

/// Sends one setting change and reports what changed.
@MainActor
func change(_ options: DeviceOptions, _ label: String, _ command: Command, value: (BudsState) -> String) async throws {
    try await withSession(options) { session, before in
        try await session.perform(command)
        let after = session.state ?? before
        print("\(label): \(value(before)) → \(value(after))")
    }
}

/// A failure to report as-is, without ArgumentParser's usage text.
struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
