import AppKit
import Testing
@testable import HeadsUp

@Test func meetingLinks() {
    #expect(meetingURL(in: ["Join: https://purdue.zoom.us/j/123456789?pwd=AbC123xyz."])?.absoluteString
            == "https://purdue.zoom.us/j/123456789?pwd=AbC123xyz")
    #expect(meetingURL(in: [nil, nil, "Join with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial: +1 555"])?.absoluteString
            == "https://meet.google.com/abc-defg-hij")
    let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d"
    #expect(meetingURL(in: ["Microsoft Teams meeting\nJoin on your computer\nClick here to join the meeting<\(teams)>"])?.absoluteString == teams)
    #expect(meetingURL(in: [nil, "Room 101", "Bring snacks"]) == nil)
    #expect(meetingURL(in: ["Agenda: https://docs.google.com/document/d/xyz"]) == nil)
    // event.url beats notes
    #expect(meetingURL(in: ["https://meet.google.com/aaa-bbbb-ccc", nil, "https://zoom.us/j/1"])?.absoluteString
            == "https://meet.google.com/aaa-bbbb-ccc")
}

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func alert(_ id: String, start: Date = t0) -> Alert {
    Alert(id: id, itemID: id, title: id, start: start, end: start + 1800, calendarTitle: "Cal", color: .red,
          location: nil, joinURL: nil, isPrivate: false)
}
private func due(_ c: [(alert: Alert, offsets: Set<Int>)], at now: Date, _ fired: inout [String: Date],
                 snoozed: inout [(alert: Alert, at: Date)]) -> [String] {
    Engine.due(candidates: c, snoozed: &snoozed, now: now, fired: &fired).map(\.id)
}

@Test func dueWindow() {
    var fired: [String: Date] = [:], snoozed: [(alert: Alert, at: Date)] = []
    let c = [(alert: alert("a"), offsets: Set([60]))]
    #expect(due(c, at: t0 - 61, &fired, snoozed: &snoozed) == [])     // before fireTime
    #expect(due(c, at: t0 - 55, &fired, snoozed: &snoozed) == ["a"])  // within window
    #expect(due(c, at: t0 - 45, &fired, snoozed: &snoozed) == [])     // not twice

    var fresh: [String: Date] = [:]
    #expect(due(c, at: t0 - 60 + 180, &fresh, snoozed: &snoozed) == [])  // past grace
}

@Test func multipleOffsetsAndBatching() {
    var fired: [String: Date] = [:], snoozed: [(alert: Alert, at: Date)] = []
    let c = [(alert: alert("b", start: t0 + 1), offsets: Set([600, 0])), (alert: alert("a"), offsets: Set([600, 0]))]
    #expect(due(c, at: t0 - 590, &fired, snoozed: &snoozed) == ["a", "b"])  // 10-min alert, both in one batch, sorted
    #expect(due(c, at: t0 + 5, &fired, snoozed: &snoozed) == ["a", "b"])    // at-start alert fires again
    #expect(due(c, at: t0 + 15, &fired, snoozed: &snoozed) == [])
    // wake after sleep: both offsets due in the same tick -> one entry per alert
    var fresh: [String: Date] = [:]
    #expect(due([(alert: alert("c"), offsets: [60, 0])], at: t0 + 1, &fresh, snoozed: &snoozed) == ["c"])
}

@Test func snoozes() {
    var fired: [String: Date] = [:]
    var snoozed: [(alert: Alert, at: Date)] = [(alert("a"), t0 + 300)]
    #expect(due([], at: t0 + 299, &fired, snoozed: &snoozed) == [])
    #expect(due([], at: t0 + 300, &fired, snoozed: &snoozed) == ["a"])  // fires even though event started
    #expect(snoozed.isEmpty)
}

@Test func oldSettingsStillDecode() throws {
    let old = try JSONDecoder().decode(CalSetting.self, from: Data(#"{"enabled":true,"offsets":[60]}"#.utf8))
    #expect(old == CalSetting(enabled: true, offsets: [60]))
    let new = CalSetting(enabled: false, offsets: [0], isPrivate: true)
    #expect(try JSONDecoder().decode(CalSetting.self, from: JSONEncoder().encode(new)) == new)
}

@Test func wifiHiding() {
    #expect(!WiFiWatcher.hidden(autoHide: false, ssid: nil, trusted: []))         // feature off
    #expect(!WiFiWatcher.hidden(autoHide: true, ssid: "Home", trusted: ["Home"]))  // trusted
    #expect(WiFiWatcher.hidden(autoHide: true, ssid: "PAL3.0", trusted: ["Home"])) // untrusted
    #expect(WiFiWatcher.hidden(autoHide: true, ssid: nil, trusted: ["Home"]))      // off Wi-Fi / no Location access
}

@Test func menuBarLabel() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))! }
    func text(_ events: [Alert], _ now: Date, hide: Bool = false) -> String? { menuBarText(events: events, now: now, hideDetails: hide, calendar: cal) }

    #expect(text([alert("CS 180", start: at(2, 14, 12))], at(2, 14)) == "CS 180 in 12m")
    #expect(text([alert("CS 180", start: at(2, 16, 5))], at(2, 14)) == "CS 180 in 2h 5m")
    #expect(text([alert("CS 180", start: at(2, 20))], at(2, 14)) == "CS 180 in 6h")      // within 6h
    #expect(text([alert("CS 180", start: at(2, 21))], at(2, 14)) == nil)                 // 7h away
    #expect(text([alert("CS 180", start: at(3, 9))], at(2, 21))?.hasPrefix("CS 180 · 9") == true) // after 8 PM: tomorrow's first
    #expect(text([alert("CS 180", start: at(3, 8))], at(2, 19)) == nil)                  // before 8 PM, 13h away
    #expect(text([], at(2, 21)) == nil)

    // In progress, but one starting within 10 min wins.
    let now = at(2, 14)
    #expect(text([alert("Lab", start: now - 600)], now) == "Lab · now")
    #expect(text([alert("Lab", start: now - 600), alert("Sync", start: now + 300)], now) == "Sync in 5m")
    #expect(text([alert("Lab", start: now - 600), alert("Sync", start: now + 1200)], now) == "Lab · now")
    #expect(text([alert("Lab", start: now - 1800)], now) == nil)                          // ended

    // Privacy and truncation.
    let secret = Alert(id: "s", itemID: "s", title: "Therapy", start: now + 720, end: now + 4000, calendarTitle: "Cal",
                       color: .red, location: nil, joinURL: nil, isPrivate: true)
    #expect(text([secret], now) == "Private event in 12m")
    #expect(text([alert("CS 180", start: now + 720)], now, hide: true) == "Private event in 12m")
    #expect(text([alert("Introduction to Algorithms Recitation", start: now + 720)], now) == "Introduction to Algor… in 12m")
}

@Test func accountNames() {
    let name = Engine.accountName
    #expect(name("tedx@gmail.com", ["Events"], nil) == "tedx@gmail.com")
    #expect(name("Google", ["School", "me@gmail.com"], URL(string: "mailto:other@gmail.com")) == "me@gmail.com")
    #expect(name("Exchange", ["Calendar"], URL(string: "mailto:agarw357@purdue.edu")) == "agarw357@purdue.edu")
    #expect(name("iCloud", ["Home"], nil) == "iCloud")
}
