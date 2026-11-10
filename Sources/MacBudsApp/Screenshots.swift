import AppKit
import BudsProtocol
import SwiftUI

/// Renders the popover offscreen with sample data. Hosting the view in a real (never shown)
/// window makes the AppKit-backed controls draw properly, and needs no screen-recording
/// permission.
@MainActor
enum Screenshots {
    /// A Buds2 revision-10 extended status: both worn, noise cancelling on, EQ dynamic.
    private static let samplePayload: [UInt8] = [
        0x0A, 0x03, 82, 85, 0x01, 0x00, 0x11, 64, 0x00, 0x03, 0xBF, 0x22, 0x01, 0x00,
        0x3A, 0x01, 0x3A, 0x01, 0x00, 0x00, 0x03, 0x66, 0x00, 0x01, 0x00, 0x10, 0x00,
        0x00, 0x00, 0x01, 0x11, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    private struct Shot {
        let name: String
        let dark: Bool
        let expanded: [String]
    }

    private static let groups = ["Noise control options", "Sound", "Touch controls", "Calls and connection", "Tools"]

    static func render(into directory: String) {
        guard let state = try? BudsState(extendedStatus: samplePayload),
              let version = try? VersionInfo(payload: [0x00, 0x00, 0x01, 0x81, 0x01, 0x01, 0x81, 0x01, 0x00, 0x00])
        else {
            print("sample data did not decode")
            exit(1)
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let shots = [
            Shot(name: "popover-dark", dark: true, expanded: []),
            Shot(name: "popover-light", dark: false, expanded: []),
            Shot(name: "popover-sound-dark", dark: true, expanded: ["Sound", "Calls and connection"]),
            Shot(name: "popover-touch-dark", dark: true, expanded: ["Touch controls"]),
        ]
        for shot in shots {
            for group in groups {
                UserDefaults.standard.set(shot.expanded.contains(group), forKey: "section.\(group)")
            }
            let model = BudsViewModel(sample: state, version: version)
            let path = "\(directory)/\(shot.name).png"
            if let png = capture(PopoverView(model: model), dark: shot.dark) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("wrote \(path)")
            } else {
                print("failed \(path)")
            }
        }
        for group in groups {
            UserDefaults.standard.removeObject(forKey: "section.\(group)")
        }
    }

    private static func capture(_ view: some View, dark: Bool) -> Data? {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let content = view
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: content)
        host.appearance = appearance

        let window = KeyableWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 340, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        // Key, so controls draw in their active colours rather than the greyed inactive look.
        window.makeKeyAndOrderFront(nil)

        // Let SwiftUI lay out, including the measured height of the settings groups.
        for _ in 0..<6 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
            window.setContentSize(host.fittingSize)
        }

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        window.orderOut(nil)
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// A borderless window refuses key status by default.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
