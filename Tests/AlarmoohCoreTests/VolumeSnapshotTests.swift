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

// MARK: - Ausgabegeraet

@Test func snapshotRoundTripsWithDevice() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = VolumeSnapshotStore(fileURL: url)

    try store.save(VolumeSnapshot(volume: 1.0, muted: false, deviceUID: "BuiltInSpeakerDevice"))

    #expect(store.load()?.deviceUID == "BuiltInSpeakerDevice")
    #expect(store.load() == VolumeSnapshot(volume: 1.0, muted: false, deviceUID: "BuiltInSpeakerDevice"))
}

/// Der eigentliche Migrationsfall: eine Datei, die eine Version ohne
/// Geraetefeld geschrieben hat. Wuerde sie unlesbar, bliebe die Lautstaerke
/// nach einem Absturz oben — der Geraeteabgleich haette dann das Gegenteil
/// dessen bewirkt, wofuer er da ist.
@Test func legacyJSONWithoutDeviceDecodesWithNilDevice() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"volume":0.4,"muted":true}"#.utf8).write(to: url)

    let loaded = try #require(VolumeSnapshotStore(fileURL: url).load())

    #expect(loaded.volume == 0.4)
    #expect(loaded.muted)
    #expect(loaded.deviceUID == nil)
}

/// Ohne Lautstaerke gibt es nichts wiederherzustellen; ein geratener
/// Standardwert waere schlimmer als gar kein Snapshot.
@Test func jsonWithoutVolumeYieldsNil() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"muted":false}"#.utf8).write(to: url)

    #expect(VolumeSnapshotStore(fileURL: url).load() == nil)
}

@Test func equalityIncludesDevice() {
    let speakers = VolumeSnapshot(volume: 1.0, muted: false, deviceUID: "BuiltInSpeakerDevice")

    #expect(speakers == VolumeSnapshot(volume: 1.0, muted: false, deviceUID: "BuiltInSpeakerDevice"))
    // Derselbe Pegel auf einem anderen Geraet ist ein anderer Zustand — genau
    // die Verwechslung, die das Feld verhindern soll.
    #expect(speakers != VolumeSnapshot(volume: 1.0, muted: false, deviceUID: "AirPods"))
    // Und "Geraet unbekannt" ist nicht dasselbe wie ein bekanntes Geraet.
    #expect(speakers != VolumeSnapshot(volume: 1.0, muted: false))
    #expect(VolumeSnapshot(volume: 1.0, muted: false) == VolumeSnapshot(volume: 1.0, muted: false))
}
