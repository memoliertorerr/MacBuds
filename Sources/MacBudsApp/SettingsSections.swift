import BudsProtocol
import SwiftUI

// MARK: Building blocks

/// A collapsible group that remembers whether it was open.
struct SettingsGroup<Content: View>: View {
    let title: String
    @AppStorage private var expanded: Bool
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        _expanded = AppStorage(wrappedValue: false, "section.\(title)")
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.top, 6)
                .padding(.leading, 2)
        } label: {
            Text(title).font(.subheadline.weight(.medium))
        }
    }
}

/// A label on the left and its control pushed to the right edge.
struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            control
        }
    }
}

/// A switch for a setting the buds may not report at all on older firmware.
struct SettingToggle: View {
    let title: String
    var caption: String?
    let value: Bool?
    let change: @MainActor (Bool) -> Void

    var body: some View {
        if let value {
            VStack(alignment: .leading, spacing: 1) {
                Toggle(isOn: Binding(get: { value }, set: { new in change(new) })) {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private let levelNames = ["Low", "Medium", "High"]

// MARK: Ambient sound

struct AmbientSection: View {
    let model: BudsViewModel
    let state: BudsState

    var body: some View {
        SettingsGroup("Noise control options") {
            SettingToggle(
                title: "High noise cancelling level",
                caption: "Experimental. A Buds Pro setting that Buds2 accept and remember; it may or may not sound different.",
                value: state.noiseReductionLevel == 1
            ) { on in model.apply { .noiseReductionLevel(high: on) } }

            SettingToggle(
                title: "Noise control with one earbud",
                caption: "Otherwise noise control switches off when you take one earbud out.",
                value: state.noiseControlWithOneEarbud
            ) { on in model.apply { .noiseControlWithOneEarbud(on) } }

            if let custom = state.customAmbient {
                SettingToggle(title: "Customize ambient sound", value: custom.enabled) { on in
                    update(custom) { $0.enabled = on }
                }
                if custom.enabled {
                    levelPicker("Left", value: custom.leftLevel) { level in update(custom) { $0.leftLevel = level } }
                    levelPicker("Right", value: custom.rightLevel) { level in update(custom) { $0.rightLevel = level } }
                    SettingRow("Tone") {
                        Picker("Tone", selection: Binding(
                            get: { custom.tone },
                            set: { tone in update(custom) { $0.tone = tone } }
                        )) {
                            Text("Soft").tag(0)
                            Text("·").tag(1)
                            Text("Neutral").tag(2)
                            Text("·").tag(3)
                            Text("Clear").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 210)
                    }
                }
            }
        }
    }

    private func update(_ current: CustomAmbient, _ change: (inout CustomAmbient) -> Void) {
        var new = current
        change(&new)
        model.apply { try .customAmbient(new) }
    }

    private func levelPicker(_ title: String, value: Int, change: @escaping @MainActor (Int) -> Void) -> some View {
        SettingRow(title) {
            Picker(title, selection: Binding(get: { value }, set: { new in change(new) })) {
                ForEach(0..<3, id: \.self) { Text(levelNames[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }
    }
}

// MARK: Sound

struct SoundSection: View {
    let model: BudsViewModel
    let state: BudsState
    @State private var balanceDraft: Double = 16

    private static let presetNames: [UInt8: String] = [
        0: "Normal", 1: "Bass boost", 2: "Soft", 3: "Dynamic", 4: "Clear", 5: "Treble boost",
    ]

    var body: some View {
        SettingsGroup("Sound") {
            SettingRow("Equalizer") {
                Picker("Equalizer", selection: Binding(
                    get: { state.equalizer },
                    set: { preset in model.apply { try .equalizer(preset) } }
                )) {
                    ForEach(Self.presetNames.keys.sorted(), id: \.self) { byte in
                        Text(Self.presetNames[byte] ?? "").tag(EqualizerPreset(byte: byte))
                    }
                    if Self.presetNames[state.equalizer.byte] == nil {
                        Text(state.equalizer.description).tag(state.equalizer)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Balance")
                    Spacer()
                    Text(balanceLabel).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 6) {
                    Text("L").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $balanceDraft, in: 0...32, step: 1) { editing in
                        if !editing {
                            let value = Int(balanceDraft)
                            if value != state.balance { model.apply { try .balance(value) } }
                        }
                    }
                    .accessibilityLabel("Balance")
                    Text("R").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear { balanceDraft = Double(state.balance) }
            .onChange(of: state.balance) { _, new in balanceDraft = Double(new) }
        }
    }

    private var balanceLabel: String {
        let offset = Int(balanceDraft) - 16
        return offset == 0 ? "Centre" : (offset < 0 ? "L \(-offset)" : "R \(offset)")
    }
}

// MARK: Touch

struct TouchSection: View {
    let model: BudsViewModel
    let state: BudsState

    private static let actionNames: [UInt8: String] = [
        1: "Voice assistant", 2: "Switch noise control", 3: "Volume down / up", 4: "Spotify",
    ]
    private static let noiseControl = TouchHoldAction(byte: 2)
    private static let volume = TouchHoldAction(byte: 3)
    private static let cycles: [(String, NoiseCycle)] = [
        ("Cancelling ↔ Ambient", NoiseCycle(anc: true, ambient: true, off: false)),
        ("Cancelling ↔ Off", NoiseCycle(anc: true, ambient: false, off: true)),
        ("Ambient ↔ Off", NoiseCycle(anc: false, ambient: true, off: true)),
    ]

    var body: some View {
        SettingsGroup("Touch controls") {
            SettingToggle(title: "Lock touch controls", value: !state.touch.enabled) { locked in
                updateTouch { $0.enabled = !locked }
            }

            Group {
                gesture("Single tap", \.singleTap)
                gesture("Double tap", \.doubleTap)
                gesture("Triple tap", \.tripleTap)
                gesture("Touch and hold", \.touchAndHold)
                gesture("Double tap during calls", \.doubleTapInCall)
                gesture("Touch and hold during calls", \.touchAndHoldInCall)
            }
            .disabled(!state.touch.enabled)

            Divider()
            Text("Touch and hold").font(.caption).foregroundStyle(.secondary)
            actionPicker("Left", current: state.holdActionLeft) { setHold(left: $0, right: nil) }
            if state.holdActionLeft == Self.noiseControl {
                cyclePicker("Left switches", current: state.noiseCycleLeft) { cycle in
                    model.apply { try .touchNoiseCycle(left: cycle, right: state.noiseCycleRight) }
                }
            }
            actionPicker("Right", current: state.holdActionRight) { setHold(left: nil, right: $0) }
            if state.holdActionRight == Self.noiseControl {
                cyclePicker("Right switches", current: state.noiseCycleRight) { cycle in
                    model.apply { try .touchNoiseCycle(left: state.noiseCycleLeft, right: cycle) }
                }
            }

            Divider()
            SettingToggle(
                title: "Double-tap earbud edge for volume",
                caption: "Labs feature: tap the edge of the left earbud for down, right for up.",
                value: state.doubleTapEdgeVolume
            ) { on in model.apply { .doubleTapEdgeVolume(on) } }
        }
    }

    private func updateTouch(_ change: (inout TouchSettings) -> Void) {
        var touch = state.touch
        change(&touch)
        model.apply { .touch(touch) }
    }

    private func gesture(_ title: String, _ keyPath: WritableKeyPath<TouchSettings, Bool>) -> some View {
        SettingToggle(title: title, value: state.touch[keyPath: keyPath]) { on in
            updateTouch { $0[keyPath: keyPath] = on }
        }
    }

    /// Volume is a pair — left down, right up — so choosing it on one side sets both, and
    /// choosing something else while both are volume moves the other side off volume too.
    private func setHold(left: TouchHoldAction?, right: TouchHoldAction?) {
        var l = left ?? state.holdActionLeft
        var r = right ?? state.holdActionRight
        let chosen = left ?? right
        if chosen == Self.volume {
            l = Self.volume
            r = Self.volume
        } else {
            if left == nil, l == Self.volume { l = Self.noiseControl }
            if right == nil, r == Self.volume { r = Self.noiseControl }
        }
        model.apply { try .touchAndHold(left: l, right: r) }
    }

    private func actionPicker(_ title: String, current: TouchHoldAction, change: @escaping @MainActor (TouchHoldAction) -> Void) -> some View {
        SettingRow(title) {
            Picker(title, selection: Binding(get: { current }, set: { new in change(new) })) {
                ForEach(Self.actionNames.keys.sorted(), id: \.self) { byte in
                    Text(Self.actionNames[byte] ?? "").tag(TouchHoldAction(byte: byte))
                }
                if Self.actionNames[current.byte] == nil {
                    Text(current.description).tag(current)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private func cyclePicker(_ title: String, current: NoiseCycle, change: @escaping @MainActor (NoiseCycle) -> Void) -> some View {
        SettingRow(title) {
            Picker(title, selection: Binding(get: { current }, set: { new in change(new) })) {
                ForEach(Self.cycles, id: \.1) { Text($0.0).tag($0.1) }
                if !Self.cycles.contains(where: { $0.1 == current }) {
                    Text(current.description).tag(current)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .font(.callout)
    }
}

// MARK: Calls and connection

struct CallsSection: View {
    let model: BudsViewModel
    let state: BudsState

    var body: some View {
        SettingsGroup("Calls and connection") {
            SettingToggle(
                title: "In-ear detection for calls",
                caption: "Calls play through the earbuds only while they are in your ears.",
                value: state.inEarDetectionForCalls
            ) { on in model.apply { .inEarDetectionForCalls(on) } }

            SettingToggle(
                title: "Ambient sound during calls",
                caption: "Hear your own voice while on a call.",
                value: state.ambientDuringCalls
            ) { on in model.apply { .ambientDuringCalls(on) } }

            SettingToggle(
                title: "Seamless earbud connection",
                caption: "Lets the earbuds switch between your devices without re-pairing.",
                value: state.seamlessConnection
            ) { on in model.apply { .seamlessConnection(on) } }
        }
    }
}

// MARK: Tools

struct ToolsSection: View {
    let model: BudsViewModel
    let state: BudsState

    private var worn: Bool {
        state.placementLeft == .wearing || state.placementRight == .wearing
    }
    private var bothWorn: Bool {
        state.placementLeft == .wearing && state.placementRight == .wearing
    }

    var body: some View {
        SettingsGroup("Tools") {
            HStack {
                Text("Find my earbuds")
                Spacer()
                Button(model.isFinding ? "Stop" : "Start") {
                    model.isFinding ? model.stopFinding() : model.startFinding()
                }
            }
            if model.isFinding {
                Text("Beeping. Stops by itself after 30 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if worn {
                Label("An earbud is in your ear. The beep is loud — take it out first.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Earbud fit test")
                Spacer()
                if model.isTestingFit { ProgressView().controlSize(.small) }
                Button("Test") { model.runFitTest() }
                    .disabled(!bothWorn || model.isTestingFit)
            }
            if let result = model.fitResult {
                Text(result).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !bothWorn {
                Text("Put both earbuds in your ears to run the test.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let version = model.version {
                Divider()
                SettingRow("Firmware") {
                    Text(version.firmwareLeft == version.firmwareRight
                        ? version.firmwareLeft
                        : "L \(version.firmwareLeft) · R \(version.firmwareRight)")
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
        }
    }
}
