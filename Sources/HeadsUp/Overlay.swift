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
            panel.appearance = NSAppearance(named: .darkAqua)

            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            let host = NSHostingView(rootView: OverlayView(model: model))
            host.frame = blur.bounds
            host.autoresizingMask = [.width, .height]
            blur.addSubview(host)
            panel.contentView = blur

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

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private var firstJoinID: String? { model.alerts.first { $0.joinURL != nil }?.id }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.alerts) { alert in
                        if alert.id != model.alerts.first?.id {
                            Divider().padding(.vertical, 28)
                        }
                        AlertRow(alert: alert, isDefault: alert.id == firstJoinID)
                    }
                }
                .padding(44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 40, y: 20)

                controls
            }
            .frame(maxWidth: 780)
            .padding(40)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Text("Snooze")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
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
            Spacer()
            Button("Dismiss") { Overlay.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.horizontal, 12)
    }
}

private struct AlertRow: View {
    let alert: Alert
    /// Return joins this alert.
    let isDefault: Bool

    /// Read at render time so "Hide Event Details" applies to whatever shows next.
    private var hidden: Bool { alert.isPrivate || Engine.shared.hidingDetails }

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(hidden ? Color.gray : Color(nsColor: alert.color)).frame(width: 10, height: 10)
                    Text(hidden ? "DETAILS HIDDEN" : alert.calendarTitle.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }

                (hidden ? Text("\(Image(systemName: "lock.fill")) Private event") : Text(alert.title))
                    .font(.system(size: 44, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let (text, urgent) = relative(to: ctx.date)
                    Text(text)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(urgent ? Color.orange : Color.primary)
                        .contentTransition(.numericText())
                }

                HStack(spacing: 20) {
                    Label((alert.start..<max(alert.end, alert.start)).formatted(.interval.hour().minute()), systemImage: "clock")
                    if !hidden, let location = alert.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse").lineLimit(1)
                    }
                }
                .font(.title3)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let url = alert.joinURL {
                Button { Overlay.join(url) } label: {
                    Label("Join", systemImage: "video.fill")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .keyboardShortcut(isDefault ? .defaultAction : nil)
            }
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
