import BudsProtocol
import ServiceManagement
import SwiftUI

struct PopoverView: View {
    let model: BudsViewModel
    /// Natural height of the settings groups, measured so the scroll area is exactly as
    /// tall as its content until it reaches the cap. A bare ScrollView has no height of its
    /// own, and a menu bar window sizes itself to fit — which squeezes it to a sliver.
    @State private var settingsHeight: CGFloat = 0
    private static let maxSettingsHeight: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let state = model.state, model.isConnected {
                BatteryRow(state: state)
                NoiseControlSection(model: model, state: state)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        AmbientSection(model: model, state: state)
                        SoundSection(model: model, state: state)
                        TouchSection(model: model, state: state)
                        CallsSection(model: model, state: state)
                        ToolsSection(model: model, state: state)
                    }
                    .padding(.trailing, 6)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { settingsHeight = $0 }
                }
                .frame(height: min(max(settingsHeight, 1), Self.maxSettingsHeight))
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                LaunchAtLoginToggle()
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model.deviceName).font(.headline)
            Spacer(minLength: 8)
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(model.connection.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One compact line: Left 35%  Right 99%  Case 40%.
struct BatteryRow: View {
    let state: BudsState

    var body: some View {
        HStack(spacing: 0) {
            cell("Left", present: state.placementLeft.byte != 0, percent: state.batteryLeft, charging: state.chargingLeft)
            cell("Right", present: state.placementRight.byte != 0, percent: state.batteryRight, charging: state.chargingRight)
            cell("Case", present: state.caseBatteryKnown, percent: state.batteryCase, charging: state.chargingCase)
        }
    }

    private func cell(_ title: String, present: Bool, percent: Int, charging: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(present ? "\(percent)%" : "—")
                .font(.body.weight(.medium).monospacedDigit())
            if charging {
                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(present ? "\(title) battery \(percent) percent\(charging ? ", charging" : "")" : "\(title) battery unavailable")
    }
}

struct NoiseControlSection: View {
    let model: BudsViewModel
    let state: BudsState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Noise control", selection: Binding(
                get: { state.noiseControl },
                set: { mode in model.apply { try .noiseControl(mode) } }
            )) {
                Text("Off").tag(NoiseControlMode.off)
                Text("Ambient").tag(NoiseControlMode.ambient)
                Text("Noise cancelling").tag(NoiseControlMode.anc)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if state.noiseControl == .ambient {
                SettingRow("Ambient level") {
                    Picker("Ambient level", selection: Binding(
                        get: { state.ambientLevel },
                        set: { level in model.apply { try .ambientLevel(level) } }
                    )) {
                        Text("Low").tag(0)
                        Text("Medium").tag(1)
                        Text("High").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
        }
    }
}

/// Registers the app as a login item. macOS only honours this for a bundled app, and keeps
/// pointing at wherever that bundle was when it was registered — so install it to
/// /Applications first (scripts/bundle.sh --install).
struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var failure: String?

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { on in
                do {
                    if on {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    failure = nil
                } catch {
                    failure = error.localizedDescription
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .help(failure ?? "Start MacBuds when you log in. Install the app to /Applications first.")
    }
}
