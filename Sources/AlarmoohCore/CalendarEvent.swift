import Foundation

/// Ein Kalender, wie ihn der Nutzer in den Einstellungen abonnieren kann.
public struct CalendarInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Ein einzelnes Vorkommen eines Termins, losgeloest von EventKit.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// Kennung dieses Vorkommens (EventKit: eventIdentifier).
    public let id: String
    /// Stabile Kennung der Serie (EventKit: calendarItemExternalIdentifier).
    /// Nil bei Einzelterminen ohne Serienbezug.
    public let seriesID: String?
    public let title: String
    public let start: Date
    public let calendarID: String
    public let calendarTitle: String
    public let isAllDay: Bool
    public let isCancelled: Bool
    /// Der Nutzer selbst hat abgesagt.
    public let isDeclined: Bool
    public let url: URL?
    public let notes: String?
    public let location: String?

    public init(
        id: String,
        seriesID: String? = nil,
        title: String,
        start: Date,
        calendarID: String,
        calendarTitle: String,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        url: URL? = nil,
        notes: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.title = title
        self.start = start
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
        self.url = url
        self.notes = notes
        self.location = location
    }
}
