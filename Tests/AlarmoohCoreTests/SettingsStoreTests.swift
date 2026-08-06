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
