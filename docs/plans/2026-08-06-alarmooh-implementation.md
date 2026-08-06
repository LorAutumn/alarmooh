# alarmooh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eine eigenständige macOS-Menüleisten-App bauen, die zwei Minuten vor wichtigen Kalenderterminen einen schleifenden Alarmton startet und den Meeting-Link zum Beitreten anbietet.

**Architecture:** Zwei SPM-Targets. `AlarmoohCore` enthält die gesamte UI-freie Logik (Kalenderprotokoll, Filter, Link-Extraktion, Scheduler, Einstellungen) und wird per TDD entwickelt. Das Executable `alarmooh` enthält AppKit-UI, EventKit-Adapter, Audio und CoreAudio-Lautstärke und wird von Hand verifiziert. Kein Backend, kein Netzwerkzugriff.

**Tech Stack:** Swift 6.3, SwiftPM, AppKit + SwiftUI, EventKit, AVFoundation, CoreAudio, ServiceManagement, swift-testing (als Paket-Dependency).

**Design-Grundlage:** `docs/plans/2026-08-06-alarmooh-design.md`

---

## Vorbedingungen der Umgebung (verifiziert am 2026-08-06)

| Prüfung | Ergebnis |
|---|---|
| macOS | 26.6, SDK 26.5 |
| Swift | 6.3.3 |
| Xcode | **nicht installiert**, nur Command Line Tools |
| AppKit/SwiftUI/EventKit/CoreAudio/ServiceManagement kompilieren | ja, mit CLT |
| `import XCTest` | **schlägt fehl** — kein Modul in den CLT |
| `import Testing` aus der Toolchain | **schlägt fehl** — kein Modul in den CLT |
| swift-testing als SPM-Dependency | **funktioniert**, `swift test` läuft grün |

**Konsequenz:** Das Paket bindet `https://github.com/swiftlang/swift-testing.git` explizit ein. Die Toolchain gibt dabei die Warnung aus, Swift Testing sei bereits im Swift-6-Toolchain enthalten — das gilt für Xcode-Toolchains, nicht für die Command Line Tools. Die Warnung ist hier kosmetisch und wird bewusst in Kauf genommen. Sollte später doch Xcode installiert werden, kann die Dependency ersatzlos entfallen; die Testdateien bleiben unverändert.

**Alle im Plan verwendeten APIs wurden vorab gegen die installierte SDK kompiliert.**

---

## Task 1: Projektgerüst

**Files:**
- Create: `Package.swift`
- Create: `Sources/AlarmoohCore/Placeholder.swift`
- Create: `Sources/alarmooh/main.swift`
- Create: `Tests/AlarmoohCoreTests/PlaceholderTests.swift`

**Step 1: Package.swift anlegen**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "alarmooh",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Nur noetig, solange kein vollstaendiges Xcode installiert ist:
        // die Command Line Tools liefern weder XCTest noch Testing mit.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .target(name: "AlarmoohCore"),
        .executableTarget(name: "alarmooh", dependencies: ["AlarmoohCore"]),
        .testTarget(
            name: "AlarmoohCoreTests",
            dependencies: ["AlarmoohCore", .product(name: "Testing", package: "swift-testing")]
        ),
    ]
)
```

**Step 2: Platzhalterdateien anlegen**

`Sources/AlarmoohCore/Placeholder.swift`:
```swift
public enum Alarmooh {
    public static let name = "alarmooh"
}
```

`Sources/alarmooh/main.swift`:
```swift
import AlarmoohCore

print(Alarmooh.name)
```

`Tests/AlarmoohCoreTests/PlaceholderTests.swift`:
```swift
import Testing
@testable import AlarmoohCore

@Test func packageNameIsSet() {
    #expect(Alarmooh.name == "alarmooh")
}
```

**Step 3: Bauen und testen**

Run: `swift build && swift test`
Expected: `Build complete!` und `Test run with 1 test passed`. Der erste Lauf lädt swift-testing und dauert ein bis zwei Minuten.

**Step 4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: add SPM package skeleton with swift-testing"
```

---

## Task 2: Domänenmodelle und Kalenderprotokoll

**Files:**
- Create: `Sources/AlarmoohCore/CalendarEvent.swift`
- Create: `Sources/AlarmoohCore/CalendarSource.swift`
- Create: `Sources/AlarmoohCore/FakeCalendarSource.swift`
- Create: `Tests/AlarmoohCoreTests/FakeCalendarSourceTests.swift`
- Delete: `Sources/AlarmoohCore/Placeholder.swift`, `Tests/AlarmoohCoreTests/PlaceholderTests.swift`

**Step 1: Failing test schreiben**

`Tests/AlarmoohCoreTests/FakeCalendarSourceTests.swift`:
```swift
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
```

`CalendarEvent.stub` ist ein Test-Helper, der gleich mit angelegt wird — er hält die Tests kurz und ist der einzige Ort, an dem Beispieldaten definiert werden.

**Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `swift test`
Expected: FAIL mit `cannot find 'FakeCalendarSource' in scope`.

**Step 3: Minimale Implementierung**

`Sources/AlarmoohCore/CalendarEvent.swift`:
```swift
import Foundation

/// Ein Kalender, wie ihn der Nutzer in den Einstellungen abonnieren kann.
public struct CalendarInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Ein einzelnes Vorkommen eines Termins, losgeloest von EventKit.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// Kennung dieses Vorkommens (EventKit: eventIdentifier).
    public let id: String
    /// Stabile Kennung der Serie (EventKit: calendarItemExternalIdentifier).
    /// Nil bei Einzelterminen ohne Serienbezug.
    public let seriesID: String?
    public let title: String
    public let start: Date
    public let calendarID: String
    public let calendarTitle: String
    public let isAllDay: Bool
    public let isCancelled: Bool
    /// Der Nutzer selbst hat abgesagt.
    public let isDeclined: Bool
    public let url: URL?
    public let notes: String?
    public let location: String?

    public init(
        id: String,
        seriesID: String? = nil,
        title: String,
        start: Date,
        calendarID: String,
        calendarTitle: String,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        url: URL? = nil,
        notes: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.title = title
        self.start = start
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
        self.url = url
        self.notes = notes
        self.location = location
    }
}
```

