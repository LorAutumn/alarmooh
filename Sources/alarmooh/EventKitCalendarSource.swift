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
            id: event.eventIdentifier ?? UUID().uuidString,
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
}
