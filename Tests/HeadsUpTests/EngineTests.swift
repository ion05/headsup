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
