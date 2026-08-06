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
