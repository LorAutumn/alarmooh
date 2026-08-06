import Foundation
import Testing
@testable import AlarmoohCore

@Test func fakeSourceReturnsEventsInWindow() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let inside = CalendarEvent.stub(id: "a", start: now.addingTimeInterval(600))
    let outside = CalendarEvent.stub(id: "b", start: now.addingTimeInterval(90_000))
    let source = FakeCalendarSource(events: [inside, outside])

    let result = try source.events(from: now, to: now.addingTimeInterval(3600))

    #expect(result.map(\.id) == ["a"])
}
