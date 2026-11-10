import BudsProtocol
import Foundation
@preconcurrency import IOBluetooth

/// Bluetooth classic (RFCOMM) transport to the earbuds.
public enum BudsTransport {
    /// Environment variable naming the earbuds' Bluetooth address, for when more than one
    /// pair of Buds2 is paired with this Mac.
    public static let addressEnvironmentVariable = "MACBUDS_ADDRESS"

    public enum DiscoveryError: Error, CustomStringConvertible {
        case notPaired(String)
        case noEarbudsFound
        case ambiguous([String])

        public var description: String {
            switch self {
            case .notPaired(let address):
                "\(address) is not paired with this Mac. Pair the earbuds in System Settings › Bluetooth."
            case .noEarbudsFound:
                "No Galaxy Buds2 are paired with this Mac. Pair them in System Settings › Bluetooth."
            case .ambiguous(let found):
                "More than one pair of Galaxy Buds2 is paired (\(found.joined(separator: ", "))). "
                    + "Choose one with --address or the \(addressEnvironmentVariable) environment variable."
            }
        }
    }

    /// Finds the earbuds to talk to.
    ///
    /// With an address (given, or in `MACBUDS_ADDRESS`) that exact device is used. Otherwise
    /// the paired devices are searched for Galaxy Buds2 by name; if several are paired, the
    /// one currently connected wins.
    @MainActor
    static func findEarbuds(address: String?) throws -> IOBluetoothDevice {
        let wanted = address ?? ProcessInfo.processInfo.environment[addressEnvironmentVariable]
        if let wanted {
            guard let device = IOBluetoothDevice(addressString: wanted), device.isPaired() else {
                throw DiscoveryError.notPaired(wanted)
            }
            return device
        }

        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let buds = paired.filter { isBuds2($0.name) }
        guard !buds.isEmpty else { throw DiscoveryError.noEarbudsFound }
        if buds.count == 1 { return buds[0] }
        let connected = buds.filter { $0.isConnected() }
        if connected.count == 1 { return connected[0] }
        throw DiscoveryError.ambiguous(buds.map { "\($0.name ?? "?") [\($0.addressString ?? "?")]" })
    }

    /// "Galaxy Buds2" and "Galaxy Buds2", but not "Galaxy Buds2 Pro" or "Galaxy Buds+":
    /// those speak different message layouts.
    static func isBuds2(_ name: String?) -> Bool {
        guard let name, name.hasPrefix("Galaxy Buds2") else { return false }
        let rest = name.dropFirst("Galaxy Buds2".count)
        return rest.isEmpty || rest.hasPrefix(" (")
    }
}
