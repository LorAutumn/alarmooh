import Foundation
import Testing
@testable import AlarmoohCore

// MARK: - Aufbau und Lesen der Kennung

@Test func occurrenceIDRoundTripsTheStartDate() {
    let start = Date(timeIntervalSince1970: 1_754_560_800)
    let id = OccurrenceID.make(eventIdentifier: "event-1", start: start)

    #expect(id == "event-1|1754560800")
    #expect(OccurrenceID.startDate(from: id) == start)
}

/// Der Zeitstempel wird auf ganze Sekunden abgeschnitten, damit dieselbe
/// Kennung bei jedem Scan bitgleich herauskommt.
@Test func occurrenceIDDropsSubSecondPrecision() {
    let id = OccurrenceID.make(
        eventIdentifier: "event-1", start: Date(timeIntervalSince1970: 1_000_000.75)
    )
    #expect(id == "event-1|1000000")
}

/// Der eventIdentifier ist eine fremde Zeichenkette und darf selbst ein "|"
/// enthalten — gelesen wird deshalb ab dem letzten.
@Test func occurrenceIDSplitsAtTheLastSeparator() {
    let id = OccurrenceID.make(eventIdentifier: "abc|def", start: Date(timeIntervalSince1970: 42))

    #expect(id == "abc|def|42")
    #expect(OccurrenceID.startDate(from: id) == Date(timeIntervalSince1970: 42))
}

@Test func occurrenceIDWithoutSeparatorHasNoStartDate() {
    #expect(OccurrenceID.startDate(from: "nur-eine-kennung") == nil)
}

@Test func occurrenceIDWithEmptyTimestampHasNoStartDate() {
    #expect(OccurrenceID.startDate(from: "event-1|") == nil)
}

@Test func occurrenceIDWithNonNumericTimestampHasNoStartDate() {
    #expect(OccurrenceID.startDate(from: "event-1|gestern") == nil)
}

// MARK: - Aufraeumen abgelaufener Stummschaltungen

private let now = Date(timeIntervalSince1970: 1_754_560_800)

private func occurrence(daysAgo: Double) -> String {
    OccurrenceID.make(
        eventIdentifier: "event-\(daysAgo)",
        start: now.addingTimeInterval(-daysAgo * 86_400)
    )
}

@Test func expiredMutedOccurrenceIsDropped() {
    let old = occurrence(daysAgo: 8)
    #expect(OccurrenceID.withoutExpired([old], now: now).isEmpty)
}

@Test func recentMutedOccurrenceIsKept() {
    let recent = occurrence(daysAgo: 6)
    #expect(OccurrenceID.withoutExpired([recent], now: now) == [recent])
}

@Test func futureMutedOccurrenceIsKept() {
    let future = occurrence(daysAgo: -3)
    #expect(OccurrenceID.withoutExpired([future], now: now) == [future])
}

/// Genau auf der Grenze bleibt der Eintrag stehen: die Aufbewahrung gilt
/// einschliesslich ihres Endes ("hoechstens sieben Tage alt"), dieselbe Lesart
/// wie bei `catchUpGrace`. Im Zweifel bleibt die Stummschaltung — sie
/// faelschlich zu entfernen hiesse, etwas wieder scharf zu schalten.
@Test func mutedOccurrenceExactlyAtTheBoundaryIsKept() {
    let onBoundary = OccurrenceID.make(
        eventIdentifier: "event-grenze",
        start: now.addingTimeInterval(-OccurrenceID.mutedRetention)
    )
    #expect(OccurrenceID.withoutExpired([onBoundary], now: now) == [onBoundary])
}

/// Eine Sekunde jenseits der Grenze faellt weg — sonst wuerde der Test oben
/// auch bei einer Regel bestehen, die nie etwas entfernt.
@Test func mutedOccurrenceOneSecondPastTheBoundaryIsDropped() {
    let past = OccurrenceID.make(
        eventIdentifier: "event-grenze",
        start: now.addingTimeInterval(-OccurrenceID.mutedRetention - 1)
    )
    #expect(OccurrenceID.withoutExpired([past], now: now).isEmpty)
}

/// Nicht lesbar heisst nicht wegwerfen: sonst wuerde ein Eintrag aus einer
/// aelteren Datei stillschweigend wieder alarmieren.
@Test func unparseableMutedEntryIsKept() {
    let ids: Set<String> = ["kein-zeitstempel", "event-1|", "event-1|gestern"]
    #expect(OccurrenceID.withoutExpired(ids, now: now) == ids)
}

@Test func pruningKeepsRecentAndDropsOldInOnePass() {
    let old = occurrence(daysAgo: 30)
    let recent = occurrence(daysAgo: 1)
    let broken = "kaputte-kennung"

    #expect(OccurrenceID.withoutExpired([old, recent, broken], now: now) == [recent, broken])
}

@Test func pruningEmptySetStaysEmpty() {
    #expect(OccurrenceID.withoutExpired([], now: now).isEmpty)
}

/// Serienkennungen tragen keinen Zeitstempel und werden nie gekuerzt. Der Test
/// haelt das an der Regel fest: selbst wenn eine Serienkennung versehentlich
/// hier ankaeme, bliebe sie stehen.
@Test func seriesIDsAreUntouchedByPruning() {
    var settings = Settings()
    settings.mutedSeriesIDs = ["series-42", "AB12CD34-serie"]
    settings.mutedEventIDs = [occurrence(daysAgo: 99)]

    settings.mutedEventIDs = OccurrenceID.withoutExpired(settings.mutedEventIDs, now: now)

    #expect(settings.mutedEventIDs.isEmpty)
    #expect(settings.mutedSeriesIDs == ["series-42", "AB12CD34-serie"])
    #expect(OccurrenceID.withoutExpired(settings.mutedSeriesIDs, now: now)
        == settings.mutedSeriesIDs)
}

/// Ohne Aenderung muss die Menge gleich bleiben — daran haengt im Koordinator,
/// dass nicht bei jedem Scan die Datei geschrieben wird.
@Test func pruningReportsNoChangeWhenNothingExpired() {
    let ids: Set<String> = [occurrence(daysAgo: 1), occurrence(daysAgo: 6), "kaputt"]
    #expect(OccurrenceID.withoutExpired(ids, now: now) == ids)
}