`Sources/AlarmoohCore/CalendarSource.swift`:
```swift
import Foundation

/// Liefert Termine. Produktiv per EventKit, im Test per Fake.
public protocol CalendarSource: Sendable {
    func calendars() throws -> [CalendarInfo]
    func events(from: Date, to: Date) throws -> [CalendarEvent]
}
```

`Sources/AlarmoohCore/FakeCalendarSource.swift`:
```swift
import Foundation

/// Nur fuer Tests und den Debug-Modus der App.
public struct FakeCalendarSource: CalendarSource {
    public var calendarList: [CalendarInfo]
    public var events: [CalendarEvent]

    public init(calendars: [CalendarInfo] = [], events: [CalendarEvent] = []) {
        self.calendarList = calendars
        self.events = events
    }

    public func calendars() throws -> [CalendarInfo] { calendarList }

    public func events(from: Date, to: Date) throws -> [CalendarEvent] {
        events
            .filter { $0.start >= from && $0.start < to }
            .sorted { $0.start < $1.start }
    }
}

extension CalendarEvent {
    /// Beispieldaten fuer Tests. Bewusst im Produktiv-Target, damit alle
    /// Testdateien denselben Helfer nutzen.
    public static func stub(
        id: String = "event-1",
        seriesID: String? = nil,
        title: String = "Standup",
        start: Date = Date(timeIntervalSince1970: 1_000_000),
        calendarID: String = "cal-work",
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        url: URL? = nil,
        notes: String? = nil,
        location: String? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: id, seriesID: seriesID, title: title, start: start,
            calendarID: calendarID, calendarTitle: "Arbeit",
            isAllDay: isAllDay, isCancelled: isCancelled, isDeclined: isDeclined,
            url: url, notes: notes, location: location
        )
    }
}
```

**Step 4: Platzhalter löschen und Test laufen lassen**

```bash
rm Sources/AlarmoohCore/Placeholder.swift Tests/AlarmoohCoreTests/PlaceholderTests.swift
```

`Sources/alarmooh/main.swift` auf `print("alarmooh")` reduzieren, damit das Executable weiter baut.

Run: `swift test`
Expected: PASS, 1 Test.

**Step 5: Commit**

```bash
git add Sources/AlarmoohCore Sources/alarmooh Tests/AlarmoohCoreTests
git commit -m "feat: add calendar domain model and source protocol"
```

---

## Task 3: Einstellungen mit Persistenz

**Files:**
- Create: `Sources/AlarmoohCore/Settings.swift`
- Create: `Sources/AlarmoohCore/SettingsStore.swift`
- Create: `Tests/AlarmoohCoreTests/SettingsStoreTests.swift`

**Step 1: Failing tests schreiben**

```swift
import Foundation
import Testing
@testable import AlarmoohCore

private func tempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("alarmooh-test-\(UUID().uuidString).json")
}

@Test func loadingMissingFileYieldsDefaults() throws {
    let store = SettingsStore(fileURL: tempURL())
    #expect(store.load() == Settings())
}

@Test func settingsSurviveARoundTrip() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = SettingsStore(fileURL: url)

    var settings = Settings()
    settings.subscribedCalendarIDs = ["cal-work"]
    settings.mutedSeriesIDs = ["series-42"]
    settings.leadTime = 300
    try store.save(settings)

    #expect(SettingsStore(fileURL: url).load() == settings)
}

@Test func corruptFileFallsBackToDefaults() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("kein json".utf8).write(to: url)

    #expect(SettingsStore(fileURL: url).load() == Settings())
}

@Test func defaultLeadTimeIsTwoMinutes() {
    #expect(Settings().leadTime == 120)
}
```

**Step 2: Tests laufen lassen**

Run: `swift test`
Expected: FAIL mit `cannot find 'SettingsStore' in scope`.

**Step 3: Implementierung**

`Sources/AlarmoohCore/Settings.swift`:
```swift
import Foundation

public struct Settings: Codable, Equatable, Sendable {
    /// Kalender, deren Termine alarmieren. Leer bedeutet: nichts alarmiert.
    public var subscribedCalendarIDs: Set<String> = []
    /// Einzelne stummgeschaltete Vorkommen.
    public var mutedEventIDs: Set<String> = []
    /// Stummgeschaltete Serien; gilt fuer alle kuenftigen Vorkommen.
    public var mutedSeriesIDs: Set<String> = []
    /// Vorlauf vor Terminbeginn.
    public var leadTime: TimeInterval = 120
    /// Auf diesen Wert wird die Systemlautstaerke beim Alarm mindestens angehoben.
    public var minimumVolume: Float = 0.8
    /// Pfad zur Audiodatei; nil bedeutet: erzeugten Fallback-Ton verwenden.
    public var soundPath: String?
    /// Sicherheitstakt fuer den Kalender-Scan.
    public var scanInterval: TimeInterval = 1800
    /// Wie lange nach dem eigentlichen Auslesezeitpunkt ein verpasster Alarm
    /// noch nachgeholt werden darf, gemessen ab Terminbeginn.
    public var catchUpGrace: TimeInterval = 120
    public var launchAtLogin: Bool = false

    public init() {}
}
```

`Sources/AlarmoohCore/SettingsStore.swift`:
```swift
import Foundation

/// Liest und schreibt die Einstellungen als lesbares JSON.
public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Standardort: ~/Library/Application Support/alarmooh/settings.json
    public static func standard() -> SettingsStore {
        SettingsStore(fileURL: Self.supportDirectory().appendingPathComponent("settings.json"))
    }

    public static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("alarmooh", isDirectory: true)
    }

    /// Defekte oder fehlende Datei ergibt Standardwerte — die App soll
    /// deswegen nicht stehenbleiben.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
```

