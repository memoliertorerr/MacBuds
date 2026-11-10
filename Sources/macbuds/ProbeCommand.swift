import ArgumentParser
import BudsTransport

struct ProbeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "List the earbuds' Bluetooth services and dump raw inbound bytes (listen only)."
    )

    @Option(help: "Bluetooth address of the earbuds. Only needed when several Galaxy Buds2 are paired; MACBUDS_ADDRESS works too.")
    var address: String?

    @Option(help: "RFCOMM channel to open. Omit to only list services.")
    var channel: UInt8?

    @Option(help: "How long to listen, in seconds.")
    var seconds: Double = 8

    @MainActor
    func run() async throws {
        let probe = try Probe(address: address) { print($0) }
        print("device: \(probe.deviceName) [\(probe.address)] connected=\(probe.isConnected)")
        for s in try probe.services() {
            let ch = s.rfcommChannel.map { "rfcomm \($0)" } ?? "no rfcomm"
            print("service: \(s.name) | \(ch) | \(s.uuids.joined(separator: ", "))")
        }
        if let channel {
            try probe.listen(channelID: channel, seconds: seconds)
        }
    }
}
