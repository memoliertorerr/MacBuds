import Foundation
@preconcurrency import IOBluetooth

/// Debug tool: lists the device's SDP services and, optionally, opens an RFCOMM
/// channel and hex-dumps whatever arrives. It never writes to the channel.
@MainActor
public final class Probe: NSObject {
    public struct Service: Sendable {
        public let name: String
        public let uuids: [String]
        public let rfcommChannel: UInt8?
    }

    public enum ProbeError: Error, CustomStringConvertible {
        case notConnected
        case sdpFailed(IOReturn)
        case openFailed(IOReturn)
        case openTimedOut

        public var description: String {
            switch self {
            case .notConnected: "device is paired but not connected to this Mac"
            case .sdpFailed(let r): "SDP query failed: \(ioReturnHex(r))"
            case .openFailed(let r): "RFCOMM open failed: \(ioReturnHex(r))"
            case .openTimedOut: "RFCOMM open timed out"
            }
        }
    }

    private let device: IOBluetoothDevice
    private var sdpStatus: IOReturn?
    private var openStatus: IOReturn?
    private var closed = false
    private var channel: IOBluetoothRFCOMMChannel?
    private let start = Date()
    private let log: (String) -> Void

    public init(address: String?, log: @escaping (String) -> Void) throws {
        device = try BudsTransport.findEarbuds(address: address)
        self.log = log
    }

    public var deviceName: String { device.name ?? "(unnamed)" }
    public var address: String { device.addressString ?? "?" }
    public var isConnected: Bool { device.isConnected() }

    /// Runs a fresh SDP query and returns every service record.
    public func services(timeout: TimeInterval = 10) throws -> [Service] {
        sdpStatus = nil
        let r = device.performSDPQuery(self)
        guard r == kIOReturnSuccess else { throw ProbeError.sdpFailed(r) }
        spin(timeout) { self.sdpStatus != nil }
        if let s = sdpStatus, s != kIOReturnSuccess { throw ProbeError.sdpFailed(s) }

        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        return records.map { record in
            Service(
                name: record.getServiceName() ?? "(no name)",
                uuids: record.serviceClassUUIDs,
                rfcommChannel: record.rfcommChannel
            )
        }
    }

    /// Opens the given RFCOMM channel and logs inbound bytes for `seconds`.
    public func listen(channelID: UInt8, seconds: TimeInterval) throws {
        guard device.isConnected() else { throw ProbeError.notConnected }
        var ch: IOBluetoothRFCOMMChannel?
        let r = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        guard r == kIOReturnSuccess else { throw ProbeError.openFailed(r) }
        channel = ch
        spin(10) { self.openStatus != nil }
        guard let status = openStatus else { throw ProbeError.openTimedOut }
        guard status == kIOReturnSuccess else { throw ProbeError.openFailed(status) }
        log("channel \(channelID) open, mtu \(ch?.getMTU() ?? 0); listening \(Int(seconds))s")
        spin(seconds) { self.closed }
        if closed { log("channel closed by remote") }
        _ = ch?.close()
    }

    private func spin(_ timeout: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        sdpStatus = status
    }
}

extension Probe: @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openStatus = error
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        closed = true
    }

    public func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let bytes = UnsafeRawBufferPointer(start: dataPointer, count: dataLength)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        log(String(format: "+%.3fs rx %3d: %@", Date().timeIntervalSince(start), dataLength, hex))
    }
}