**Step 4: Tests laufen lassen**

Run: `swift test`
Expected: PASS, 5 Tests.

**Step 5: Commit**

```bash
git add Sources/AlarmoohCore/Settings.swift Sources/AlarmoohCore/SettingsStore.swift Tests/AlarmoohCoreTests/SettingsStoreTests.swift
git commit -m "feat: add settings model with JSON persistence"
```

---

## Task 4: Terminfilter (Opt-out-Regeln)

**Files:**
- Create: `Sources/AlarmoohCore/EventFilter.swift`
- Create: `Tests/AlarmoohCoreTests/EventFilterTests.swift`

**Step 1: Failing tests schreiben**

```swift
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
```

**Step 2: Tests laufen lassen**

Run: `swift test`
Expected: FAIL mit `cannot find 'EventFilter' in scope`.

**Step 3: Implementierung**

```swift
import Foundation

/// Setzt das Opt-out-Modell um: abonnierte Kalender alarmieren vollstaendig,
/// einzelne Termine und Serien lassen sich stummschalten.
public enum EventFilter {
    public static func alarmable(_ events: [CalendarEvent], settings: Settings) -> [CalendarEvent] {
        events
            .filter { settings.subscribedCalendarIDs.contains($0.calendarID) }
            .filter { !$0.isAllDay && !$0.isCancelled && !$0.isDeclined }
            .filter { !settings.mutedEventIDs.contains($0.id) }
            .filter { event in
                guard let seriesID = event.seriesID else { return true }
                return !settings.mutedSeriesIDs.contains(seriesID)
            }
            .sorted { $0.start < $1.start }
    }
}
```

**Step 4: Tests laufen lassen**

Run: `swift test`
Expected: PASS, 13 Tests.

**Step 5: Commit**

```bash
git add Sources/AlarmoohCore/EventFilter.swift Tests/AlarmoohCoreTests/EventFilterTests.swift
git commit -m "feat: add opt-out event filter"
```

---

## Task 5: Meeting-Link-Erkennung

Statt eigener Regex-Bastelei wird `NSDataDetector` aus Foundation verwendet — URL-Erkennung ist kein Kernproblem dieser App.

**Files:**
- Create: `Sources/AlarmoohCore/LinkExtractor.swift`
- Create: `Tests/AlarmoohCoreTests/LinkExtractorTests.swift`

**Step 1: Failing tests schreiben**

```swift
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
```

**Step 2: Tests laufen lassen**

Run: `swift test`
Expected: FAIL mit `cannot find 'LinkExtractor' in scope`.

**Step 3: Implementierung**

```swift
import Foundation

/// Findet die Meeting-URL eines Termins.
public enum LinkExtractor {
    /// Hosts, die als echte Meeting-Anbieter gelten und Vorrang haben.
    static let knownHosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com",
    ]

    public static func meetingLink(in event: CalendarEvent) -> URL? {
        if let url = event.url, isUsable(url) { return url }

        // Reihenfolge der Design-Entscheidung: URL-Feld, Notizen, Ort.
        let haystack = [event.notes, event.location].compactMap { $0 }.joined(separator: "\n")
        let candidates = urls(in: haystack)

        return candidates.first(where: isKnownProvider) ?? candidates.first
    }

    static func urls(in text: String) -> [URL] {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .filter(isUsable)
    }

    static func isUsable(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http"
    }

    static func isKnownProvider(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return knownHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
```

**Step 4: Tests laufen lassen**

Run: `swift test`
Expected: PASS, 19 Tests.

**Step 5: Commit**

```bash
git add Sources/AlarmoohCore/LinkExtractor.swift Tests/AlarmoohCoreTests/LinkExtractorTests.swift
git commit -m "feat: extract meeting links from event fields"
```

---

## Task 6: Alarm-Scheduler

Das Herzstück: Aus einer Terminliste, der aktuellen Zeit und den bereits erledigten Alarmen wird genau ein nächster Alarm bestimmt. Die Nachholregel für verpasste Alarme steckt ebenfalls hier — deshalb ist sie testbar.

**Files:**
- Create: `Sources/AlarmoohCore/AlarmScheduler.swift`
- Create: `Tests/AlarmoohCoreTests/AlarmSchedulerTests.swift`

**Step 1: Failing tests schreiben**

```swift
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
```

**Step 2: Tests laufen lassen**

Run: `swift test`
Expected: FAIL mit `cannot find 'AlarmScheduler' in scope`.

**Step 3: Implementierung**

```swift
import Foundation

public struct PendingAlarm: Equatable, Sendable {
    public let event: CalendarEvent
    /// Zeitpunkt, zu dem der Alarm ausgeloest werden soll. Liegt der regulaere
    /// Zeitpunkt in der Vergangenheit (Ruhezustand), ist es "jetzt".
    public let fireDate: Date

    public init(event: CalendarEvent, fireDate: Date) {
        self.event = event
        self.fireDate = fireDate
    }
}

public enum AlarmScheduler {
    /// Bestimmt den naechsten faelligen Alarm.
    ///
    /// - `handled` enthaelt Termine, deren Alarm bereits lief und abgestellt wurde.
    /// - Termine, deren Beginn laenger als `catchUpGrace` zurueckliegt, entfallen.
    public static func nextAlarm(
        events: [CalendarEvent],
        now: Date,
        settings: Settings,
        handled: Set<String> = []
    ) -> PendingAlarm? {
        events
            .filter { !handled.contains($0.id) }
            .filter { $0.start > now.addingTimeInterval(-settings.catchUpGrace) }
            .sorted { $0.start < $1.start }
            .first
            .map { event in
                let regular = event.start.addingTimeInterval(-settings.leadTime)
                return PendingAlarm(event: event, fireDate: max(regular, now))
            }
    }
}
```

**Step 4: Tests laufen lassen**

Run: `swift test`
Expected: PASS, 27 Tests.

**Step 5: Commit**

