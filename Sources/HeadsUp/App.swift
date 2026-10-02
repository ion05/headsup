import SwiftUI

@main
struct HeadsUpApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // MenuBarExtra must stay first so the settings Window isn't auto-opened at launch.
        MenuBarExtra {
            MenuContent()
        } label: {
            MenuBarIcon()
        }
        .menuBarExtraStyle(.menu)

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

    var body: some View {
        // eye.slash, not bell.slash: alerts still fire, only details are hidden.
        Image(systemName: engine.hidingDetails ? "eye.slash.fill" : "bell.fill")
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

private struct MenuContent: View {
    @ObservedObject private var engine = Engine.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !engine.hasAccess {
            Button("Calendar access needed…", action: openSettings)
        } else if engine.upcoming.isEmpty {
            Text("No upcoming events")
        } else {
            ForEach(engine.upcoming.prefix(5)) { alert in
                let label = "\(alert.start.formatted(date: .omitted, time: .shortened))  \(alert.title)"
                Menu {
                    if let url = alert.joinURL {
                        Button("Join") { NSWorkspace.shared.open(url) }
                    }
                    Toggle("Private", isOn: Binding(get: { engine.privateItems.contains(alert.itemID) }, set: { engine.setPrivate(alert.itemID, $0) }))
                } label: {
                    if alert.isPrivate { Label(label, systemImage: "lock.fill") } else { Text(label) }
                }
            }
        }

        Divider()
        Toggle("Hide Event Details", isOn: $engine.hideAllDetails)
        Button("Test Alert") { engine.testAlert() }
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Divider()
        Button("Quit HeadsUp") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openSettings() {
        openWindow(id: "settings")
        // Accessory (LSUIElement) apps aren't active, so the window would open behind others.
        NSApp.activate(ignoringOtherApps: true)
    }
}
