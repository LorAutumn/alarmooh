import Foundation

/// Setzt das Opt-out-Modell um: abonnierte Kalender alarmieren vollstaendig,
/// einzelne Termine und Serien lassen sich stummschalten.
public enum EventFilter {
    public static func alarmable(_ events: [CalendarEvent], settings: Settings) -> [CalendarEvent] {
        events
            .filter { settings.subscribedCalendarIDs.contains($0.calendarID) }
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined }
            .filter { !settings.mutedEventIDs.contains($0.id) }
            .filter { event in
                guard let seriesID = event.seriesID else { return true }
                return !settings.mutedSeriesIDs.contains(seriesID)
            }
            .sorted { $0.start < $1.start }
    }
}
