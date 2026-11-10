import BudsProtocol
import CoreBluetooth
import Foundation
@preconcurrency import IOBluetooth

/// A live connection to the earbuds' control channel.
///
/// Owns the RFCOMM channel, turns its byte stream into frames, and keeps `state` current
/// from what the buds report. Everything runs on the main actor because IOBluetooth delivers
/// its callbacks on the main run loop and its objects are not Sendable.
///
/// This opens and closes only the control channel. It never touches the device's baseband
/// connection, so audio keeps playing.
@MainActor
public final class BudsSession: NSObject {
    /// SDP service "GEARMANAGER". docs/PROTOCOL.md §1.
    public static let controlServiceUUID = "2E73A4AD332D41FC90E216BEF06523F2"

    public enum SessionError: Error, CustomStringConvertible {
        case bluetoothDenied
        case discovery(BudsTransport.DiscoveryError)
        case notConnected(String)
        case sdpFailed(IOReturn)
        case controlServiceNotFound
        case openFailed(IOReturn)
        case channelBusy
        case timedOut(String)
        case notOpen
        case closed
        case forbiddenMessage(UInt8)
        case writeFailed(IOReturn)
        case rejected(messageID: UInt8, code: UInt8)
        case unexpectedEcho(messageID: UInt8, sent: [UInt8], echoed: [UInt8])
        case notApplied(messageID: UInt8)

        public var description: String {
            switch self {
            case .bluetoothDenied:
                "macOS is blocking Bluetooth for this app. Turn it on in System Settings › Privacy & Security › Bluetooth, then reopen the app."
            case .discovery(let error):
                error.description
            case .notConnected(let name):
                "\(name) is paired but not connected. Take the earbuds out of the case and connect them in the Bluetooth menu."
            case .sdpFailed(let r):
                "Could not query the earbuds' services (\(ioReturnHex(r)))."
            case .controlServiceNotFound:
                "The earbuds do not expose the control service — is this a Galaxy Buds2?"
            case .openFailed(let r):
                "Could not open the control channel (\(ioReturnHex(r))). Another app may be holding it — quit MacBuds.app or any other Buds manager and retry."
            case .channelBusy:
                "The control channel did not open. Another app is almost certainly holding it — the earbuds accept one at a time. Quit MacBuds.app (or any other Buds manager) and retry."
            case .timedOut(let what):
                "Timed out waiting for \(what)."
            case .notOpen:
                "Not connected to the control channel."
            case .closed:
                "The earbuds closed the control channel."
            case .forbiddenMessage(let id):
                String(format: "Refusing to send message 0x%02X: it is not on the allowlist of documented, safe messages.", id)
            case .writeFailed(let r):
                "Write to the earbuds failed (\(ioReturnHex(r)))."
            case .rejected(let id, let code):
                String(format: "The earbuds rejected message 0x%02X (result code 0x%02X).", id, code)
            case .notApplied(let id):
                String(format: "The earbuds answered message 0x%02X but kept their previous setting.", id)
            case .unexpectedEcho(let id, let sent, let echoed):
                String(format: "The earbuds acknowledged message 0x%02X with different values (sent ", id)
                    + hexBytes(sent) + ", echoed " + hexBytes(echoed) + "). The setting may not have changed."
            }
        }
    }

    /// How the buds answered a request. docs/PROTOCOL.md §4.1.
    public enum Reply: Equatable, Sendable {
        /// 0x42: the accepted parameters, echoed in the request's own layout.
        case acknowledged(echo: [UInt8])
        /// 0x51 with result code 0.
        case succeeded(extra: [UInt8])
    }

    /// The address asked for, or nil to find the earbuds automatically.
    public let requestedAddress: String?
    /// The address of the earbuds actually in use, once found.
    public private(set) var address: String?
    public private(set) var deviceName = "Galaxy Buds2"
    public private(set) var state: BudsState?
    public private(set) var version: VersionInfo?
    public private(set) var isOpen = false
    /// Every frame received, after `state` has been updated from it. For debugging.
    public var onFrame: ((Frame) -> Void)?

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var decoder = FrameStreamDecoder()

