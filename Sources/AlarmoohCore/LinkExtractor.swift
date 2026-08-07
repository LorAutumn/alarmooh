import Foundation

/// Findet die Meeting-URL eines Termins.
public enum LinkExtractor {
    /// Hosts, die als echte Meeting-Anbieter gelten und Vorrang haben.
    static let knownHosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com",
        "webex.com", "gotomeeting.com", "goto.com", "meet.jit.si", "jitsi.org",
        "bluejeans.com", "chime.aws", "zoomgov.com", "ringcentral.com", "around.co",
        "discord.gg", "slack.com",
    ]

    /// Bestandteile, die eine URL als etwas anderes als einen Beitreten-Link
    /// ausweisen. Der Knopf im Panel heisst "Beitreten" und schaltet den Alarm
    /// ab; ein Abmelde-Link an dieser Stelle waere fatal.
    static let rejectedFragments = [
        "unsubscribe", "dialin.", "support.google.com", "aka.ms", "meetingoptions",
        "/mailing", "optout",
    ]

    /// HTML-Entities, wie Exchange/Outlook sie in `notes` liefert. Ohne das
    /// Aufloesen bricht ein Zoom-Link mit `?pwd=…&amp;uname=…` beim Beitreten ab.
    /// `&amp;` bewusst zuletzt, sonst entstuende aus `&amp;lt;` ein `<`.
    static let htmlEntities = [
        ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&"),
    ]

    public static func meetingLink(in event: CalendarEvent) -> URL? {
        if let url = event.url, isUsable(url), !isRejected(url) { return url }

        // Reihenfolge der Design-Entscheidung: URL-Feld, Notizen, Ort.
        let haystack = [event.notes, event.location].compactMap { $0 }.joined(separator: "\n")
        let candidates = urls(in: haystack)

        return candidates.first(where: isKnownProvider) ?? candidates.first
    }

    static func urls(in text: String) -> [URL] {
        let haystack = unescapingHTMLEntities(text)
        guard !haystack.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        let source = haystack as NSString
        return detector.matches(in: haystack, range: range)
            .filter { hasExplicitScheme(source.substring(with: $0.range)) }
            .compactMap(\.url)
            .filter(isUsable)
            .filter { !isRejected($0) }
    }

    static func unescapingHTMLEntities(_ text: String) -> String {
        htmlEntities.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Der Detektor erkennt auch blosse Domains in Fliesstext ("… von
    /// wiki.example.com auf confluence"). Nur was im Quelltext wirklich mit
    /// einem Schema begann, ist ein gemeinter Link.
    static func hasExplicitScheme(_ matched: String) -> Bool {
        let lowercased = matched.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }

    static func isUsable(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http"
    }

    static func isRejected(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        return rejectedFragments.contains { absolute.contains($0) }
    }

    /// Oeffentlich, weil das Alarm-Panel einen bekannten Meeting-Anbieter von
    /// einem beliebigen Host unterscheiden koennen muss, um vor einer fremden
    /// Adresse zu warnen. Nur die Frage ist oeffentlich, nicht die Antwortliste:
    /// `knownHosts` bleibt intern, die Ansicht hat sie nicht zu durchlaufen.
    public static func isKnownProvider(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return knownHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
