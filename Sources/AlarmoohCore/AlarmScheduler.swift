import Foundation

public struct PendingAlarm: Equatable, Sendable {
    public let event: CalendarEvent
    /// Zeitpunkt, zu dem der Alarm ausgeloest werden soll. Liegt der regulaere
    /// Zeitpunkt in der Vergangenheit (Ruhezustand), ist es "jetzt".
    public let fireDate: Date

    public init(event: CalendarEvent, fireDate: Date) {
        self.event = event
        self.fireDate = fireDate
    }
}

public enum AlarmScheduler {
    /// Bestimmt den naechsten faelligen Alarm.
    ///
    /// - `handled` enthaelt Termine, deren Alarm bereits lief und abgestellt wurde.
    /// - Termine, deren Beginn laenger als `catchUpGrace` zurueckliegt, entfallen.
    public static func nextAlarm(
        events: [CalendarEvent],
        now: Date,
        settings: Settings,
        handled: Set<String> = []
    ) -> PendingAlarm? {
        events
            .filter { !handled.contains($0.id) }
            // ">=", weil die Nachfrist "hoechstens" gilt: ein Termin, der genau
            // `catchUpGrace` zurueckliegt, ist noch drin. Mit Grenze 0 faellt
            // sonst auch ein Termin weg, der genau jetzt beginnt.
            .filter { $0.start >= now.addingTimeInterval(-settings.catchUpGrace) }
            .sorted { $0.start < $1.start }
            .first
            .map { event in
                let regular = event.start.addingTimeInterval(-settings.leadTime)
                return PendingAlarm(event: event, fireDate: max(regular, now))
            }
    }
}
