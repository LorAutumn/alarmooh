import Foundation

/// Liefert Termine. Produktiv per EventKit, im Test per Fake.
public protocol CalendarSource: Sendable {
    func calendars() throws -> [CalendarInfo]
    func events(from: Date, to: Date) throws -> [CalendarEvent]
}