```bash
git add Sources/AlarmoohCore/AlarmScheduler.swift Tests/AlarmoohCoreTests/AlarmSchedulerTests.swift
git commit -m "feat: add alarm scheduler with catch-up rule"
```

---

## Task 7: Fallback-Ton erzeugen

Damit die App ohne fremdes Audiomaterial lauffähig ist, erzeugt sie beim ersten Start selbst einen zweitönigen Gong als WAV-Datei. Der Nutzer kann ihn später durch eine eigene Datei ersetzen.

**Files:**
- Create: `Sources/AlarmoohCore/ToneGenerator.swift`
- Create: `Tests/AlarmoohCoreTests/ToneGeneratorTests.swift`

**Step 1: Failing tests schreiben**

```swift
import AVFoundation
import Foundation
import Testing
@testable import AlarmoohCore

@Test func generatesPlayableWavFile() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("alarmooh-tone-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }

    try ToneGenerator.writeFallbackTone(to: url)

    let file = try AVAudioFile(forReading: url)
    let seconds = Double(file.length) / file.fileFormat.sampleRate
    #expect(seconds > 1.0)
    #expect(seconds < 4.0)
}
```

**Step 2: Tests laufen lassen**

Run: `swift test`
Expected: FAIL mit `cannot find 'ToneGenerator' in scope`.

**Step 3: Implementierung**

```swift
import AVFoundation
import Foundation

/// Erzeugt den mitgelieferten Ersatzton. Bewusst selbst erzeugt statt als
/// Audiodatei im Repository: fremdes Tonmaterial gehoert nicht ins Git.
public enum ToneGenerator {
    /// Zwei absteigende Toene, wie ein schlichtes Stationssignal.
    public static func writeFallbackTone(to url: URL) throws {
        let sampleRate = 44_100.0
        let noteDuration = 0.55
        let frequencies: [Double] = [987.77, 659.25]  // H5, E5

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw ToneError.formatUnavailable
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        for frequency in frequencies {
            let frames = AVAudioFrameCount(sampleRate * noteDuration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = buffer.floatChannelData?[0]
            else { throw ToneError.bufferUnavailable }
            buffer.frameLength = frames

            for frame in 0..<Int(frames) {
                let t = Double(frame) / sampleRate
                // Exponentiell abklingende Huellkurve, damit es nach Glocke klingt.
                let envelope = exp(-3.0 * t / noteDuration)
                samples[frame] = Float(sin(2 * .pi * frequency * t) * envelope * 0.9)
            }
            try file.write(from: buffer)
        }
    }

    enum ToneError: Error {
        case formatUnavailable
        case bufferUnavailable
    }
}
```

**Step 4: Tests laufen lassen**

Run: `swift test`
Expected: PASS, 28 Tests.

**Step 5: Commit**

```bash
git add Sources/AlarmoohCore/ToneGenerator.swift Tests/AlarmoohCoreTests/ToneGeneratorTests.swift
git commit -m "feat: generate fallback alarm tone"
```

---

## Task 8: Lautstärke-Schnappschuss persistieren

Die CoreAudio-Anbindung kommt in Task 11. Der testbare Teil — den vorherigen Lautstärkezustand über einen Absturz hinweg zu merken — gehört in den Core.

**Files:**
- Create: `Sources/AlarmoohCore/VolumeSnapshot.swift`
- Create: `Tests/AlarmoohCoreTests/VolumeSnapshotTests.swift`

**Step 1: Failing tests schreiben**

```swift
import Foundation
import Testing
@testable import AlarmoohCore

private func tempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("alarmooh-vol-\(UUID().uuidString).json")
}

@Test func snapshotRoundTrips() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = VolumeSnapshotStore(fileURL: url)

    try store.save(VolumeSnapshot(volume: 0.25, muted: true))

    #expect(store.load() == VolumeSnapshot(volume: 0.25, muted: true))
}

@Test func clearRemovesSnapshot() throws {
    let url = tempURL()
    let store = VolumeSnapshotStore(fileURL: url)
    try store.save(VolumeSnapshot(volume: 0.5, muted: false))

    store.clear()

    #expect(store.load() == nil)
}

@Test func loadWithoutFileYieldsNil() {
    #expect(VolumeSnapshotStore(fileURL: tempURL()).load() == nil)
}
```

**Step 2: Tests laufen lassen**

Run: `swift test`
Expected: FAIL mit `cannot find 'VolumeSnapshotStore' in scope`.

**Step 3: Implementierung**

```swift
import Foundation

public struct VolumeSnapshot: Codable, Equatable, Sendable {
    public let volume: Float
    public let muted: Bool

    public init(volume: Float, muted: Bool) {
        self.volume = volume
        self.muted = muted
    }
}

/// Haelt den Lautstaerkezustand vor einem Alarm fest, damit ein Absturz
/// waehrend des Alarms die Systemlautstaerke nicht dauerhaft oben laesst.
public struct VolumeSnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func standard() -> VolumeSnapshotStore {
        VolumeSnapshotStore(
            fileURL: SettingsStore.supportDirectory().appendingPathComponent("volume-snapshot.json")
        )
    }

    public func load() -> VolumeSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(VolumeSnapshot.self, from: data)
    }

    public func save(_ snapshot: VolumeSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

**Step 4: Tests laufen lassen**

Run: `swift test`
Expected: PASS, 31 Tests.

**Step 5: Commit**

```bash
git add Sources/AlarmoohCore/VolumeSnapshot.swift Tests/AlarmoohCoreTests/VolumeSnapshotTests.swift
git commit -m "feat: persist volume snapshot across crashes"
```

**Damit ist der komplette testbare Kern fertig. Ab hier folgt die App-Schicht, die von Hand verifiziert wird.**

---

## Task 9: App-Bundle, Info.plist, Makefile

Ohne signiertes Bundle gibt EventKit keine Daten heraus. Das muss stehen, bevor der EventKit-Adapter sinnvoll geprüft werden kann.

**Files:**
- Create: `Resources/Info.plist`
- Create: `Makefile`
- Modify: `Sources/alarmooh/main.swift`

**Step 1: Info.plist anlegen**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>alarmooh</string>
    <key>CFBundleDisplayName</key>     <string>alarmooh</string>
    <key>CFBundleIdentifier</key>      <string>io.github.lorautumn.alarmooh</string>
    <key>CFBundleExecutable</key>      <string>alarmooh</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>alarmooh liest deine Termine, um dich rechtzeitig vor Meetings zu warnen.</string>
</dict>
</plist>
```

