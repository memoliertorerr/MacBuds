import SwiftUI

@main
enum Main {
    static func main() {
        // `MacBuds --render-screenshots <dir>` draws the popover with sample data into PNG
        // files and exits, without touching Bluetooth. Used for the README images.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-screenshots"), flag + 1 < arguments.count {
            MainActor.assumeIsolated { Screenshots.render(into: arguments[flag + 1]) }
            return
        }
        MacBudsApp.main()
    }
}

struct MacBudsApp: App {
    @State private var model = BudsViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(systemName: "earbuds")
            if let battery = model.menuBarBattery {
                Text("\(battery)%")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
