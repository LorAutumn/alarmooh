import Foundation

/// Nur fuer Tests und den Debug-Modus der App.
public struct FakeCalendarSource: CalendarSource {
    public var calendarList: [CalendarInfo]
    public var events: [CalendarEvent]

    public init(calendars: [CalendarInfo] = [], events: [CalendarEvent] = []) {
        self.calendarList = calendars
        self.events = events
    }

    public func calendars() throws -> [CalendarInfo] { calendarList }

    /// Bildet die Einschraenkung der echten Quelle nach: nur Termine aus den
    /// genannten Kalendern. Eine leere Menge enthaelt keine Kennung, liefert
    /// also nichts — dieselbe Regel wie in `EventKitCalendarSource`.
    public func events(from: Date, to: Date, calendarIDs: Set<String>) throws -> [CalendarEvent] {
        events
            .filter { calendarIDs.contains($0.calendarID) }
            .filter { $0.start >= from && $0.start < to }
            .sorted { $0.start < $1.start }
    }
}

extension CalendarEvent {
    /// Beispieldaten fuer Tests. Bewusst im Produktiv-Target, damit alle
    /// Testdateien denselben Helfer nutzen.
    public static func stub(
        id: String = "event-1",
        seriesID: String? = nil,
        title: String = "Standup",
        start: Date = Date(timeIntervalSince1970: 1_000_000),
        calendarID: String = "cal-work",
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        url: URL? = nil,
        notes: String? = nil,
        location: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, seriesID: seriesID, title: title, start: start,
            calendarID: calendarID, calendarTitle: "Arbeit",
            isAllDay: isAllDay, isCancelled: isCancelled, isDeclined: isDeclined,
            url: url, notes: notes, location: location
        )
    }
}