`LSUIElement` sorgt dafür, dass kein Dock-Icon und kein App-Switcher-Eintrag erscheint.

**Step 2: Makefile anlegen**

```make
BUNDLE     := Alarmooh.app
BUNDLE_ID  := io.github.lorautumn.alarmooh
BINARY     := .build/release/alarmooh

.PHONY: build test bundle run clean

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/alarmooh
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(BUNDLE)

run: bundle
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
```

`open` statt direktem Aufruf der Binary: Nur so registriert LaunchServices das Bundle korrekt, was für die Kalenderberechtigung nötig ist.

**Step 3: main.swift als minimale AppKit-App**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // kein Dock-Icon
app.run()
```

`Sources/alarmooh/AppDelegate.swift` (vorläufig):
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("alarmooh gestartet")
    }
}
```

**Step 4: Bauen und starten**

Run: `make bundle && open Alarmooh.app`
Expected: Kein Fehler, kein Dock-Icon. Prüfen mit:
`log show --last 1m --predicate 'eventMessage CONTAINS "alarmooh gestartet"' | tail -3`
Danach beenden: `pkill -f Alarmooh.app`

**Step 5: Commit**

```bash
git add Makefile Resources/Info.plist Sources/alarmooh
git commit -m "build: add app bundle target with ad-hoc signing"
```

---

## Task 10: EventKit-Adapter

**Files:**
- Create: `Sources/alarmooh/EventKitCalendarSource.swift`
- Modify: `Sources/alarmooh/AppDelegate.swift`

Der Adapter liegt bewusst im App-Target, nicht im Core: Er lässt sich ohne Bundle und ohne erteilte Berechtigung nicht sinnvoll testen, und der Core soll frei von EventKit bleiben.

**Step 1: Adapter schreiben**

```swift
import AlarmoohCore
import EventKit
import Foundation

final class EventKitCalendarSource: CalendarSource, @unchecked Sendable {
    private let store = EKEventStore()

    /// Einmalige Nachfrage beim Nutzer. Ergebnis wird von macOS gemerkt.
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func calendars() throws -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title < $1.title }
    }

    func events(from: Date, to: Date) throws -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .map(Self.convert)
            .sorted { $0.start < $1.start }
    }

    static func convert(_ event: EKEvent) -> CalendarEvent {
        let declined = event.attendees?
            .first(where: \.isCurrentUser)?
            .participantStatus == .declined

        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            seriesID: event.hasRecurrenceRules ? event.calendarItemExternalIdentifier : nil,
            title: event.title ?? "Termin",
            start: event.startDate,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled,
            isDeclined: declined,
            url: event.url,
            notes: event.notes,
            location: event.location
        )
    }
}
```

**Step 2: Im AppDelegate probeweise auslesen**

```swift
import AlarmoohCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let source = EventKitCalendarSource()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            guard await source.requestAccess() else {
                NSLog("alarmooh: Kalenderzugriff verweigert")
                return
            }
            let calendars = (try? source.calendars()) ?? []
            NSLog("alarmooh: %d Kalender gefunden: %@",
                  calendars.count, calendars.map(\.title).joined(separator: ", "))

            let now = Date()
            let events = (try? source.events(from: now, to: now.addingTimeInterval(86_400))) ?? []
            NSLog("alarmooh: %d Termine in den naechsten 24 h", events.count)
        }
    }
}
```

**Step 3: Manuell verifizieren**

Run: `make run`
Expected: macOS fragt einmalig nach Kalenderzugriff mit dem Text aus der Info.plist. Nach dem Erlauben:

```bash
log show --last 2m --predicate 'eventMessage CONTAINS "alarmooh:"' --style compact | tail -5
```
Expected: Zeilen mit Kalenderanzahl und Terminanzahl. Kommt stattdessen „Kalenderzugriff verweigert", in den Systemeinstellungen unter Datenschutz → Kalender nachsehen.

Danach: `pkill -f Alarmooh.app`

**Step 4: Commit**

```bash
git add Sources/alarmooh/EventKitCalendarSource.swift Sources/alarmooh/AppDelegate.swift
git commit -m "feat: read calendars and events via EventKit"
```

---

## Task 11: Ton und Systemlautstärke

**Files:**
- Create: `Sources/alarmooh/AlarmPlayer.swift`
- Create: `Sources/alarmooh/SystemVolumeController.swift`

**Step 1: SystemVolumeController schreiben**

```swift
import AlarmoohCore
import CoreAudio
import Foundation

/// Hebt die Ausgabelautstaerke fuer die Dauer eines Alarms an und stellt den
/// vorherigen Zustand danach wieder her.
final class SystemVolumeController {
    private let snapshots = VolumeSnapshotStore.standard()

    /// Beim Start aufrufen: Falls ein Alarm durch einen Absturz beendet wurde,
    /// steht die Lautstaerke noch oben.
    func restoreAfterCrashIfNeeded() {
        guard let snapshot = snapshots.load() else { return }
        apply(snapshot)
        snapshots.clear()
    }

    func raise(to minimum: Float) {
        guard let current = currentSnapshot() else { return }
        try? snapshots.save(current)
        if current.muted { setMuted(false) }
        if current.volume < minimum { setVolume(minimum) }
    }

    func restore() {
        guard let snapshot = snapshots.load() else { return }
        apply(snapshot)
        snapshots.clear()
    }

    private func apply(_ snapshot: VolumeSnapshot) {
        setVolume(snapshot.volume)
        setMuted(snapshot.muted)
    }

    private func currentSnapshot() -> VolumeSnapshot? {
        guard let volume = getVolume() else { return nil }
        return VolumeSnapshot(volume: volume, muted: getMuted() ?? false)
    }

    // MARK: - CoreAudio

    private var outputDevice: AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func getVolume() -> Float? {
        guard let device = outputDevice else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress()
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func setVolume(_ value: Float) {
        guard let device = outputDevice else { return }
        var newValue = Float32(min(max(value, 0), 1))
        var address = volumeAddress()
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &newValue
        )
    }

    private func getMuted() -> Bool? {
        guard let device = outputDevice else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress()
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value == 1 : nil
    }

    private func setMuted(_ muted: Bool) {
        guard let device = outputDevice else { return }
        var value: UInt32 = muted ? 1 : 0
        var address = muteAddress()
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }
}
```

