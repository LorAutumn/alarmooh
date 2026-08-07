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
    /// Der naechste Termin, der ueberhaupt noch aktuell ist.
    ///
    /// - `handled` enthaelt Termine, deren Alarm bereits lief und abgestellt wurde.
    /// - Termine, deren Beginn laenger als `catchUpGrace` zurueckliegt, entfallen.
    ///
    /// Die eine Definition von "naechster Termin" fuer Menue und Alarm. EventKit
    /// liefert auch Termine, die schon laufen — der Suchzeitraum trifft alles,
    /// was ihn ueberlappt. Ohne diese Regel zeigte das Menue eine seit einer
    /// Viertelstunde laufende Besprechung als "Naechster: …" an.
    ///
    /// Bewusst ohne `paused`-Pruefung: Wer die Alarme abgestellt hat, will
    /// trotzdem sehen, was ansteht, und aus dem Menue beitreten koennen.
    /// Die Pause gehoert allein zu `nextAlarm`.
    public static func nextRelevantEvent(
        events: [CalendarEvent],
        now: Date,
        settings: Settings,
        handled: Set<String> = []
    ) -> CalendarEvent? {
        events
            .filter { !handled.contains($0.id) }
            // ">=", weil die Nachfrist "hoechstens" gilt: ein Termin, der genau
            // `catchUpGrace` zurueckliegt, ist noch drin. Mit Grenze 0 faellt
            // sonst auch ein Termin weg, der genau jetzt beginnt.
            .filter { $0.start >= now.addingTimeInterval(-settings.catchUpGrace) }
            .sorted { $0.start < $1.start }
            .first
    }

    /// Bestimmt den naechsten faelligen Alarm.
    ///
    /// Baut auf `nextRelevantEvent` auf, damit es genau eine Definition von
    /// "naechster Termin" gibt: Menue und Alarm koennen so nicht auseinanderlaufen.
    /// Hinzu kommt hier nur die Pause und der Ausloesezeitpunkt.
    public static func nextAlarm(
        events: [CalendarEvent],
        now: Date,
        settings: Settings,
        handled: Set<String> = []
    ) -> PendingAlarm? {
        // Die eine Stelle, an der die Pause gilt. Sie gehoert hierher und nicht
        // ins Menue: solange kein Alarm geplant wird, kann auch keiner aus einem
        // anderen Weg (Scan, Aufwachen, Nachholfrist) doch noch losgehen.
        // Wer Pausieren woanders nachbaut, macht es nur unvollstaendig.
        guard !settings.paused else { return nil }

        return nextRelevantEvent(events: events, now: now, settings: settings, handled: handled)
            .map { event in
                let regular = event.start.addingTimeInterval(-settings.leadTime)
                return PendingAlarm(event: event, fireDate: max(regular, now))
            }
    }

    /// Untergrenze fuer die Laufzeit eines Alarms, siehe `alarmEndDate`.
    private static let minimumRingingDuration: TimeInterval = 60

    /// Wann ein laufender Alarm von selbst aufhoert.
    ///
    /// Dieselbe Regel wie ueberall: Mit `catchUpGrace` nach Terminbeginn hoert
    /// ein Termin auf, aktuell zu sein — dann verstummt auch der Ton, falls der
    /// Nutzer ihn nicht schon durch Beitreten, Stummschalten oder Pausieren
    /// abgestellt hat.
    ///
    /// Aber nie frueher als eine Minute nach jetzt: Ein nachgeholter Alarm kann
    /// losgehen, wenn der Termin schon 1:58 laeuft. Die strenge Regel liesse ihn
    /// dann zwei Sekunden laeuten — ein Piepser, den der Nutzer genau in dem Fall
    /// verpasst, fuer den die Nachholfrist ueberhaupt da ist.
    public static func alarmEndDate(
        for event: CalendarEvent,
        now: Date,
        settings: Settings
    ) -> Date {
        max(
            event.start.addingTimeInterval(settings.catchUpGrace),
            now.addingTimeInterval(minimumRingingDuration)
        )
    }
}
