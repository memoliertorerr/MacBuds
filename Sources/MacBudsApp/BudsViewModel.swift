import BudsProtocol
import BudsTransport
import Observation
import OSLog
import SwiftUI

/// `log stream --predicate 'subsystem == "dev.memoli.macbuds"'` shows connection changes
/// and failed setting changes.
private let log = Logger(subsystem: "dev.memoli.macbuds", category: "session")

/// What the popover shows and does. Wraps one `BudsSession`, keeps it connected, and turns
/// control changes into commands. Controls read `state`, which only changes once the buds
/// accept a command — so a rejected change snaps the control back by itself.
@MainActor
@Observable
final class BudsViewModel {
    enum Connection: Equatable {
        case connecting
        case connected
        /// The earbuds are not connected to this Mac (in the case, or on another device).
        case earbudsAway
        /// Something else holds the control channel.
        case busy
        case failed(String)

        var label: String {
            switch self {
            case .connecting: "Connecting…"
            case .connected: "Connected"
            case .earbudsAway: "Earbuds not connected to this Mac"
            case .busy: "Control channel in use by another app"
            case .failed(let message): message
            }
        }
    }

    private(set) var connection: Connection = .connecting {
        didSet {
            guard connection != oldValue else { return }
            log.notice("connection: \(self.connection.label, privacy: .public)")
            // Also on stdout, readable with `open --stdout <file> dist/MacBuds.app`.
            print("connection: \(connection.label)")
            fflush(stdout)
        }
    }
    private(set) var state: BudsState?
    private(set) var version: VersionInfo?
    private(set) var deviceName = "Galaxy Buds2"
    /// The last failed change, shown inline until the next successful one.
    private(set) var errorMessage: String? {
        didSet {
            if let errorMessage { log.error("\(errorMessage, privacy: .public)") }
        }
    }
    private(set) var isFinding = false
    private(set) var isTestingFit = false
    private(set) var fitResult: String?

    private let session = BudsSession()
    private var connectionLoop: Task<Void, Never>?
    private var findTimeout: Task<Void, Never>?

    /// Seconds between attempts while the earbuds are away. Checking is cheap: it asks macOS
    /// whether the device is connected and only opens the channel when it is.
    private static let retryInterval: Duration = .seconds(4)
    static let findDuration: Duration = .seconds(30)

    /// A model showing fixed sample data, never connecting. For screenshots and previews.
    init(sample state: BudsState, version: VersionInfo?) {
        self.state = state
        self.version = version
        connection = .connected
    }

    init() {
        session.onFrame = { [weak self] frame in
            // The earbuds report it when the search is ended on the buds themselves.
            if frame.id == MessageID.findMyEarbudsStop { self?.findEnded() }
        }
        connectionLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.connectAndFollow()
                try? await Task.sleep(for: Self.retryInterval)
            }
        }
    }

    var isConnected: Bool { connection == .connected }

    /// Lowest charge among the earbuds that are present, for the menu bar.
    var menuBarBattery: Int? {
        guard isConnected, let state else { return nil }
        let present = [
            (state.placementLeft, state.batteryLeft),
            (state.placementRight, state.batteryRight),
        ].filter { $0.0.byte != 0 }.map(\.1)
        return present.min()
    }

    // MARK: Connection

    /// One connection's lifetime: connect, mirror state until the channel closes.
    private func connectAndFollow() async {
        do {
            try await session.connect()
            deviceName = session.deviceName
            state = try await session.currentState()
            connection = .connected
            errorMessage = nil
            Task { [weak self] in
                let version = await self?.session.versionInfo()
                self?.version = version
            }
            for await new in session.stateUpdates() {
                state = new
            }
            // The stream ends when the channel closes (earbuds docked, out of range, …).
            connection = .earbudsAway
            findEnded()
            isTestingFit = false
        } catch let error as BudsSession.SessionError {
            session.disconnect()
            switch error {
            case .notConnected: connection = .earbudsAway
            case .bluetoothDenied: connection = .failed(error.description)
            case .openFailed, .channelBusy: connection = .busy
            default: connection = .failed(error.description)
            }
        } catch {
            session.disconnect()
            connection = .failed("\(error)")
        }
    }

    // MARK: Settings

    /// Sends a setting change. `make` may throw for an invalid value.
    func apply(_ make: () throws -> Command) {
        let command: Command
        do {
            command = try make()
        } catch {
            errorMessage = "\(error)"
            return
        }
        Task {
            do {
                try await session.perform(command)
                errorMessage = nil
            } catch BudsSession.SessionError.notApplied where command.frame.id == MessageID.noiseControls {
                errorMessage = "Noise control only works while the earbuds are in your ears."
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    // MARK: Find my earbuds

    func startFinding() {
        guard let state, isConnected else { return }
        let worn = state.placementLeft == .wearing || state.placementRight == .wearing
        let id = worn ? MessageID.findMyEarbudsOnWearingStart : MessageID.findMyEarbudsStart
        do {
            try session.send(Frame(id: id))
            isFinding = true
            errorMessage = nil
            findTimeout = Task { [weak self] in
                try? await Task.sleep(for: Self.findDuration)
                if !Task.isCancelled { self?.stopFinding() }
            }
        } catch {
            errorMessage = "\(error)"
        }
    }

    func stopFinding() {
        guard isFinding else { return }
        try? session.send(Frame(id: MessageID.findMyEarbudsStop))
        findEnded()
    }

    private func findEnded() {
        findTimeout?.cancel()
        findTimeout = nil
        isFinding = false
    }

    // MARK: Fit test

    func runFitTest() {
        guard isConnected, !isTestingFit else { return }
        isTestingFit = true
        fitResult = nil
        Task {
            defer { isTestingFit = false }
            let start = Frame(id: MessageID.checkFit, payload: [0x01])
            let stop = Frame(id: MessageID.checkFit, payload: [0x00])
            do {
                let result = try await session.waitFor(MessageID.checkFitResult, sending: start, timeout: 20)
                try? session.send(stop)
                guard result.count >= 2 else {
                    fitResult = "The earbuds sent a result this app cannot read."
                    return
                }
                fitResult = "Left: \(FitResult(byte: result[0])) · Right: \(FitResult(byte: result[1]))"
            } catch {
                if session.isOpen { try? session.send(stop) }
                fitResult = "\(error)"
            }
        }
    }
}