Hinweis für die Umsetzung: Nicht jedes Ausgabegerät unterstützt jede Property — Bluetooth-Kopfhörer liefern für `Mute` gelegentlich einen Fehler. Alle Zugriffe sind deshalb fehlertolerant und tun im Zweifel nichts, statt abzustürzen.

**Step 2: AlarmPlayer schreiben**

```swift
import AlarmoohCore
import AVFoundation
import Foundation

/// Spielt den Alarmton in Endlosschleife, bis `stop()` gerufen wird.
final class AlarmPlayer {
    private var player: AVAudioPlayer?
    private let volumeController = SystemVolumeController()

    var isPlaying: Bool { player?.isPlaying ?? false }

    func start(settings: Settings) {
        stop()
        guard let url = try? soundURL(for: settings) else { return }
        volumeController.raise(to: settings.minimumVolume)

        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1   // endlos, wie im Design festgelegt
        player?.volume = 1.0
        player?.prepareToPlay()
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
        volumeController.restore()
    }

    func restoreVolumeAfterCrashIfNeeded() {
        volumeController.restoreAfterCrashIfNeeded()
    }

    /// Eigene Datei des Nutzers, sonst der erzeugte Ersatzton.
    private func soundURL(for settings: Settings) throws -> URL {
        if let path = settings.soundPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let fallback = SettingsStore.supportDirectory().appendingPathComponent("fallback-tone.wav")
        if !FileManager.default.fileExists(atPath: fallback.path) {
            try FileManager.default.createDirectory(
                at: fallback.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try ToneGenerator.writeFallbackTone(to: fallback)
        }
        return fallback
    }
}
```

**Step 3: Manuell verifizieren**

Im `AppDelegate` vorübergehend nach dem Start `player.start(settings: Settings())` und nach 5 Sekunden `player.stop()` aufrufen.

Run: `make run`
Expected: Systemlautstärke springt auf 80 %, zweitöniger Gong läuft in Schleife, nach 5 s Stille und die alte Lautstärke ist zurück. Prüfen lässt sich das auch an der Lautstärkeanzeige in der Menüleiste.

Danach den Testaufruf wieder entfernen.

**Step 4: Commit**

```bash
git add Sources/alarmooh/AlarmPlayer.swift Sources/alarmooh/SystemVolumeController.swift
git commit -m "feat: loop alarm tone and raise system volume"
```

---

## Task 12: Menüleisten-Icon und Alarm-Panel

**Files:**
- Create: `Sources/alarmooh/StatusItemController.swift`
- Create: `Sources/alarmooh/AlarmPanelController.swift`
- Create: `Sources/alarmooh/AlarmView.swift`

**Step 1: StatusItemController**

```swift
import AlarmoohCore
import AppKit

final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = { NSApp.terminate(nil) }
    /// Klick aufs Icon waehrend eines Alarms stellt ihn ab.
    var onIconClickedDuringAlarm: (() -> Void)?

    init() {
        item.button?.image = NSImage(
            systemSymbolName: "bell.badge", accessibilityDescription: "alarmooh"
        )
        item.button?.image?.isTemplate = true
        rebuildMenu(nextEvent: nil)
    }

    /// Position des Icons in Bildschirmkoordinaten — das Panel haengt sich darunter.
    var iconFrameOnScreen: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func setAlarming(_ alarming: Bool) {
        item.button?.contentTintColor = alarming ? .systemRed : nil
    }

    func rebuildMenu(nextEvent: CalendarEvent?) {
        let menu = NSMenu()
        if let event = nextEvent {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            menu.addItem(
                withTitle: "Naechster: \(event.title) um \(formatter.string(from: event.start))",
                action: nil, keyEquivalent: ""
            )
        } else {
            menu.addItem(withTitle: "Kein ueberwachter Termin", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Einstellungen…",
            action: #selector(MenuActions.openSettings), keyEquivalent: ","
        ).target = actions
        menu.addItem(
            withTitle: "alarmooh beenden",
            action: #selector(MenuActions.quit), keyEquivalent: "q"
        ).target = actions
        item.menu = menu
    }

    private lazy var actions = MenuActions(owner: self)

    final class MenuActions: NSObject {
        weak var owner: StatusItemController?
        init(owner: StatusItemController) { self.owner = owner }
        @objc func openSettings() { owner?.onOpenSettings() }
        @objc func quit() { owner?.onQuit() }
    }
}
```

**Step 2: AlarmView (SwiftUI)**

```swift
import AlarmoohCore
import SwiftUI

struct AlarmView: View {
    let event: CalendarEvent
    let link: URL?
    let onJoin: (URL) -> Void
    let onDismiss: () -> Void
    let onMuteSeries: (() -> Void)?

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title)
                .font(.title2.bold())
                .lineLimit(2)
            Text("\(timeText) · \(event.calendarTitle)")
                .foregroundStyle(.secondary)

            HStack {
                if let link {
                    Button("Beitreten") { onJoin(link) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                Button("Stumm") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if let onMuteSeries {
                Button("Diese Serie nie wieder", action: onMuteSeries)
                    .buttonStyle(.link)
                    .font(.footnote)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
```

