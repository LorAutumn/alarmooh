import Foundation

/// Setzt das Opt-out-Modell um: abonnierte Kalender alarmieren vollstaendig,
/// einzelne Termine und Serien lassen sich stummschalten.
public enum EventFilter {
    /// Alle Termine, die ueberhaupt als Alarm in Frage kommen — einschliesslich
    /// der stummgeschalteten.
    ///
    /// Das ist die Liste fuer das Einstellungsfenster: Wer eine Stummschaltung
    /// zuruecknehmen will, muss den Termin dort noch sehen. Ganztaegige,
    /// abgesagte und selbst abgesagte Termine sind dagegen auch hier raus — die
    /// kann der Nutzer nicht scharf schalten, sie gehoeren in keine Auswahl.
    public static func selectable(_ events: [CalendarEvent], settings: Settings) -> [CalendarEvent] {
        events
            .filter { settings.subscribedCalendarIDs.contains($0.calendarID) }
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined }
            .sorted { $0.start < $1.start }
    }

    /// Die Termine, die tatsaechlich alarmieren: `selectable` ohne die
    /// stummgeschalteten Vorkommen und Serien.
    ///
    /// Bewusst auf `selectable` aufgesetzt und nicht daneben gebaut: Auswahl im
    /// Fenster und Alarm duerfen nicht auseinanderlaufen. Was hier fehlt, aber
    /// dort steht, ist genau die Stummschaltung — nichts anderes.
    public static func alarmable(_ events: [CalendarEvent], settings: Settings) -> [CalendarEvent] {
        selectable(events, settings: settings)
            .filter { !settings.mutedEventIDs.contains($0.id) }
            .filter { event in
                guard let seriesID = event.seriesID else { return true }
                return !settings.mutedSeriesIDs.contains(seriesID)
            }
    }
}
