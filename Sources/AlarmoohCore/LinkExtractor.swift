import Foundation

/// Findet die Meeting-URL eines Termins.
public enum LinkExtractor {
    /// Hosts, die als echte Meeting-Anbieter gelten und Vorrang haben.
    static let knownHosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com",
    ]

    public static func meetingLink(in event: CalendarEvent) -> URL? {
        if let url = event.url, isUsable(url) { return url }

        // Reihenfolge der Design-Entscheidung: URL-Feld, Notizen, Ort.
        let haystack = [event.notes, event.location].compactMap { $0 }.joined(separator: "\n")
        let candidates = urls(in: haystack)

        return candidates.first(where: isKnownProvider) ?? candidates.first
    }

    static func urls(in text: String) -> [URL] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .filter(isUsable)
    }

    static func isUsable(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http"
    }

    static func isKnownProvider(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return knownHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
