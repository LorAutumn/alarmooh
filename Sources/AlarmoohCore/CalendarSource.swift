import Foundation

/// Liefert Termine. Produktiv per EventKit, im Test per Fake.
public protocol CalendarSource: Sendable {
    func calendars() throws -> [CalendarInfo]

    /// Termine im Zeitraum, beschraenkt auf die genannten Kalender.
    ///
    /// `calendarIDs` ist bewusst ein Parameter und keine Eigenschaft der
    /// Quelle: eine gesetzte Eigenschaft waere verborgener Zustand, den zwei
    /// Aufrufer (Alarm-Scan und Einstellungsfenster) sich teilen muessten, und
    /// ein vergessenes Setzen laese die Quelle mit dem Umfang des letzten
    /// Aufrufs weiterlesen. So steht der Umfang an jeder Aufrufstelle.
    ///
    /// Ebenso bewusst nicht optional: es gibt keinen Wert, der "alle Kalender"
    /// bedeutet. Eine leere Menge heisst leere Ergebnisliste — genau wie ein
    /// leeres Abo nichts alarmieren darf.
    func events(from: Date, to: Date, calendarIDs: Set<String>) throws -> [CalendarEvent]
}
