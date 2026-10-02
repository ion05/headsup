import AppKit

/// Per-calendar choices, saved in UserDefaults keyed by EKCalendar.calendarIdentifier.
struct CalSetting: Codable, Equatable {
    var enabled: Bool
    /// Seconds before start to alert. 600 = 10 min, 60 = 1 min, 0 = at start.
    var offsets: Set<Int>
    /// Hide event details in this calendar's alerts.
    var isPrivate = false
}

extension CalSetting {
    // Settings saved before isPrivate existed still decode instead of resetting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        offsets = try c.decode(Set<Int>.self, forKey: .offsets)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
    }
}

/// One event as shown in the full-screen alert.
struct Alert: Identifiable, Equatable {
    /// Stable per occurrence: "<eventIdentifier>|<start timeIntervalSince1970>".
    let id: String
    /// EKEvent.calendarItemIdentifier, shared by every occurrence of a recurring event.
    let itemID: String
    let title: String
    let start: Date
    let end: Date
    let calendarTitle: String
    let color: NSColor
    let location: String?
    let joinURL: URL?
    /// Alert hides title, calendar and location.
    let isPrivate: Bool
}
