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

// MARK: - Toleranter Decoder

private func load(json: String) throws -> Settings {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(json.utf8).write(to: url)
    return SettingsStore(fileURL: url).load()
}

@Test func emptyJSONObjectDecodesToDefaults() throws {
    #expect(try load(json: "{}") == Settings())
}

@Test func partialJSONKeepsGivenKeysAndDefaultsTheRest() throws {
    let settings = try load(json: #"{"subscribedCalendarIDs": ["cal-work"], "leadTime": 300}"#)

    #expect(settings.subscribedCalendarIDs == ["cal-work"])
    #expect(settings.leadTime == 300)
    #expect(settings.minimumVolume == Settings().minimumVolume)
    #expect(settings.scanInterval == Settings().scanInterval)
    #expect(settings.catchUpGrace == Settings().catchUpGrace)
    #expect(settings.launchAtLogin == Settings().launchAtLogin)
}

@Test func unknownKeyDoesNotBreakDecoding() throws {
    let settings = try load(json: #"{"leadTime": 60, "lieblingsfarbe": "blau"}"#)
    #expect(settings.leadTime == 60)
}

@Test func negativeLeadTimeIsClampedToZero() throws {
    #expect(try load(json: #"{"leadTime": -300}"#).leadTime == 0)
}

@Test func minimumVolumeIsClampedToUnitRange() throws {
    #expect(try load(json: #"{"minimumVolume": 8.0}"#).minimumVolume == 1)
    #expect(try load(json: #"{"minimumVolume": -1.0}"#).minimumVolume == 0)
}

@Test func tooShortScanIntervalIsClamped() throws {
    #expect(try load(json: #"{"scanInterval": 5}"#).scanInterval == 60)
}

@Test func negativeCatchUpGraceIsClampedToZero() throws {
    #expect(try load(json: #"{"catchUpGrace": -10}"#).catchUpGrace == 0)
}

// MARK: - Defekte Datei

@Test func corruptFileIsReportedAndNotOverwritten() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let original = "das hat der Nutzer von Hand geschrieben"
    try Data(original.utf8).write(to: url)

    let store = SettingsStore(fileURL: url)
    #expect(store.load() == Settings())
    #expect(store.lastLoadFailed)

    #expect(throws: SettingsStoreError.self) { try store.save(Settings()) }
    #expect(try String(contentsOf: url, encoding: .utf8) == original)
}

@Test func missingFileIsNotReportedAsFailure() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = SettingsStore(fileURL: url)

    #expect(store.load() == Settings())
    #expect(!store.lastLoadFailed)
    try store.save(Settings())
    #expect(FileManager.default.fileExists(atPath: url.path))
}
