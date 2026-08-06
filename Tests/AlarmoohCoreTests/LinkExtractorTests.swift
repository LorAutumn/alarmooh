import Foundation
import Testing
@testable import AlarmoohCore

@Test func urlFieldWins() {
    let event = CalendarEvent.stub(
        url: URL(string: "https://meet.google.com/abc-defg-hij"),
        notes: "Fallback https://example.com/other"
    )
    #expect(LinkExtractor.meetingLink(in: event)?.host == "meet.google.com")
}

@Test func findsZoomLinkInNotes() {
    let event = CalendarEvent.stub(notes: "Bitte puenktlich.\nhttps://acme.zoom.us/j/123456 \nDanke")
    #expect(LinkExtractor.meetingLink(in: event)?.absoluteString == "https://acme.zoom.us/j/123456")
}

@Test func findsTeamsLinkInLocation() {
    let event = CalendarEvent.stub(location: "https://teams.microsoft.com/l/meetup-join/xyz")
    #expect(LinkExtractor.meetingLink(in: event)?.host == "teams.microsoft.com")
}

@Test func prefersKnownProviderOverArbitraryLink() {
    let event = CalendarEvent.stub(
        notes: "Agenda: https://wiki.example.com/page und Call: https://meet.google.com/abc-defg-hij"
    )
    #expect(LinkExtractor.meetingLink(in: event)?.host == "meet.google.com")
}

@Test func fallsBackToFirstHTTPSLink() {
    let event = CalendarEvent.stub(notes: "Details unter https://wiki.example.com/page")
    #expect(LinkExtractor.meetingLink(in: event)?.host == "wiki.example.com")
}

@Test func returnsNilWhenNoLinkPresent() {
    #expect(LinkExtractor.meetingLink(in: CalendarEvent.stub(notes: "Kein Link hier")) == nil)
}

// MARK: - Aussortierte Links

@Test func prefersWebexOverLeadingUnsubscribeLink() {
    let event = CalendarEvent.stub(
        notes: """
        Abmelden: https://mail.example.com/unsubscribe?id=42
        Beitreten: https://acme.webex.com/meet/demo
        """
    )
    #expect(
        LinkExtractor.meetingLink(in: event)?.absoluteString
            == "https://acme.webex.com/meet/demo"
    )
}

@Test func unsubscribeOnlyNotesYieldNoLink() {
    let event = CalendarEvent.stub(
        notes: "Newsletter-Termin. Abmelden: https://mail.example.com/unsubscribe?id=42"
    )
    #expect(LinkExtractor.meetingLink(in: event) == nil)
}

@Test func prefersJitsiOverIntranetLink() {
    let event = CalendarEvent.stub(
        notes: "Protokoll: https://intranet.example.com/seite\nCall: https://meet.jit.si/alarmooh"
    )
    #expect(LinkExtractor.meetingLink(in: event)?.host == "meet.jit.si")
}

@Test func prefersGoToMeetingOverDocumentLink() {
    let event = CalendarEvent.stub(
        notes: """
        Agenda: https://docs.google.com/document/d/abc
        https://global.gotomeeting.com/join/123456789
        """
    )
    #expect(LinkExtractor.meetingLink(in: event)?.host == "global.gotomeeting.com")
}

// MARK: - Rohdaten des Detektors

@Test func unescapesHTMLEntitiesInZoomLink() {
    let event = CalendarEvent.stub(
        notes: "https://acme.zoom.us/j/123456?pwd=geheim&amp;uname=demo"
    )
    #expect(
        LinkExtractor.meetingLink(in: event)?.absoluteString
            == "https://acme.zoom.us/j/123456?pwd=geheim&uname=demo"
    )
}

@Test func bareDomainInProseIsNotALink() {
    let event = CalendarEvent.stub(
        notes: "wir sprechen ueber die Migration von wiki.example.com auf confluence"
    )
    #expect(LinkExtractor.meetingLink(in: event) == nil)
}
