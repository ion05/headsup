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
    @ObservedObject private var wifi = WiFiWatcher.shared
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
        .background(.thickMaterial)
        .overlay(RoundedRectangle(cornerRadius: panelRadius, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .background(RoundedWindow())
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
                Button("Open Settings…", action: openSettings).glassButtonStyle().controlSize(.small).padding(.top, 2)
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
                    if wifi.autoHide, let until = wifi.pausedUntil {
                        HStack(spacing: 4) {
                            Text("Wi-Fi hiding paused \(pauseLabel(until))").font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("Resume") { wifi.resume() }
                                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color.accentColor)
                        }
                    } else if engine.offTrustedWiFi {
                        HStack(spacing: 4) {
                            Text("Hidden — untrusted Wi-Fi").font(.system(size: 11)).foregroundStyle(.secondary)
                            Menu {
                                ForEach([1, 2, 4], id: \.self) { h in
                                    Button(h == 1 ? "1 hour" : "\(h) hours") { wifi.pause(until: .now + Double(h) * 3600) }
                                }
                                Button("Until tomorrow") {
                                    wifi.pause(until: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!)
                                }
                            } label: {
                                Text("Show for…").font(.system(size: 11)).foregroundStyle(Color.accentColor)
                            }
                            // A plain-button menu draws our label; .borderlessButton ignores its font and color.
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
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

            let buttons = HStack(spacing: 8) {
                Button { engine.testAlert() } label: { Label("Test Alert", systemImage: "bell.badge").frame(maxWidth: .infinity) }
                Button(action: openSettings) { Label("Settings…", systemImage: "gearshape").frame(maxWidth: .infinity) }
                    .keyboardShortcut(",")
                Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power").frame(maxWidth: .infinity) }
                    .keyboardShortcut("q")
            }
            .font(.system(size: 12, weight: .medium))
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 6)
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 0) { buttons.buttonStyle(.glass) }
            } else {
                buttons.buttonStyle(.bordered)
            }
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
                let label = Label("Join", systemImage: "video.fill").font(.system(size: 13, weight: .semibold))
                if #available(macOS 26, *) {
                    Button { NSWorkspace.shared.open(url) } label: {
                        label.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 32).contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .joinGlass()
                } else {
                    Button { NSWorkspace.shared.open(url) } label: { label.frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .padding(12)
        .cardSurface(color)
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
                .glassButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .hoverChip(hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { eventMenu(alert, isMarkedPrivate: isMarkedPrivate) }
    }
}

private let panelRadius: CGFloat = 26

/// macOS 27 gives the menu-bar window near-square corners and a see-through background,
/// so clip the window to our own radius; the panel paints its own background.
private struct RoundedWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Hook: NSView {
        override func viewDidMoveToWindow() {
            // The frame view above contentView draws the system background, so clip there.
            guard let frame = window?.contentView?.superview else { return }
            frame.wantsLayer = true
            frame.layer?.cornerRadius = panelRadius
            frame.layer?.cornerCurve = .continuous
            frame.layer?.masksToBounds = true
        }

        // The shadow is traced from the window's pixels; retrace it when the panel resizes.
        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in self?.window?.invalidateShadow() }
        }
    }
}

private extension View {
    /// Next-up card: tinted Liquid Glass on macOS 26+, soft tinted fill before.
    @ViewBuilder func cardSurface(_ color: Color) -> some View {
        // Concentric with the window: its radius minus the panel's 8pt inset.
        let shape = RoundedRectangle(cornerRadius: panelRadius - 8, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(color.opacity(0.15)), in: shape)
        } else {
            background(color.opacity(0.1), in: shape).overlay(shape.strokeBorder(color.opacity(0.25)))
        }
    }

    /// Row hover highlight: a glass chip on macOS 26+, faint fill before.
    @ViewBuilder func hoverChip(_ on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(on ? .regular : .identity, in: shape)
        } else {
            background(on ? Color.primary.opacity(0.06) : .clear, in: shape)
        }
    }

    @ViewBuilder func glassButtonStyle() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }
}

/// "until 3:40 PM", or "until midnight" for the Until tomorrow pause.
func pauseLabel(_ until: Date) -> String {
    Calendar.current.startOfDay(for: until) == until ? "until midnight" : "until \(until.formatted(date: .omitted, time: .shortened))"
}

func timeRange(_ alert: Alert) -> String {
    (alert.start..<max(alert.end, alert.start)).formatted(.interval.hour().minute())
}

@MainActor private func privateButton(_ alert: Alert, on: Bool) -> some View {
    Button { Engine.shared.setPrivate(alert.itemID, !on) } label: {
        Image(systemName: on ? "lock.fill" : "lock.open")
            .font(.system(size: 11, weight: .medium))
    }
    .glassButtonStyle()
    .buttonBorderShape(.circle)
    .controlSize(.small)
    .help(on ? "Show this event's details in alerts" : "Hide this event's details in alerts")
}

@MainActor @ViewBuilder private func eventMenu(_ alert: Alert, isMarkedPrivate: Bool) -> some View {
    if let url = alert.joinURL {
        Button("Join", systemImage: "video") { NSWorkspace.shared.open(url) }
    }
    Toggle("Private", isOn: Binding(get: { isMarkedPrivate }, set: { Engine.shared.setPrivate(alert.itemID, $0) }))
}
