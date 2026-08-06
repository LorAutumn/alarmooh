import AlarmoohCore
import EventKit
import Foundation

final class EventKitCalendarSource: CalendarSource, @unchecked Sendable {
    private let store = EKEventStore()

    /// Einmalige Nachfrage beim Nutzer. Ergebnis wird von macOS gemerkt.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func calendars() throws -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title < $1.title }
    }

    func events(from: Date, to: Date) throws -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .map(Self.convert)
            .sorted { $0.start < $1.start }
    }

    static func convert(_ event: EKEvent) -> CalendarEvent {
        let declined = event.attendees?
            .first(where: \.isCurrentUser)?
            .participantStatus == .declined

        return CalendarEvent(
            id: occurrenceID(for: event),
            seriesID: event.hasRecurrenceRules ? event.calendarItemExternalIdentifier : nil,
            title: event.title ?? "Termin",
            start: event.startDate,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled,
            isDeclined: declined,
            url: event.url,
            notes: event.notes,
            location: event.location
        )
    }

    /// Kennung eines einzelnen Vorkommens.
    ///
    /// WICHTIG, bitte nicht "vereinfachen": `eventIdentifier` gehoert bei
    /// Serienterminen der ganzen Serie, nicht dem einzelnen Vorkommen. Alle
    /// Termine einer Serie teilen sich denselben Wert. Ohne den Startzeitpunkt
    /// im Schluessel wuerde ein einmal weggeklickter Alarm die komplette Serie
    /// fuer immer stummschalten, und "dieses eine Vorkommen stummschalten"
    /// waere nicht mehr von "ganze Serie stummschalten" zu unterscheiden.
    /// Erst das Paar (eventIdentifier, startDate) ist eindeutig.
    ///
    /// Der Startzeitpunkt wird als ganze Sekunden seit 1970 geschrieben; damit
    /// ist die Kennung bei jedem erneuten Scan bitgleich und haengt nicht von
    /// Locale, Zeitzone oder der Double-Formatierung ab.
    private static func occurrenceID(for event: EKEvent) -> String {
        let start = Int(event.startDate.timeIntervalSince1970)
        // Fehlt die Kennung (bisher nie beobachtet), nehmen wir die lokale
        // Kennung; erst wenn auch die leer ist, bleibt nur eine Zufalls-UUID.
        // Die ist bewusst der letzte Ausweg: sie aendert sich bei jedem Scan.
        let base = event.eventIdentifier
            ?? (event.calendarItemIdentifier.isEmpty ? nil : event.calendarItemIdentifier)
            ?? UUID().uuidString
        return "\(base)|\(start)"
    }
}
