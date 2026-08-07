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

// MARK: - Pause

@Test func pausedYieldsNoAlarmForUpcomingEvent() {
    let event = CalendarEvent.stub(start: now.addingTimeInterval(600))
    var paused = settings()
    paused.paused = true

    #expect(AlarmScheduler.nextAlarm(events: [event], now: now, settings: paused) == nil)
}

@Test func resumingRestoresTheAlarm() {
    let event = CalendarEvent.stub(id: "wieder-scharf", start: now.addingTimeInterval(600))
    var s = settings()
    s.paused = true
    #expect(AlarmScheduler.nextAlarm(events: [event], now: now, settings: s) == nil)

    s.paused = false
    let alarm = AlarmScheduler.nextAlarm(events: [event], now: now, settings: s)
    #expect(alarm?.event.id == "wieder-scharf")
    #expect(alarm?.fireDate == now.addingTimeInterval(480))
}

@Test func pausedAlsoSuppressesTheCatchUpAlarm() {
    // Sonst holte der naechste Scan nach dem Aufwachen den Alarm nach,
    // obwohl der Nutzer ausdruecklich pausiert hat.
    let event = CalendarEvent.stub(start: now.addingTimeInterval(-60))
    var paused = settings(grace: 120)
    paused.paused = true

    #expect(AlarmScheduler.nextAlarm(events: [event], now: now, settings: paused) == nil)
}

// MARK: - Naechster aktueller Termin (Menue)

@Test func relevantEventDropsEventRunningLongerThanGrace() {
    // EventKit liefert laufende Termine mit; ohne diese Regel stuende ein seit
    // einer Viertelstunde laufendes Meeting weiter als "Naechster" im Menue.
    let running = CalendarEvent.stub(id: "laeuft", start: now.addingTimeInterval(-900))
    let upcoming = CalendarEvent.stub(id: "kommt", start: now.addingTimeInterval(1800))

    let next = AlarmScheduler.nextRelevantEvent(
        events: [running, upcoming], now: now, settings: settings()
    )

    #expect(next?.id == "kommt")
}

@Test func relevantEventKeepsEventStartedWithinGrace() {
    let event = CalendarEvent.stub(id: "gerade-erst", start: now.addingTimeInterval(-60))
    let next = AlarmScheduler.nextRelevantEvent(events: [event], now: now, settings: settings())
    #expect(next?.id == "gerade-erst")
}

@Test func relevantEventSkipsHandledEvent() {
    let done = CalendarEvent.stub(id: "erledigt", start: now.addingTimeInterval(300))
    let next = CalendarEvent.stub(id: "danach", start: now.addingTimeInterval(900))

    let result = AlarmScheduler.nextRelevantEvent(
        events: [done, next], now: now, settings: settings(), handled: ["erledigt"]
    )

    #expect(result?.id == "danach")
}

@Test func relevantEventSurvivesPauseAlthoughAlarmDoesNot() {
    // Pausiert heisst: kein Ton. Das Menue zeigt den Termin trotzdem, sonst
    // koennte man aus der Pause heraus nicht mehr beitreten.
    let event = CalendarEvent.stub(id: "trotzdem-sichtbar", start: now.addingTimeInterval(600))
    var paused = settings()
    paused.paused = true

    #expect(
        AlarmScheduler.nextRelevantEvent(events: [event], now: now, settings: paused)?.id
            == "trotzdem-sichtbar"
    )
    #expect(AlarmScheduler.nextAlarm(events: [event], now: now, settings: paused) == nil)
}

// MARK: - Ende des laufenden Alarms

@Test func alarmEndsGraceAfterEventStart() {
    // Regulaerer Alarm: zwei Minuten vor Beginn ausgeloest, endet zwei Minuten
    // nach Beginn — also vier Minuten Laeuten.
    let event = CalendarEvent.stub(start: now.addingTimeInterval(120))
    let end = AlarmScheduler.alarmEndDate(for: event, now: now, settings: settings(grace: 120))
    #expect(end == now.addingTimeInterval(240))
}

@Test func alarmFiringAtEventStartStillEndsAtStartPlusGrace() {
    // Start + Nachfrist liegt hier 120 s entfernt, also mehr als die Untergrenze.
    let event = CalendarEvent.stub(start: now)
    let end = AlarmScheduler.alarmEndDate(for: event, now: now, settings: settings(grace: 120))
    #expect(end == now.addingTimeInterval(120))
}

@Test func catchUpAlarmRingsAtLeastOneMinute() {
    // Nachgeholter Alarm: der Termin laeuft schon 118 s, die strenge Regel gaebe
    // zwei Sekunden Ton. Stattdessen eine Minute ab jetzt.
    let event = CalendarEvent.stub(start: now.addingTimeInterval(-118))
    let end = AlarmScheduler.alarmEndDate(for: event, now: now, settings: settings(grace: 120))
    #expect(end == now.addingTimeInterval(60))
}
