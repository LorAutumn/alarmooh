import Foundation
import Testing
@testable import AlarmoohCore

private func settingsSubscribedToWork() -> Settings {
    var s = Settings()
    s.subscribedCalendarIDs = ["cal-work"]
    return s
}

@Test func eventFromSubscribedCalendarPasses() {
    let event = CalendarEvent.stub(calendarID: "cal-work")
    #expect(EventFilter.alarmable([event], settings: settingsSubscribedToWork()).count == 1)
}

@Test func eventFromUnsubscribedCalendarIsDropped() {
    let event = CalendarEvent.stub(calendarID: "cal-private")
    #expect(EventFilter.alarmable([event], settings: settingsSubscribedToWork()).isEmpty)
}

@Test func allDayEventIsDropped() {
    let event = CalendarEvent.stub(calendarID: "cal-work", isAllDay: true)
    #expect(EventFilter.alarmable([event], settings: settingsSubscribedToWork()).isEmpty)
}

@Test func cancelledEventIsDropped() {
    let event = CalendarEvent.stub(calendarID: "cal-work", isCancelled: true)
    #expect(EventFilter.alarmable([event], settings: settingsSubscribedToWork()).isEmpty)
}

@Test func declinedEventIsDropped() {
    let event = CalendarEvent.stub(calendarID: "cal-work", isDeclined: true)
    #expect(EventFilter.alarmable([event], settings: settingsSubscribedToWork()).isEmpty)
}

@Test func mutedSingleEventIsDropped() {
    var settings = settingsSubscribedToWork()
    settings.mutedEventIDs = ["event-1"]
    let event = CalendarEvent.stub(id: "event-1", calendarID: "cal-work")
    #expect(EventFilter.alarmable([event], settings: settings).isEmpty)
}

@Test func mutedSeriesDropsAllOccurrences() {
    var settings = settingsSubscribedToWork()
    settings.mutedSeriesIDs = ["series-42"]
    let first = CalendarEvent.stub(id: "occ-1", seriesID: "series-42", calendarID: "cal-work")
    let second = CalendarEvent.stub(id: "occ-2", seriesID: "series-42", calendarID: "cal-work")
    #expect(EventFilter.alarmable([first, second], settings: settings).isEmpty)
}

@Test func resultIsSortedByStart() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let later = CalendarEvent.stub(id: "b", start: now.addingTimeInterval(600), calendarID: "cal-work")
    let sooner = CalendarEvent.stub(id: "a", start: now, calendarID: "cal-work")
    let result = EventFilter.alarmable([later, sooner], settings: settingsSubscribedToWork())
    #expect(result.map(\.id) == ["a", "b"])
}
