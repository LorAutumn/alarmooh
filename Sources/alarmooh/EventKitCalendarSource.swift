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

    /// Fragt EventKit nur nach den abonnierten Kalendern.
    ///
    /// WICHTIG, bitte nicht "vereinfachen": `predicateForEvents` versteht
    /// `calendars: nil` als *alle* Kalender des Speichers. Ein leeres Abo darf
    /// deshalb niemals zu `nil` werden — das waere aus "nichts alarmiert"
    /// stillschweigend "alles lesen" geworden. Also lieber frueh aussteigen und
    /// den Kalender gar nicht erst anfassen.
    ///
    /// Dass `EventFilter.selectable` danach noch einmal gegen das Abo prueft,
    /// bleibt so: die Einschraenkung hier spart Arbeit und liest weniger fremde
    /// Termine ein, die zweite Pruefung im Speicher ist die Absicherung, falls
    /// diese hier je danebenliegt.
    func events(from: Date, to: Date, calendarIDs: Set<String>) throws -> [CalendarEvent] {
        // Ueber die Kennung aufgeloest, nicht blind uebernommen: ein Abo kann
        // auf einen geloeschten Kalender zeigen. Der faellt hier einfach weg.
        let subscribed = store.calendars(for: .event)
            .filter { calendarIDs.contains($0.calendarIdentifier) }
        // Leeres Abo — oder keine der gespeicherten Kennungen existiert noch.
        // Beides heisst: keine Termine.
        guard !subscribed.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: subscribed)
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
    /// Das Format selbst steht in `OccurrenceID` im Kern — dort, wo es auch
    /// wieder gelesen wird (Anzeige im Fenster, Aufraeumen alter
    /// Stummschaltungen). Hier faellt nur die Entscheidung, was der Grundteil
    /// der Kennung ist.
    private static func occurrenceID(for event: EKEvent) -> String {
        // Fehlt die Kennung (bisher nie beobachtet), nehmen wir die lokale
        // Kennung; erst wenn auch die leer ist, bleibt nur eine Zufalls-UUID.
        // Die ist bewusst der letzte Ausweg: sie aendert sich bei jedem Scan.
        let base = event.eventIdentifier
            ?? (event.calendarItemIdentifier.isEmpty ? nil : event.calendarItemIdentifier)
            ?? UUID().uuidString
        return OccurrenceID.make(eventIdentifier: base, start: event.startDate)
    }
}
