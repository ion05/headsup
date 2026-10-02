import SwiftUI

@MainActor enum Overlay {
    private static var panels: [NSPanel] = []
    /// Non-nil while the overlay is up. A fresh one per showing, so a fade-out can't clobber a new alert.
    private static var model: OverlayModel?

    static func show(_ alerts: [Alert]) {
        if let model {
            let new = alerts.filter { a in !model.alerts.contains { $0.id == a.id } }
            guard !new.isEmpty else { return }
            model.alerts += new
            NSSound(named: "Glass")?.play()
            return
        }

        var unique: [Alert] = []
        for a in alerts where !unique.contains(where: { $0.id == a.id }) { unique.append(a) }
        guard !unique.isEmpty else { return }

        let model = OverlayModel(alerts: unique)
        self.model = model
        NSApp.activate(ignoringOtherApps: true)
        NSSound(named: "Glass")?.play()

        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false

            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            // Siblings, not nested: inside the effect view SwiftUI text turns vibrant and washes out.
            let host = NSHostingView(rootView: OverlayView(model: model))
            let root = NSView(frame: screen.frame)
            for v in [blur, host] as [NSView] {
                v.frame = root.bounds
                v.autoresizingMask = [.width, .height]
                root.addSubview(v)
            }
            panel.contentView = root

            panel.alphaValue = 0
            panel.orderFrontRegardless()
            if screen == NSScreen.main { panel.makeKey() }
            panels.append(panel)
        }
        if !panels.contains(where: \.isKeyWindow) { panels.first?.makeKey() }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panels.forEach { $0.animator().alphaValue = 1 }
        }
    }

    static func dismiss() {
        let closing = panels
        panels = []
        model = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { closing.forEach { $0.close() } }
        })
    }

    static func snooze(_ alerts: [Alert], until: Date) {
        Engine.shared.snooze(alerts, until: until)
        dismiss()
    }

    static func join(_ url: URL) {
        NSWorkspace.shared.open(url)
        dismiss()
    }
}

private final class OverlayModel: ObservableObject {
    @Published var alerts: [Alert]
    init(alerts: [Alert]) { self.alerts = alerts }
}

/// Borderless panels refuse key status by default; we need it for Esc / Return.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Content sits directly on the frosted desktop; on macOS 26+ the controls are Liquid Glass.
private struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @Environment(\.colorScheme) private var scheme

    private var firstJoinID: String? { model.alerts.first { $0.joinURL != nil }?.id }

    var body: some View {
        ZStack {
            (scheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.5)).ignoresSafeArea()

            VStack(spacing: 56) {
                ForEach(model.alerts) { alert in
                    AlertRow(alert: alert, isDefault: alert.id == firstJoinID, compact: model.alerts.count > 1)
                }
                controls
            }
            .frame(maxWidth: 900)
            .padding(60)
        }
    }

    @ViewBuilder private var controls: some View {
        let row = HStack(spacing: 8) {
            Text("Snooze").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary).padding(.trailing, 4)
            ForEach([1, 5, 10], id: \.self) { mins in
                Button("\(mins) min") { Overlay.snooze(model.alerts, until: .now + Double(mins * 60)) }
            }
            if model.alerts.contains(where: { $0.start > .now }) {
                Button("Until start") {
                    // Already-started alerts have nothing to wait for, so they're just dismissed.
                    for a in model.alerts where a.start > .now { Engine.shared.snooze([a], until: a.start) }
                    Overlay.dismiss()
                }
            }
            Spacer().frame(width: 24)
            Button { Overlay.dismiss() } label: { HStack(spacing: 8) { Text("Dismiss"); keyHint("esc") } }
                .keyboardShortcut(.cancelAction)
        }
        if #available(macOS 26, *) {
            GlassEffectContainer {
                row.font(.system(size: 14, weight: .medium))
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.extraLarge)
            }
        } else {
            row.buttonStyle(Pill())
        }
    }
}

