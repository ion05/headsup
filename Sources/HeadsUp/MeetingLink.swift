import Foundation

private let meetingRegex = try! NSRegularExpression(pattern: [
    #"https://[\w.-]*zoom\.us/(?:j|my|w|s)/[^\s<>"]+"#,
    #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#,
    #"https://teams\.microsoft\.com/l/meetup-join/[^\s<>"]+"#,
    #"https://teams\.live\.com/meet/[^\s<>"]+"#,
].joined(separator: "|"), options: .caseInsensitive)

/// First Zoom / Google Meet / Teams link found in the given texts. Earlier texts win; no fallback to other links.
func meetingURL(in texts: [String?]) -> URL? {
    for case let text? in texts {
        guard let m = meetingRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { continue }
        var s = String(text[r])
        // Surrounding prose/markup: "(link).", Outlook's <link>, quoted hrefs.
        while let last = s.last, ">)\".,".contains(last) { s.removeLast() }
        if let url = URL(string: s) { return url }
    }
    return nil
}
