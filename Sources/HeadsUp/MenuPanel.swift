import SwiftUI

/// The event to feature: one starting within 10 min beats one in progress, otherwise the soonest.
func nextEvent(_ events: [Alert], now: Date) -> Alert? {
    let live = events.filter { $0.end > now }.sorted { $0.start < $1.start }
    return live.first { $0.start > now && $0.start.timeIntervalSince(now) <= 600 }
        ?? live.first { $0.start <= now }
        ?? live.first
}

/// Menu-bar text next to the icon: "CS 180 in 12m", "CS 180 · now", or after 8 PM with today done,
/// tomorrow's first event "CS 180 · 9:00 AM". Nil = icon only.
func menuBarText(events: [Alert], now: Date, hideDetails: Bool, calendar: Calendar = .current) -> String? {
    guard let next = nextEvent(events, now: now) else { return nil }
    var title = next.isPrivate || hideDetails ? "Private event" : next.title
    if title.count > 22 { title = title.prefix(21).trimmingCharacters(in: .whitespaces) + "…" }

    if next.start <= now { return "\(title) · now" }
    let wait = next.start.timeIntervalSince(now)
    if wait <= 6 * 3600 { return "\(title) in \(shortDuration(wait))" }

    // next is the soonest event and it's 6h+ away, so nothing is left today.
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    guard calendar.component(.hour, from: now) >= 20, calendar.isDate(next.start, inSameDayAs: tomorrow) else { return nil }
    let time = next.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone))
    return "\(title) · \(time)"
}

/// "12m", "2h", "2h 5m". Rounds up so it never says "0m" before the start.
func shortDuration(_ seconds: TimeInterval) -> String {
    let m = Int((seconds / 60).rounded(.up)), h = m / 60
    return h == 0 ? "\(m)m" : m % 60 == 0 ? "\(h)h" : "\(h)h \(m % 60)m"
}

struct MenuPanel: View {
    @ObservedObject private var engine = Engine.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if engine.hasAccess {
                TimelineView(.everyMinute) { agenda(now: $0.date) }
            } else {
                accessBanner
            }
            Divider().padding(.horizontal, 12).padding(.vertical, 6)
            footer
        }
        .padding(8)
        .frame(width: 340)
    }

    @ViewBuilder private func agenda(now: Date) -> some View {
        let cal = Calendar.current
        let events = engine.upcoming.filter { $0.end > now }
        let next = nextEvent(events, now: now)
        let rest = events.filter { $0.id != next?.id }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let today = rest.filter { $0.start < tomorrow }
        let showTomorrow = cal.component(.hour, from: now) >= 20 || !events.contains { $0.start < tomorrow }
        let later = showTomorrow ? rest.filter { $0.start >= tomorrow } : []

        VStack(alignment: .leading, spacing: 12) {
            if let next {
                NextUpCard(alert: next, now: now, isMarkedPrivate: engine.privateItems.contains(next.itemID))
            } else {
                emptyState
            }
            if !today.isEmpty || !later.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        section("Today", day: now, today, now: now)
                        section("Tomorrow", day: tomorrow, later, now: now)
                    }
                }
                // Grows with its rows, scrolls past ~8 of them.
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func section(_ title: String, day: Date, _ events: [Alert], now: Date) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
                ForEach(events) { EventRow(alert: $0, now: now, isMarkedPrivate: engine.privateItems.contains($0.itemID)) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text("Nothing coming up").font(.system(size: 13, weight: .semibold))
            Text("Your calendar is clear through tomorrow.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var accessBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar access needed").font(.system(size: 13, weight: .semibold))
                Text("HeadsUp can't see your events yet.").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Open Settings…", action: openSettings).controlSize(.small).padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash").frame(width: 16).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hide Event Details")
                    if engine.offTrustedWiFi {
                        Text("Hidden — untrusted Wi-Fi").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Hide Event Details", isOn: $engine.hideAllDetails)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            MenuButton(title: "Test Alert", systemImage: "bell.badge") { engine.testAlert() }
            MenuButton(title: "Settings…", systemImage: "gearshape", shortcut: ",", action: openSettings)
            MenuButton(title: "Quit HeadsUp", systemImage: "power", shortcut: "q") { NSApp.terminate(nil) }
        }
    }

    private func openSettings() {
        openWindow(id: "settings")
        // Accessory (LSUIElement) apps aren't active, so the window would open behind others.
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct NextUpCard: View {
    let alert: Alert
    let now: Date
    let isMarkedPrivate: Bool
    @State private var hovering = false

    var body: some View {
        let color = Color(nsColor: alert.color)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("NEXT UP").font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer()
                if hovering { privateButton(alert, on: isMarkedPrivate) }
                Text(relative(now: now))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(alert.start <= now ? Color.accentColor : Color.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(alert.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        if alert.isPrivate {
                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Text(timeRange(alert)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    Group {
                        Label(alert.calendarTitle, systemImage: "calendar")
                        if let location = alert.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            // Lets the color bar stretch to the text's height and no further.
            .fixedSize(horizontal: false, vertical: true)

            if let url = alert.joinURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Join", systemImage: "video.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.25)))
        .onHover { hovering = $0 }
        .contextMenu { eventMenu(alert, isMarkedPrivate: isMarkedPrivate) }
    }

    private func relative(now: Date) -> String {
        if alert.start <= now { return "now · ends in \(shortDuration(alert.end.timeIntervalSince(now)))" }
        if !Calendar.current.isDate(alert.start, inSameDayAs: now) { return "Tomorrow" }
        return "in \(shortDuration(alert.start.timeIntervalSince(now)))"
    }
}

private struct EventRow: View {
    let alert: Alert
    let now: Date
    let isMarkedPrivate: Bool
    @State private var hovering = false

    var body: some View {
        let live = alert.start <= now
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(nsColor: alert.color))
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(alert.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if alert.isPrivate {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(live ? "Now · until \(alert.end.formatted(date: .omitted, time: .shortened))" : timeRange(alert))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(live ? Color.accentColor : Color.secondary)
            }
            Spacer(minLength: 4)
            if hovering { privateButton(alert, on: isMarkedPrivate) }
            if let url = alert.joinURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Join", systemImage: "video.fill").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { eventMenu(alert, isMarkedPrivate: isMarkedPrivate) }
    }
}

/// Native-menu-looking row for the footer.
private struct MenuButton: View {
    let title: String
    let systemImage: String
    var shortcut: KeyEquivalent?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 16).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let shortcut {
                    Text("⌘\(String(shortcut.character).uppercased())").foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(shortcut.map { KeyboardShortcut($0) })
    }
}

private func timeRange(_ alert: Alert) -> String {
    (alert.start..<max(alert.end, alert.start)).formatted(.interval.hour().minute())
}

@MainActor private func privateButton(_ alert: Alert, on: Bool) -> some View {
    Button { Engine.shared.setPrivate(alert.itemID, !on) } label: {
        Image(systemName: on ? "lock.fill" : "lock.open")
            .font(.system(size: 11, weight: .medium))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help(on ? "Show this event's details in alerts" : "Hide this event's details in alerts")
}

@MainActor @ViewBuilder private func eventMenu(_ alert: Alert, isMarkedPrivate: Bool) -> some View {
    if let url = alert.joinURL {
        Button("Join", systemImage: "video") { NSWorkspace.shared.open(url) }
    }
    Toggle("Private", isOn: Binding(get: { isMarkedPrivate }, set: { Engine.shared.setPrivate(alert.itemID, $0) }))
}