private struct AlertRow: View {
    let alert: Alert
    /// Return joins this alert.
    let isDefault: Bool
    /// Smaller type when several alerts share the screen.
    let compact: Bool

    /// Read at render time so "Hide Event Details" applies to whatever shows next.
    private var hidden: Bool { alert.isPrivate || Engine.shared.hidingDetails }

    var body: some View {
        VStack(spacing: 18) {
            tag

            (hidden ? Text("\(Image(systemName: "lock.fill")) Private event") : Text(alert.title))
                .font(.system(size: compact ? 48 : 68, weight: .semibold))
                .tracking(compact ? -1 : -1.4)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let (text, urgent) = relative(to: ctx.date)
                Text(text)
                    .font(.system(size: compact ? 24 : 32, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? Color.orange : Color.secondary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 18) {
                Label((alert.start..<max(alert.end, alert.start)).formatted(.interval.hour().minute()), systemImage: "clock")
                if !hidden, let location = alert.location {
                    Label(location, systemImage: "mappin").lineLimit(1)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)

            if let url = alert.joinURL { join(url).padding(.top, 14) }
        }
    }

    /// Calendar name as a small pill tinted with its color.
    private var tag: some View {
        let color = hidden ? Color.secondary : Color(nsColor: alert.color)
        return HStack(spacing: 7) {
            if hidden { Image(systemName: "eye.slash").font(.system(size: 11, weight: .semibold)) }
            else { Circle().fill(color).frame(width: 8, height: 8) }
            Text(hidden ? "Details hidden" : alert.calendarTitle)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(hidden ? Color.secondary : Color.primary.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
    }

    @ViewBuilder private func join(_ url: URL) -> some View {
        let label = HStack(spacing: 10) {
            Image(systemName: "video.fill")
            Text("Join")
            if isDefault { keyHint("↩").padding(.leading, 2) }
        }
        if #available(macOS 26, *) {
            // .glassProminent on the default (Return) button renders as a small rounded rect on macOS 27,
            // so the capsule is built from a tinted interactive glass effect instead.
            Button { Overlay.join(url) } label: {
                label.font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .frame(height: 52)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
            // Glass drops its tint when the app isn't frontmost; keep Join blue regardless.
            .background(Color.accentColor, in: Capsule())
            .keyboardShortcut(isDefault ? .defaultAction : nil)
        } else {
            Button { Overlay.join(url) } label: { label }
                .buttonStyle(Pill(prominent: true))
                .keyboardShortcut(isDefault ? .defaultAction : nil)
        }
    }

    private func relative(to now: Date) -> (String, urgent: Bool) {
        let mins = Int((alert.start.timeIntervalSince(now) / 60).rounded())
        let duration = Duration.seconds(abs(mins) * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        if mins > 0 { return ("Starts in \(duration)", false) }
        if mins == 0 { return ("Starting now", true) }
        return ("Started \(duration) ago", true)
    }
}

/// Little key hint shown inside a button.
private func keyHint(_ s: String) -> some View {
    Text(s).font(.system(size: 12, weight: .medium)).opacity(0.5)
}

/// Pre-macOS 26 fallback for the glass buttons: soft capsule with hover feedback. Prominent = big accent Join.
private struct Pill: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, prominent: prominent) }

    private struct PillBody: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            configuration.label
                .font(.system(size: prominent ? 19 : 14, weight: prominent ? .semibold : .medium))
                .padding(.horizontal, prominent ? 30 : 16)
                .frame(height: prominent ? 52 : 34)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(fill, in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var fill: Color {
            if prominent { return .accentColor.opacity(hovering ? 0.88 : 1) }
            // Light: soft white pills that lift off the frost. Dark: faint white wash.
            return .white.opacity(scheme == .dark ? (hovering ? 0.18 : 0.1) : (hovering ? 0.9 : 0.6))
        }
    }
}
