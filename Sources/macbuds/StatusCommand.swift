import ArgumentParser
import BudsProtocol
import BudsTransport
import Foundation

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show battery, placement and every setting the earbuds report."
    )

    @Option(help: "Bluetooth address of the earbuds. Only needed when several Galaxy Buds2 are paired; MACBUDS_ADDRESS works too.")
    var address: String?

    @Flag(help: "Print JSON instead of text.")
    var json = false

    @Flag(help: "Keep running and print a line whenever something changes.")
    var watch = false

    @Option(help: "With --watch: stop after this many seconds (default: run until interrupted).")
    var seconds: Double?

    @MainActor
    func run() async throws {
        let session = BudsSession(address: address)
        try await session.connect()
        defer { session.disconnect() }
        let state = try await session.currentState()

        if watch {
            try await runWatch(session)
            return
        }
        let version = await session.versionInfo()
        if json {
            print(try Self.json(Report(device: session.deviceName, address: session.address ?? "", version: version, state: state)))
        } else {
            print(Self.text(state, device: session.deviceName, version: version))
        }
    }

    @MainActor
    private func runWatch(_ session: BudsSession) async throws {
        if let seconds {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                session.disconnect()
            }
        }
        var previous: BudsState?
        for await state in session.stateUpdates() {
            let stamp = Date().formatted(date: .omitted, time: .standard)
            if json {
                print(try Self.json(state, pretty: false))
            } else if let previous {
                print("\(stamp)  \(Self.changes(from: previous, to: state))")
            } else {
                print("\(stamp)  \(Self.summary(state))")
            }
            previous = state
        }
    }

    struct Report: Encodable {
        let device: String
        let address: String
        let version: VersionInfo?
        let state: BudsState
    }

    static func json(_ value: some Encodable, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func summary(_ s: BudsState) -> String {
        "battery L \(s.batteryLeft)% R \(s.batteryRight)% case \(caseBattery(s)) | "
            + "left \(s.placementLeft), right \(s.placementRight) | noise \(s.noiseControl)"
    }

    /// One line naming only what differs, compared through the JSON form so new fields are
    /// picked up without touching this function.
    static func changes(from old: BudsState, to new: BudsState) -> String {
        func fields(_ s: BudsState) -> [String: String] {
            guard let data = try? JSONEncoder().encode(s),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            return object.mapValues { "\($0)" }
        }
        let before = fields(old), after = fields(new)
        let changed = after.keys.sorted().filter { before[$0] != after[$0] }
        return changed.map { "\($0): \(before[$0] ?? "-") → \(after[$0] ?? "-")" }.joined(separator: ", ")
    }

    static func caseBattery(_ s: BudsState) -> String {
        s.caseBatteryKnown ? "\(s.batteryCase)%" : "n/a"
    }

    static func text(_ s: BudsState, device: String, version: VersionInfo?) -> String {
        func onOff(_ value: Bool?) -> String {
            switch value {
            case true?: "on"
            case false?: "off"
            case nil: "not reported"
            }
        }
        func charging(_ flag: Bool) -> String { flag ? " (charging)" : "" }

        var rows: [(String, String)] = []
        rows.append(("Device", device))
        if let version {
            let fw = version.firmwareLeft == version.firmwareRight
                ? version.firmwareLeft
                : "left \(version.firmwareLeft), right \(version.firmwareRight)"
            rows.append(("Firmware", fw))
        }
        rows.append(("Battery", "left \(s.batteryLeft)%\(charging(s.chargingLeft)), "
            + "right \(s.batteryRight)%\(charging(s.chargingRight)), "
            + "case \(caseBattery(s))\(charging(s.chargingCase))"))
        rows.append(("Placement", "left \(s.placementLeft), right \(s.placementRight) (primary: \(s.primary.rawValue))"))
        rows.append(("Noise control", "\(s.noiseControl)"))
        rows.append(("Ambient level", "\(s.ambientLevel)"))
        rows.append(("One-earbud noise control", onOff(s.noiseControlWithOneEarbud)))
        rows.append(("Touch noise cycle", "left \(s.noiseCycleLeft), right \(s.noiseCycleRight)"))
        if let custom = s.customAmbient {
            rows.append(("Custom ambient", custom.enabled
                ? "on (left \(custom.leftLevel), right \(custom.rightLevel), tone \(custom.tone))"
                : "off"))
        }
        rows.append(("ANC level (experimental)", s.noiseReductionLevel == 0 ? "low" : (s.noiseReductionLevel == 1 ? "high" : "\(s.noiseReductionLevel)")))
        rows.append(("Equalizer", "\(s.equalizer)"))
        rows.append(("Balance", "\(s.balance) (0–32, 16 is centre)"))
        rows.append(("Touch controls", s.touch.enabled ? "enabled" : "locked"))
        let gestures: [(String, Bool)] = [
            ("single tap", s.touch.singleTap), ("double tap", s.touch.doubleTap),
            ("triple tap", s.touch.tripleTap), ("touch and hold", s.touch.touchAndHold),
            ("double tap in call", s.touch.doubleTapInCall),
            ("touch and hold in call", s.touch.touchAndHoldInCall),
        ]
        let disabled = gestures.filter { !$0.1 }.map(\.0)
        rows.append(("Gestures", disabled.isEmpty ? "all enabled" : "disabled: " + disabled.joined(separator: ", ")))
        rows.append(("Touch and hold", "left \(s.holdActionLeft), right \(s.holdActionRight)"))
        rows.append(("Double-tap edge volume", onOff(s.doubleTapEdgeVolume)))
        rows.append(("Seamless connection", onOff(s.seamlessConnection)))
        rows.append(("In-ear detection for calls", onOff(s.inEarDetectionForCalls)))
        rows.append(("Ambient sound during calls", onOff(s.ambientDuringCalls)))

        let width = rows.map(\.0.count).max() ?? 0
        return rows
            .map { $0.0.padding(toLength: width + 2, withPad: " ", startingAt: 0) + $0.1 }
            .joined(separator: "\n")
    }
}
