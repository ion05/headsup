import SwiftUI
import EventKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var engine = Engine.shared
    @ObservedObject private var wifi = WiFiWatcher.shared
    @State private var openAtLogin = false
    @State private var loginMessage: String?

    /// Calendars grouped by account (sourceIdentifier), sorted by the name shown.
    private var groups: [(id: String, name: String, kind: String, calendars: [EKCalendar])] {
        Dictionary(grouping: engine.calendars) { $0.source?.sourceIdentifier ?? "" }
            .map { id, cals in
                let kind = cals.first?.source?.title ?? "Other"
                return (id, engine.accountNames[id] ?? kind, kind, cals)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                if !engine.hasAccess { accessBanner }

                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.secondary)
                }

                LabeledContent("See what an alert looks like") {
                    Button("Send test alert") { engine.testAlert() }
                }
            } header: {
                header
            }

            Section("Auto-hide on untrusted Wi-Fi") {
                Toggle("Hide event details when not on a trusted Wi-Fi", isOn: $wifi.autoHide)
                if wifi.autoHide { wifiRows }
            }

            Section {
                Label("Missing a Google calendar? In Calendar → Settings → Accounts → Google → Delegation, turn it on and it'll appear here.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(groups, id: \.id) { group in
                let on = !engine.offAccounts.contains(group.id)
                Section {
                    ForEach(group.calendars, id: \.calendarIdentifier) { CalendarRow(calendar: $0) }
                        .disabled(!on)
                        .opacity(on ? 1 : 0.4)
                } header: {
                    Toggle(isOn: Binding(get: { on }, set: { engine.setAccount(group.id, on: $0) })) {
                        HStack(spacing: 6) {
                            Text(group.name).textCase(nil)
                            if group.name != group.kind {
                                Text(group.kind).textCase(nil).foregroundStyle(.tertiary)
                            }
                        }
                    }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Turn off every calendar in this account")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { refreshLoginStatus() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white, Color.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("HeadsUp").font(.title2.bold()).foregroundStyle(.primary)
                Text("Full-screen reminders, right before your events start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 12)
    }

    private var accessBanner: some View {
        banner("calendar.badge.exclamationmark", "Calendar access needed",
               "HeadsUp can't see your events yet. Allow full calendar access in System Settings → Privacy & Security → Calendars, then come back here.",
               pane: "Privacy_Calendars")
    }

    @ViewBuilder private var wifiRows: some View {
        if wifi.denied { locationBanner }

        LabeledContent {
            Button("Trust this network") { wifi.trustCurrent() }
                .disabled(wifi.ssid.map(wifi.trusted.contains) ?? true)
        } label: {
            if let ssid = wifi.ssid {
                Label("Connected to \(ssid)", systemImage: "wifi")
            } else if wifi.authorized {
                Label("Not on Wi-Fi", systemImage: "wifi.slash")
            } else {
                Label("Network name unavailable", systemImage: "wifi.exclamationmark")
            }
        }

        if wifi.trusted.isEmpty {
            Text("No trusted networks yet. Connect to one you trust, like home, and tap Trust this network.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        ForEach(wifi.trusted, id: \.self) { name in
            HStack {
                Label(name, systemImage: name == wifi.ssid ? "checkmark.shield.fill" : "checkmark.shield")
                Spacer()
                Button { wifi.remove(name) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop trusting \(name)")
                .accessibilityLabel("Stop trusting \(name)")
            }
        }

        Label(engine.offTrustedWiFi ? "Details are hidden right now" : "Details are shown on this network",
              systemImage: engine.offTrustedWiFi ? "eye.slash" : "eye")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var locationBanner: some View {
        banner("location.slash.fill", "Location access needed",
               "macOS only shares the Wi-Fi name with apps that have Location access. Until you allow it, HeadsUp can't tell where you are, so it hides details in every alert.",
               pane: "Privacy_LocationServices")
    }

    /// Orange warning with a button to the given Privacy & Security pane.
    private func banner(_ icon: String, _ title: String, _ text: String, pane: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch {
            loginMessage = "Couldn't change this: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        openAtLogin = status == .enabled
        if status == .requiresApproval {
            loginMessage = "Approve HeadsUp in System Settings → General → Login Items."
        }
    }
}

private struct CalendarRow: View {
    let calendar: EKCalendar
    // Local copy so the row updates instantly whether or not the engine republishes on update().
    @State private var setting: CalSetting

    init(calendar: EKCalendar) {
        self.calendar = calendar
        _setting = State(initialValue: Engine.shared.setting(for: calendar))
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(cgColor: calendar.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
                .frame(width: 10, height: 10)
            Text(calendar.title).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                lockChip.padding(.trailing, 6)
                chip("10m", 600)
                chip("1m", 60)
                chip("Start", 0)
            }
            .disabled(!setting.enabled)
            .opacity(setting.enabled ? 1 : 0.35)
            Toggle("Enabled", isOn: Binding(get: { setting.enabled }, set: { setting.enabled = $0; save() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func chip(_ label: String, _ offset: Int) -> some View {
        let on = setting.offsets.contains(offset)
        return Button {
            if on { setting.offsets.remove(offset) } else { setting.offsets.insert(offset) }
            save()
        } label: {
            Text(label).padding(.horizontal, 3).capsuleChip(on)
        }
        .buttonStyle(.plain)
        .help(offset == 0 ? "Alert when the event starts" : "Alert \(offset / 60) min before")
    }

    private var lockChip: some View {
        let on = setting.isPrivate
        return Button {
            setting.isPrivate.toggle()
            save()
        } label: {
            Image(systemName: on ? "lock.fill" : "lock").frame(width: 14).capsuleChip(on)
        }
        .buttonStyle(.plain)
        .help("Hide details in alerts")
        .accessibilityLabel("Hide details in alerts")
    }

    private func save() { Engine.shared.update(setting, for: calendar) }
}

private extension View {
    /// Small toggle chip: accent when on, faint gray when off.
    func capsuleChip(_ on: Bool) -> some View {
        font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(on ? Color.white : Color.secondary)
            .background(Capsule().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
            .contentShape(Capsule())
    }
}