    private var sdpContinuation: CheckedContinuation<Void, any Error>?
    private var openContinuation: CheckedContinuation<Void, any Error>?
    private struct Waiter {
        let id: Int
        let offer: (Frame) -> Bool
        let fail: (any Error) -> Void
    }
    private var waiters: [Waiter] = []
    private var nextWaiterID = 0
    private var stateObservers: [Int: AsyncStream<BudsState>.Continuation] = [:]

    public init(address: String? = nil) {
        requestedAddress = address
    }

    // MARK: Connecting

    /// Finds the control service by UUID and opens its RFCOMM channel.
    public func connect(timeout: TimeInterval = 10) async throws {
        guard !isOpen else { return }
        // Without the Bluetooth permission IOBluetooth does not fail; it just reports every
        // device as unpaired. Ask the privacy system directly so the real cause is shown.
        // (.notDetermined falls through: touching the device below raises the prompt.)
        let authorization = CBManager.authorization
        guard authorization != .denied, authorization != .restricted else {
            throw SessionError.bluetoothDenied
        }
        let device: IOBluetoothDevice
        do {
            device = try BudsTransport.findEarbuds(address: requestedAddress)
        } catch let error as BudsTransport.DiscoveryError {
            throw SessionError.discovery(error)
        }
        self.device = device
        address = device.addressString
        deviceName = device.name ?? deviceName
        guard device.isConnected() else { throw SessionError.notConnected(deviceName) }

        var channelID = controlChannelID(of: device)
        if channelID == nil {
            try await querySDP(device, timeout: timeout)
            channelID = controlChannelID(of: device)
        }
        guard let channelID else { throw SessionError.controlServiceNotFound }

        // A reused session must not serve the previous connection's snapshot as current.
        decoder.reset()
        state = nil
        version = nil
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess else { throw SessionError.openFailed(result) }
        channel = opened
        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                openContinuation = c
                expire(after: timeout) { session in
                    // Seen on device: when another client holds the channel the open neither
                    // succeeds nor fails, it just never completes.
                    session.openContinuation?.resume(throwing: SessionError.channelBusy)
                    session.openContinuation = nil
                }
            }
        } catch {
            _ = opened?.close()
            channel = nil
            throw error
        }
        isOpen = true
    }

    /// Closes the control channel only; the earbuds stay connected for audio.
    public func disconnect() {
        guard let channel else { return }
        self.channel = nil
        isOpen = false
        channel.setDelegate(nil)
        _ = channel.close()
        finish(with: SessionError.closed)
    }

    private func controlChannelID(of device: IOBluetoothDevice) -> UInt8? {
        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        return records
            .first { $0.serviceClassUUIDs.contains(Self.controlServiceUUID) }?
            .rfcommChannel
    }

    private func querySDP(_ device: IOBluetoothDevice, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            let result = device.performSDPQuery(self)
            guard result == kIOReturnSuccess else {
                c.resume(throwing: SessionError.sdpFailed(result))
                return
            }
            sdpContinuation = c
            expire(after: timeout) { session in
                session.sdpContinuation?.resume(throwing: SessionError.timedOut("the service query"))
                session.sdpContinuation = nil
            }
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        if status == kIOReturnSuccess {
            sdpContinuation?.resume()
        } else {
            sdpContinuation?.resume(throwing: SessionError.sdpFailed(status))
        }
        sdpContinuation = nil
    }

    private func expire(after seconds: TimeInterval, _ action: @escaping (BudsSession) -> Void) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if let self { action(self) }
        }
    }

    // MARK: State

    /// The current snapshot, waiting for the buds' first status message if need be. They
    /// send one unprompted right after the channel opens.
    public func currentState(timeout: TimeInterval = 5) async throws -> BudsState {
        if let state { return state }
        guard isOpen else { throw SessionError.notOpen }
        try await waitForFrame("the earbuds' status", timeout: timeout) { frame in
            frame.id == MessageID.extendedStatusUpdated ? () : nil
        }
        guard let state else { throw SessionError.timedOut("the earbuds' status") }
        return state
    }

    /// Firmware and hardware revisions. The buds send these unprompted a moment after the
    /// first status; nil if they have not arrived within `timeout`.
    public func versionInfo(timeout: TimeInterval = 1) async -> VersionInfo? {
        if version == nil, isOpen {
            _ = try? await waitForFrame("version info", timeout: timeout) { frame in
                frame.id == MessageID.versionInfo ? () : nil
            }
        }
        return version
    }

    /// The current snapshot (if any) followed by every change. Ends when the channel closes.
    public func stateUpdates() -> AsyncStream<BudsState> {
        AsyncStream { continuation in
            let id = nextWaiterID
            nextWaiterID += 1
            stateObservers[id] = continuation
            if let state { continuation.yield(state) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stateObservers[id] = nil }
            }
        }
    }

    private func setState(_ new: BudsState) {
        guard new != state else { return }
        state = new
        for observer in stateObservers.values { observer.yield(new) }
    }

    // MARK: Sending

    /// Puts one frame on the wire. Refuses anything not on `MessageID.sendable`.
    public func send(_ frame: Frame) throws {
        guard MessageID.sendable.contains(frame.id) else {
            throw SessionError.forbiddenMessage(frame.id)
        }
        guard isOpen, let channel else { throw SessionError.notOpen }
        var bytes = try frame.encode()
        let result = channel.writeSync(&bytes, length: UInt16(bytes.count))
        guard result == kIOReturnSuccess else { throw SessionError.writeFailed(result) }
    }

    /// Sends a frame and waits for the buds to acknowledge (0x42) or answer (0x51) it.
    public func request(_ frame: Frame, timeout: TimeInterval = 3) async throws -> Reply {
        let id = frame.id
        let name = String(format: "a reply to message 0x%02X", id)
        let result: Result<Reply, SessionError> = try await waitForFrame(name, timeout: timeout, sending: frame) { reply in
            guard reply.payload.first == id else { return nil }
            switch reply.id {
            case MessageID.acknowledgement:
                return .success(.acknowledged(echo: Array(reply.payload.dropFirst())))
            case MessageID.response:
                let code = reply.payload.count > 1 ? reply.payload[1] : 0
                return code == 0
                    ? .success(.succeeded(extra: Array(reply.payload.dropFirst(2))))
                    : .failure(.rejected(messageID: id, code: code))
            default:
                return nil
            }
        }
        return try result.get()
    }

    /// Changes a setting: sends the command, waits for the buds to answer in whatever way
    /// that message is answered, and updates the snapshot.
    ///
    /// Throws `.unexpectedEcho` or `.notApplied` when the buds answer but did not take the
    /// requested value; the snapshot then shows what they actually report.
    public func perform(_ command: Command, timeout: TimeInterval = 3) async throws {
        let id = command.frame.id
        switch command.reply {
        case .acknowledgement:
            let reply = try await request(command.frame, timeout: timeout)
            if case .acknowledged(let echo) = reply, !echo.isEmpty {
                let sent = command.frame.payload
                guard echo.starts(with: sent) || sent.starts(with: echo) else {
                    throw SessionError.unexpectedEcho(messageID: id, sent: sent, echoed: echo)
                }
            }
            applyToState(command)

        case .noiseControlsUpdate:
            // Two answers are possible (docs/PROTOCOL.md §4.3). If the mode changes, the buds
            // acknowledge with 0x42. If it does not — already in that mode, or they refuse
            // because they are not being worn — they send 0x77 with the mode in effect,
            // which handle() has folded into `state` by the time this resumes.
            let changed = try await waitForFrame(String(format: "a reply to message 0x%02X", id), timeout: timeout, sending: command.frame) { reply -> Bool? in
                switch reply.id {
                case MessageID.acknowledgement where reply.payload.first == id: true
                case MessageID.noiseControlsUpdate: false
                default: nil
                }
            }
            if changed {
                applyToState(command)
            } else if let state, !command.isReflected(in: state) {
                throw SessionError.notApplied(messageID: id)
            }

        case .none:
            try send(command.frame)
            // No acknowledgement exists for these; give the buds a moment to act on it
            // before the caller closes the channel.
            try await Task.sleep(for: .milliseconds(300))
            applyToState(command)
        }
    }

    private func applyToState(_ command: Command) {
        guard var new = state else { return }
        command.apply(&new)
        setState(new)
    }

    /// Sends an empty-payload information request and returns the reply's payload. The buds
    /// answer these with a frame carrying the same message ID.
    public func query(_ id: UInt8, timeout: TimeInterval = 3) async throws -> [UInt8] {
        try await waitForFrame(String(format: "a reply to message 0x%02X", id), timeout: timeout, sending: Frame(id: id)) {
            $0.id == id ? $0.payload : nil
        }
    }

    /// Sends `frame` (if given) and waits for the next frame with ID `id`.
    public func waitFor(_ id: UInt8, sending frame: Frame? = nil, timeout: TimeInterval) async throws -> [UInt8] {
        try await waitForFrame(String(format: "message 0x%02X", id), timeout: timeout, sending: frame) {
            $0.id == id ? $0.payload : nil
        }
    }

    /// Suspends until `match` accepts an incoming frame. The waiter is registered before
    /// `sending` goes out, so a fast reply cannot be missed.
    @discardableResult
    private func waitForFrame<T: Sendable>(
        _ what: String,
        timeout: TimeInterval,
        sending frame: Frame? = nil,
        _ match: @escaping (Frame) -> T?
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, any Error>) in
            let id = nextWaiterID
            nextWaiterID += 1
            waiters.append(Waiter(
                id: id,
                offer: { frame in
                    guard let value = match(frame) else { return false }
                    c.resume(returning: value)
                    return true
                },
                fail: { c.resume(throwing: $0) }
            ))
            if let frame {
                do {
                    try send(frame)
                } catch {
                    removeWaiter(id)?.fail(error)
                    return
                }
            }
            expire(after: timeout) { session in
                session.removeWaiter(id)?.fail(SessionError.timedOut(what))
            }
        }
    }

    private func removeWaiter(_ id: Int) -> Waiter? {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
        return waiters.remove(at: index)
    }

    // MARK: Receiving

    private func handle(_ frame: Frame) {
        switch frame.id {
        case MessageID.extendedStatusUpdated:
            if let new = try? BudsState(extendedStatus: frame.payload) { setState(new) }
        case MessageID.statusUpdated:
            if var new = state, (try? new.apply(statusUpdate: frame.payload)) != nil { setState(new) }
        case MessageID.noiseControlsUpdate:
            if var new = state, (try? new.apply(noiseControlsUpdate: frame.payload)) != nil { setState(new) }
        case MessageID.versionInfo:
            version = try? VersionInfo(payload: frame.payload)
        default:
            break
        }
        onFrame?(frame)
        waiters.removeAll { $0.offer(frame) }
    }

    private func finish(with error: any Error) {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.fail(error) }
        for observer in stateObservers.values { observer.finish() }
        stateObservers.removeAll()
    }
}

extension BudsSession: @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            openContinuation?.resume()
        } else {
            openContinuation?.resume(throwing: SessionError.openFailed(error))
        }
        openContinuation = nil
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel === channel else { return }
        channel = nil
        isOpen = false
        finish(with: SessionError.closed)
    }

    public func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let bytes = UnsafeRawBufferPointer(start: dataPointer, count: dataLength)
        for frame in decoder.push(bytes) {
            handle(frame)
        }
    }
}