**Step 3: AlarmPanelController**

```swift
import AlarmoohCore
import AppKit
import SwiftUI

/// Das schwebende Fenster unter dem Menueleisten-Icon.
final class AlarmPanelController {
    private var panel: NSPanel?

    func show(view: AlarmView, below iconFrame: NSRect?) {
        close()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 320, height: 160))
        position(panel, below: iconFrame)
        panel.orderFrontRegardless()   // ohne die App zu aktivieren
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Unter dem Icon; ist es nicht sichtbar (Menueleisten-Ueberlauf, Notch),
    /// oben mittig auf dem aktiven Bildschirm.
    private func position(_ panel: NSPanel, below iconFrame: NSRect?) {
        let size = panel.frame.size
        guard let screen = NSScreen.main else { return }

        if let iconFrame, screen.frame.intersects(iconFrame) {
            let x = min(
                max(iconFrame.midX - size.width / 2, screen.visibleFrame.minX + 8),
                screen.visibleFrame.maxX - size.width - 8
            )
            panel.setFrameOrigin(NSPoint(x: x, y: iconFrame.minY - size.height - 6))
        } else {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.maxY - size.height - 12
            ))
        }
    }
}
```

**Step 4: Manuell verifizieren**

Im `AppDelegate` vorübergehend nach dem Start ein Panel mit einem Stub-Termin anzeigen.

Run: `make run`
Expected: Glocken-Icon in der Menüleiste; Panel erscheint direkt darunter, bleibt über anderen Fenstern, stiehlt den Fokus nicht (Tippen im Editor läuft weiter), ist auch nach `Ctrl+→` auf einem anderen Space sichtbar.

**Step 5: Commit**

```bash
git add Sources/alarmooh/StatusItemController.swift Sources/alarmooh/AlarmPanelController.swift Sources/alarmooh/AlarmView.swift
git commit -m "feat: add status item and floating alarm panel"
```

---

## Task 13: Koordinator — Scan-Auslöser, Timer, Aktiv-Prüfung

Das Stück, das alles zusammenhängt.

**Files:**
- Create: `Sources/alarmooh/AlarmCoordinator.swift`
- Modify: `Sources/alarmooh/AppDelegate.swift`

**Step 1: Koordinator schreiben**

```swift
import AlarmoohCore
import AppKit
import CoreGraphics
import EventKit

@MainActor
final class AlarmCoordinator {
    private let source: EventKitCalendarSource
    private let statusItem: StatusItemController
    private let panel = AlarmPanelController()
    private let player = AlarmPlayer()
    private let settingsStore = SettingsStore.standard()

    private var settings: Settings
    private var events: [CalendarEvent] = []
    private var handled: Set<String> = []
    private var alarmTimer: Timer?
    private var scanTimer: Timer?
    private var activeAlarm: CalendarEvent?

    init(source: EventKitCalendarSource, statusItem: StatusItemController) {
        self.source = source
        self.statusItem = statusItem
        self.settings = settingsStore.load()
    }

    func start() {
        player.restoreVolumeAfterCrashIfNeeded()
        statusItem.onIconClickedDuringAlarm = { [weak self] in self?.dismissAlarm() }
        observeSystem()
        scheduleScanTimer()
        scan()
    }

    // MARK: - Scan

    /// Ausgeloest durch: EventKit-Aenderung, Sicherheitstakt, Aufwachen.
    func scan() {
        settings = settingsStore.load()
        let now = Date()
        let raw = (try? source.events(from: now, to: now.addingTimeInterval(86_400))) ?? []
        events = EventFilter.alarmable(raw, settings: settings)
        forgetHandledEventsNoLongerRelevant()
        statusItem.rebuildMenu(nextEvent: events.first)
        scheduleNextAlarm()
    }

    /// Verhindert, dass die Menge der erledigten Alarme unbegrenzt waechst:
    /// Termine ausserhalb des 24-Stunden-Fensters werden vergessen.
    private func forgetHandledEventsNoLongerRelevant() {
        handled.formIntersection(Set(events.map(\.id)))
    }

    // MARK: - Timer

    private func scheduleNextAlarm() {
        alarmTimer?.invalidate()
        guard activeAlarm == nil,
              let next = AlarmScheduler.nextAlarm(
                  events: events, now: Date(), settings: settings, handled: handled
              )
        else { return }

        let delay = max(next.fireDate.timeIntervalSinceNow, 0)
        alarmTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire(next.event) }
        }
        // Wichtig fuer minimale Last: ein einziger Timer, keine Schleife.
        alarmTimer?.tolerance = 5
    }

    private func scheduleScanTimer() {
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(
            withTimeInterval: settings.scanInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scanTimer?.tolerance = 60
    }

    // MARK: - Alarm

    private func fire(_ event: CalendarEvent) {
        // Nur bei aktivem Rechner: schlaeft das Display oder ist der Deckel zu,
        // wird der Alarm verworfen und beim Aufwachen neu bewertet.
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }

        activeAlarm = event
        statusItem.setAlarming(true)
        player.start(settings: settings)

        let link = LinkExtractor.meetingLink(in: event)
        let view = AlarmView(
            event: event,
            link: link,
            onJoin: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.dismissAlarm()
            },
            onDismiss: { [weak self] in self?.dismissAlarm() },
            onMuteSeries: event.seriesID.map { seriesID in
                { [weak self] in
                    self?.muteSeries(seriesID)
                    self?.dismissAlarm()
                }
            }
        )
        panel.show(view: view, below: statusItem.iconFrameOnScreen)
    }

    func dismissAlarm() {
        guard let event = activeAlarm else { return }
        handled.insert(event.id)
        activeAlarm = nil
        player.stop()
        panel.close()
        statusItem.setAlarming(false)
        scheduleNextAlarm()   // ein direkt folgender Termin kommt jetzt dran
    }

    private func muteSeries(_ seriesID: String) {
        settings.mutedSeriesIDs.insert(seriesID)
        try? settingsStore.save(settings)
        scan()
    }

    // MARK: - Systemereignisse

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scan() }
            }
        }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }
}
```

