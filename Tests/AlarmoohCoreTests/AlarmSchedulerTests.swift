import Foundation
import Testing
@testable import AlarmoohCore

private let now = Date(timeIntervalSince1970: 1_000_000)

private func settings(leadTime: TimeInterval = 120, grace: TimeInterval = 120) -> Settings {
    var s = Settings()
    s.subscribedCalendarIDs = ["cal-work"]
    s.leadTime = leadTime
    s.catchUpGrace = grace
    return s
}

@Test func picksEarliestUpcomingEvent() {
    let soon = CalendarEvent.stub(id: "soon", start: now.addingTimeInterval(600))
    let later = CalendarEvent.stub(id: "later", start: now.addingTimeInterval(3600))

    let alarm = AlarmScheduler.nextAlarm(events: [later, soon], now: now, settings: settings())

    #expect(alarm?.event.id == "soon")
}

@Test func fireDateIsStartMinusLeadTime() {
    let event = CalendarEvent.stub(start: now.addingTimeInterval(600))
    let alarm = AlarmScheduler.nextAlarm(events: [event], now: now, settings: settings())
    #expect(alarm?.fireDate == now.addingTimeInterval(480))
}

@Test func longPastEventIsIgnored() {
    let event = CalendarEvent.stub(start: now.addingTimeInterval(-3600))
    #expect(AlarmScheduler.nextAlarm(events: [event], now: now, settings: settings()) == nil)
}

@Test func missedAlarmForEventStartingSoonFiresImmediately() {
    // Rechner war im Ruhezustand: Auslesezeitpunkt liegt 30 s zurueck,
    // der Termin beginnt aber erst in 90 s.
    let event = CalendarEvent.stub(start: now.addingTimeInterval(90))
    let alarm = AlarmScheduler.nextAlarm(events: [event], now: now, settings: settings())
    #expect(alarm?.fireDate == now)
}

@Test func eventStartedWithinGraceStillFires() {
    let event = CalendarEvent.stub(start: now.addingTimeInterval(-60))
    let alarm = AlarmScheduler.nextAlarm(events: [event], now: now, settings: settings())
    #expect(alarm?.fireDate == now)
}

@Test func eventStartedExactlyAtGraceBoundaryStillFires() {
    // "Hoechstens zwei Minuten" schliesst die zwei Minuten ein.
    let event = CalendarEvent.stub(start: now.addingTimeInterval(-120))
    let alarm = AlarmScheduler.nextAlarm(events: [event], now: now, settings: settings(grace: 120))
    #expect(alarm?.fireDate == now)
}

@Test func eventStartingExactlyNowFiresWithoutGrace() {
    let event = CalendarEvent.stub(start: now)
    let alarm = AlarmScheduler.nextAlarm(events: [event], now: now, settings: settings(grace: 0))
    #expect(alarm?.fireDate == now)
}

@Test func eventStartedBeyondGraceIsDropped() {
    let event = CalendarEvent.stub(start: now.addingTimeInterval(-180))
    #expect(AlarmScheduler.nextAlarm(events: [event], now: now, settings: settings()) == nil)
}

@Test func handledEventIsSkipped() {
    let handled = CalendarEvent.stub(id: "done", start: now.addingTimeInterval(300))
    let next = CalendarEvent.stub(id: "next", start: now.addingTimeInterval(900))

    let alarm = AlarmScheduler.nextAlarm(
        events: [handled, next], now: now, settings: settings(), handled: ["done"]
    )

    #expect(alarm?.event.id == "next")
}

@Test func noEventsYieldsNoAlarm() {
    #expect(AlarmScheduler.nextAlarm(events: [], now: now, settings: settings()) == nil)
}
