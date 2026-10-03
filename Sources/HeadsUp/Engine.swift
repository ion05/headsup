import AppKit
import EventKit

@MainActor final class Engine: ObservableObject {
    static let shared = Engine()

    @Published private(set) var hasAccess = false
    /// All event calendars, sorted by source title then calendar title.
    @Published private(set) var calendars: [EKCalendar] = []
    /// Not-yet-ended, non-all-day events from enabled calendars through end of tomorrow, sorted by start, for the menu panel.
    @Published private(set) var upcoming: [Alert] = []
    /// Every alert hides its details, e.g. while screen sharing.
    @Published var hideAllDetails = false {
        didSet { UserDefaults.standard.set(hideAllDetails, forKey: Self.hideAllKey) }
    }

    /// Set by the Wi-Fi watcher: auto-hide is on and we're not on a trusted network.
    @Published var offTrustedWiFi = false
    /// What the UI should use to decide whether to hide details.
    var hidingDetails: Bool { hideAllDetails || offTrustedWiFi }

    /// UI sets this. Called on main with every alert due right now (batched into one call).
    var onFire: (([Alert]) -> Void)?

    private let store = EKEventStore()
    private static let settingsKey = "calSettings"
    private var settings: [String: CalSetting] = [:]
    private static let hideAllKey = "hideAllDetails"
    private static let privateItemsKey = "privateItems"
    /// calendarItemIdentifiers the user marked private from the menu.
    private(set) var privateItems: Set<String> = []
    private static let offAccountsKey = "offSources"
    /// sourceIdentifiers of accounts switched off as a whole. Keeps each calendar's own choice for when it's back on.
    private(set) var offAccounts: Set<String> = []
    /// sourceIdentifier -> what Settings shows for the account, ideally its email.
    @Published private(set) var accountNames: [String: String] = [:]
    /// "<alert.id>|<offset>" -> when the key can be forgotten (end of its grace window).
    private var fired: [String: Date] = [:]
    private var snoozed: [(alert: Alert, at: Date)] = []
    private var timers: [Timer] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey) {
            settings = (try? JSONDecoder().decode([String: CalSetting].self, from: data)) ?? [:]
        }
        privateItems = Set(UserDefaults.standard.stringArray(forKey: Self.privateItemsKey) ?? [])
        offAccounts = Set(UserDefaults.standard.stringArray(forKey: Self.offAccountsKey) ?? [])
        hideAllDetails = UserDefaults.standard.bool(forKey: Self.hideAllKey)
    }

    /// Request calendar access, start the timer, observe store changes.
    func start() {
        guard timers.isEmpty else { return }
        WiFiWatcher.shared.start()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { Engine.shared.reloadCalendars(); Engine.shared.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Engine.shared.tick() }
        }
        // .common mode so ticks keep running while the menu-bar menu is open.
        timers = [
            Timer(timeInterval: 10, repeats: true) { _ in MainActor.assumeIsolated { Engine.shared.tick() } },
            // Nudges Exchange/CalDAV sync so last-minute events show up sooner.
            Timer(timeInterval: 60, repeats: true) { _ in MainActor.assumeIsolated { Engine.shared.store.refreshSourcesIfNecessary() } },
        ]
        timers.forEach { RunLoop.main.add($0, forMode: .common) }
        Task {
            hasAccess = (try? await store.requestFullAccessToEvents()) ?? false
            reloadCalendars()
            tick()
        }
    }

    func setting(for cal: EKCalendar) -> CalSetting {
        settings[cal.calendarIdentifier]
            ?? CalSetting(enabled: !(cal.type == .birthday || cal.title.localizedCaseInsensitiveContains("holiday")), offsets: [60])
    }

    func update(_ s: CalSetting, for cal: EKCalendar) {
        objectWillChange.send()
        settings[cal.calendarIdentifier] = s
        UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
        tick()
    }

    func setAccount(_ sourceID: String, on: Bool) {
        objectWillChange.send()
        if on { offAccounts.remove(sourceID) } else { offAccounts.insert(sourceID) }
        UserDefaults.standard.set(Array(offAccounts), forKey: Self.offAccountsKey)
        tick()
    }

    /// Marks every occurrence of an event private (or not).
    func setPrivate(_ itemID: String, _ on: Bool) {
        objectWillChange.send()
        if on { privateItems.insert(itemID) } else { privateItems.remove(itemID) }
        UserDefaults.standard.set(Array(privateItems), forKey: Self.privateItemsKey)
        tick()
    }

    /// Re-fire these alerts at `until`.
    func snooze(_ alerts: [Alert], until: Date) {
        snoozed += alerts.map { ($0, until) }
    }

    /// Fires onFire with a fake event starting in 1 minute that has a Meet link.
    func testAlert() {
        let start = Date().addingTimeInterval(60)
        onFire?([Alert(id: "test|\(Int(start.timeIntervalSince1970))", itemID: "test", title: "Test: HeadsUp is working",
                       start: start, end: start.addingTimeInterval(30 * 60), calendarTitle: "HeadsUp",
                       color: .systemBlue, location: nil, joinURL: URL(string: "https://meet.google.com/abc-defg-hij"), isPrivate: false)])
    }

    private func reloadCalendars() {
        calendars = store.calendars(for: .event)
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
        // EventKit doesn't expose an account's email, so infer it from the user's own address on recent events.
        // ponytail: 90-day scan on every calendar reload; cache per source if reloads get slow.
        let now = Date()
        var names: [String: String] = [:]
        for (id, cals) in Dictionary(grouping: calendars, by: { $0.source?.sourceIdentifier ?? "" }) {
            let events = store.events(matching: store.predicateForEvents(
                withStart: now.addingTimeInterval(-60 * 86400), end: now.addingTimeInterval(30 * 86400), calendars: cals))
            let mine = events.lazy.compactMap { e -> URL? in
                ([e.organizer].compactMap { $0 } + (e.attendees ?? [])).first { $0.isCurrentUser }?.url
            }.first
            names[id] = Self.accountName(title: cals.first?.source?.title ?? "Other", calendarTitles: cals.map(\.title), myURL: mine)
        }
        accountNames = names
    }

    /// Account title if it's an email, else a calendar named like an email (Google's primary), else the user's own address, else the title.
    nonisolated static func accountName(title: String, calendarTitles: [String], myURL: URL?) -> String {
        if title.contains("@") { return title }
        if let email = calendarTitles.first(where: { $0.contains("@") }) { return email }
        if let url = myURL, url.scheme == "mailto", let email = url.absoluteString.split(separator: ":").last { return String(email) }
        return title
    }

    private func tick() {
        let now = Date()
        let cals = calendars.filter { setting(for: $0).enabled && !offAccounts.contains($0.source?.sourceIdentifier ?? "") }
        // One query covers both alerts and the menu panel (through end of tomorrow). Empty array would mean "all calendars" to EventKit.
        let endOfTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now))!
        let events = cals.isEmpty ? [] : store.events(matching: store.predicateForEvents(
            withStart: now.addingTimeInterval(-15 * 60), end: endOfTomorrow, calendars: cals))
        let candidates = events
            .filter { !($0.isAllDay || $0.status == .canceled || $0.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined) }
            .map { (alert: alert(for: $0), offsets: setting(for: $0.calendar).offsets) }

        let due = Self.due(candidates: candidates, snoozed: &snoozed, now: now, fired: &fired)
        if !due.isEmpty { onFire?(due) }

        let next = candidates.map(\.alert).filter { $0.end > now }.sorted { $0.start < $1.start }
        if next != upcoming { upcoming = next }
    }

    private func alert(for e: EKEvent) -> Alert {
        Alert(id: "\(e.eventIdentifier ?? e.calendarItemIdentifier)|\(Int(e.startDate.timeIntervalSince1970))",
              itemID: e.calendarItemIdentifier, title: e.title ?? "", start: e.startDate, end: e.endDate, calendarTitle: e.calendar.title,
              color: NSColor(cgColor: e.calendar.cgColor) ?? .systemBlue,
              location: e.location?.isEmpty == false ? e.location : nil,
              joinURL: meetingURL(in: [e.url?.absoluteString, e.location, e.notes]),
              isPrivate: setting(for: e.calendar).isPrivate || privateItems.contains(e.calendarItemIdentifier))
    }

    // ponytail: fixed 180s grace absorbs timer jitter and short sleeps; a longer sleep drops the alert.
    // Persist the last tick time and fire everything missed since then if that matters.
    nonisolated static let grace: TimeInterval = 180

    /// Everything due at `now`, deduped by alert id, sorted by start. Mutates `fired` and `snoozed`.
    nonisolated static func due(candidates: [(alert: Alert, offsets: Set<Int>)], snoozed: inout [(alert: Alert, at: Date)],
                                now: Date, fired: inout [String: Date]) -> [Alert] {
        fired = fired.filter { $0.value > now }
        var out: [Alert] = []
        for (alert, offsets) in candidates {
            for offset in offsets {
                let key = "\(alert.id)|\(offset)"
                let fireTime = alert.start.addingTimeInterval(-TimeInterval(offset))
                guard fireTime <= now, now.timeIntervalSince(fireTime) < grace, fired[key] == nil else { continue }
                fired[key] = fireTime.addingTimeInterval(grace)
                out.append(alert)
            }
        }
        out += snoozed.filter { $0.at <= now }.map(\.alert)
        snoozed.removeAll { $0.at <= now }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted { $0.start < $1.start }
    }
}
