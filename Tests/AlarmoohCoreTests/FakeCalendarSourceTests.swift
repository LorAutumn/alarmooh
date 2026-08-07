import Foundation
import Testing
@testable import AlarmoohCore

@Test func fakeSourceReturnsEventsInWindow() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let inside = CalendarEvent.stub(id: "a", start: now.addingTimeInterval(600))
    let outside = CalendarEvent.stub(id: "b", start: now.addingTimeInterval(90_000))
    let source = FakeCalendarSource(events: [inside, outside])

    let result = try source.events(from: now, to: now.addingTimeInterval(3600),
                                   calendarIDs: ["cal-work"])

    #expect(result.map(\.id) == ["a"])
}

// MARK: - Einschraenkung auf die abonnierten Kalender

@Test func fakeSourceReturnsOnlyRequestedCalendars() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let work = CalendarEvent.stub(id: "a", start: now, calendarID: "cal-work")
    let priv = CalendarEvent.stub(id: "b", start: now, calendarID: "cal-private")
    let source = FakeCalendarSource(events: [work, priv])

    let result = try source.events(from: now, to: now.addingTimeInterval(3600),
                                   calendarIDs: ["cal-work"])

    #expect(result.map(\.id) == ["a"])
}

/// Der gefaehrliche Fall: kein Abo darf niemals "alle Kalender" bedeuten.
@Test func fakeSourceReturnsNothingForEmptyCalendarSet() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let work = CalendarEvent.stub(id: "a", start: now, calendarID: "cal-work")
    let priv = CalendarEvent.stub(id: "b", start: now, calendarID: "cal-private")
    let source = FakeCalendarSource(events: [work, priv])

    let result = try source.events(from: now, to: now.addingTimeInterval(3600), calendarIDs: [])

    #expect(result.isEmpty)
}

/// Ein Abo auf einen geloeschten Kalender loest sich nicht auf — und darf
/// deshalb erst recht nicht auf alles zurueckfallen.
@Test func fakeSourceReturnsNothingForUnknownCalendarID() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let work = CalendarEvent.stub(id: "a", start: now, calendarID: "cal-work")
    let source = FakeCalendarSource(events: [work])

    let result = try source.events(from: now, to: now.addingTimeInterval(3600),
                                   calendarIDs: ["cal-geloescht"])

    #expect(result.isEmpty)
}

@Test func fakeSourceCombinesWindowAndCalendarScope() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let source = FakeCalendarSource(events: [
        CalendarEvent.stub(id: "a", start: now.addingTimeInterval(600), calendarID: "cal-work"),
        CalendarEvent.stub(id: "b", start: now.addingTimeInterval(600), calendarID: "cal-private"),
        CalendarEvent.stub(id: "c", start: now.addingTimeInterval(90_000), calendarID: "cal-work"),
    ])

    let result = try source.events(from: now, to: now.addingTimeInterval(3600),
                                   calendarIDs: ["cal-work"])

    #expect(result.map(\.id) == ["a"])
}