**Step 2: AppDelegate verdrahten**

```swift
import AlarmoohCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let source = EventKitCalendarSource()
    private lazy var statusItem = StatusItemController()
    private lazy var coordinator = AlarmCoordinator(source: source, statusItem: statusItem)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            guard await source.requestAccess() else {
                statusItem.rebuildMenu(nextEvent: nil)
                return
            }
            coordinator.start()
        }
    }
}
```

**Step 3: Manuell verifizieren**

1. `swift test` — Kern weiterhin grün.
2. In Kalender.app einen Termin drei Minuten in der Zukunft anlegen, mit einer Zoom-URL in den Notizen.
3. In `settings.json` den Kalender abonnieren (Einstellungsfenster kommt erst in Task 14):
   ```bash
   cat ~/Library/Application\ Support/alarmooh/settings.json
   ```
4. `make run`
5. Expected: Nach etwa einer Minute erscheint das Panel unter dem Icon, der Ton läuft in Schleife, das Icon ist rot. Klick auf „Beitreten" öffnet den Browser und beendet den Ton; die Systemlautstärke steht wieder auf dem alten Wert.
6. Deckel-Test: Termin anlegen, Deckel schließen, nach der Alarmzeit öffnen. Expected: Kein Alarm, wenn der Termin schon länger als zwei Minuten läuft; Alarm sofort, wenn er noch bevorsteht.

**Step 4: Commit**

```bash
git add Sources/alarmooh/AlarmCoordinator.swift Sources/alarmooh/AppDelegate.swift
git commit -m "feat: wire scan triggers, alarm timer and active-machine check"
```

---

## Task 14: Einstellungsfenster

**Files:**
- Create: `Sources/alarmooh/SettingsView.swift`
- Create: `Sources/alarmooh/SettingsWindowController.swift`
- Modify: `Sources/alarmooh/AlarmCoordinator.swift` (Menüpunkt verbinden)

**Step 1: SettingsView**

Inhalt, gruppiert in einem `Form`:
- **Kalender** — Liste aller `CalendarInfo` mit `Toggle` je Kalender, gebunden an `subscribedCalendarIDs`.
- **Vorlaufzeit** — `Stepper` in Minuten, 1 bis 15, Standard 2.
- **Mindestlautstärke** — `Slider` 0 bis 1.
- **Alarmton** — Pfadanzeige plus Button „Datei wählen…" mit `NSOpenPanel`, gefiltert auf Audiodateien; dazu der Hinweis, dass die Datei nach `~/Library/Application Support/alarmooh/` kopiert wird.
- **Stummgeschaltet** — Liste aus `mutedEventIDs` und `mutedSeriesIDs` mit Löschbutton je Eintrag.
- **Bei Anmeldung starten** — `Toggle`, gebunden an `SMAppService.mainApp`:
  ```swift
  if enabled { try? SMAppService.mainApp.register() }
  else { try? SMAppService.mainApp.unregister() }
  ```

Jede Änderung schreibt sofort über `SettingsStore.save` und ruft `coordinator.scan()`.

**Step 2: SettingsWindowController**

Ein gewöhnliches `NSWindow` mit `NSHostingView`, das beim Öffnen `NSApp.activate()` ruft — hier ist Fokus erwünscht, anders als beim Alarm-Panel.

**Step 3: Manuell verifizieren**

Run: `make run`, dann „Einstellungen…" im Menü.
Expected: Alle Kalender erscheinen; ein Häkchen landet sofort in `settings.json`; „Bei Anmeldung starten" taucht in den Systemeinstellungen unter Anmeldeobjekte auf.

Hinweis: `SMAppService.mainApp` funktioniert zuverlässig erst, wenn `Alarmooh.app` in `/Applications` liegt. Für den Dauerbetrieb dorthin kopieren.

**Step 4: Commit**

```bash
git add Sources/alarmooh/SettingsView.swift Sources/alarmooh/SettingsWindowController.swift Sources/alarmooh/AlarmCoordinator.swift
git commit -m "feat: add settings window"
```

---

## Task 15: README und Abschluss-Durchlauf

**Files:**
- Create: `README.md`

**Step 1: README schreiben**

Inhalt: Zweck in drei Sätzen, Anforderungen (macOS 14+, Swift 6, Command Line Tools genügen), `make bundle` / `make run` / `make test`, wo die Einstellungen liegen, wie man den eigenen Alarmton hinterlegt, und der Hinweis zum Urheberrecht bei fremdem Tonmaterial.

**Step 2: Vollständiger Durchlauf**

```bash
make clean && make test && make bundle
```
Expected: Alle Tests grün, `Alarmooh.app` gebaut.

Abschließende Handprüfung anhand der Liste aus Task 13, zusätzlich:
- Zwei Termine im Abstand von einer Minute: Der zweite Alarm erscheint erst, wenn der erste abgestellt ist.
- Termin ohne Link: Panel zeigt nur „Stumm".
- „Diese Serie nie wieder": Serie verschwindet aus dem Menü und taucht in `settings.json` auf.
- Leerlauf: `top -pid $(pgrep -f Alarmooh.app)` zeigt nahe 0 % CPU.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Offene Punkte für später

- **Ad-hoc-Signatur:** Bei jedem Build ändert sich die Code-Identität, weshalb macOS die Kalenderfrage gelegentlich erneut stellt. Falls störend: einmalig ein selbstsigniertes Zertifikat im Schlüsselbund anlegen und im Makefile statt `--sign -` verwenden.
- **Xcode:** Wird es später installiert, kann die swift-testing-Dependency aus `Package.swift` entfallen; die Tests bleiben unverändert.
- **Bewusst weggelassen:** Snooze, Auto-Timeout des Tons, mehrere Sounds pro Kalender, Kalender-Schreibzugriff, Countdown in der Menüleiste, Google-Calendar-API als zweite Quelle.
