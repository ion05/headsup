import Combine
import SwiftUI

@main
struct HeadsUpApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // MenuBarExtra must stay first so the settings Window isn't auto-opened at launch.
        MenuBarExtra {
            MenuPanel()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)

        Window("HeadsUp Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 560, height: 640)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Engine.shared.onFire = { Overlay.show($0) }
            Engine.shared.start()
        }
    }
}

/// The status item label is the only view rendered at launch, so it's where we get an
/// openWindow action for the first-run settings window.
private struct MenuBarIcon: View {
    @ObservedObject private var engine = Engine.shared
    @Environment(\.openWindow) private var openWindow
    /// The engine only republishes when events change, so the countdown needs its own clock.
    @State private var now = Date()
    private let clock = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            // eye.slash, not bell.slash: alerts still fire, only details are hidden.
            Image(systemName: engine.hidingDetails ? "eye.slash.fill" : "bell.fill")
            if let text = menuBarText(events: engine.upcoming, now: now, hideDetails: engine.hidingDetails) {
                Text(text)
            }
        }
        .onReceive(clock) { now = $0 }
        .onAppear {
            guard !UserDefaults.standard.bool(forKey: "didFirstLaunch") else { return }
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            DispatchQueue.main.async {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
