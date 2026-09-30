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

// MARK: - Zuruecksetzen

/// Nach einem Alarm im selben Lauf: der Zustand von vorher kommt voll zurueck,
/// auch wenn das lauter ist — die Kopfhoerer standen vor dem Alarm auf 0,8.
@Test func restoreFromThisRunMayBeLouder() {
    let before = VolumeSnapshot(volume: 0.8, muted: false, deviceUID: "EarPods")
    let now = VolumeSnapshot(volume: 0.1, muted: false, deviceUID: "EarPods")

    #expect(before.restoreTarget(current: now, allowLouder: true) == before)
}

/// Aus der Datei (Absturz oder liegengebliebener Snapshot): der Wert kann alt
/// sein, und der Nutzer hat inzwischen vielleicht leiser gestellt. Dann nie
/// lauter als jetzt — sonst kaemen 0,8 von gestern ins Ohr.
@Test func restoreFromFileIsNeverLouder() {
    let stale = VolumeSnapshot(volume: 0.8, muted: false, deviceUID: "EarPods")
    let now = VolumeSnapshot(volume: 0.2, muted: false, deviceUID: "EarPods")

    #expect(stale.restoreTarget(current: now, allowLouder: false).volume == 0.2)
}

/// Leiser zuruecksetzen ist dagegen genau der Zweck der Absturzsicherung:
/// Lautsprecher wurden fuer den Alarm angehoben.
@Test func restoreFromFileStillLowers() {
    let before = VolumeSnapshot(volume: 0.2, muted: true, deviceUID: "BuiltInSpeakerDevice")
    let now = VolumeSnapshot(volume: 0.5, muted: false, deviceUID: "BuiltInSpeakerDevice")

    #expect(before.restoreTarget(current: now, allowLouder: false) == before)
}

/// Eine Stummschaltung aufzuheben waere auch "lauter".
@Test func restoreFromFileKeepsCurrentMute() {
    let stale = VolumeSnapshot(volume: 0.3, muted: false, deviceUID: "EarPods")
    let now = VolumeSnapshot(volume: 0.5, muted: true, deviceUID: "EarPods")

    let target = stale.restoreTarget(current: now, allowLouder: false)
    #expect(target.muted)
    #expect(target.volume == 0.3)
}

/// Ist der aktuelle Zustand nicht lesbar, laesst sich "lauter" nicht pruefen;
/// dann bleibt es beim gemerkten Wert wie bisher.
@Test func restoreWithoutCurrentStateUsesSnapshot() {
    let snapshot = VolumeSnapshot(volume: 0.4, muted: false, deviceUID: "EarPods")

    #expect(snapshot.restoreTarget(current: nil, allowLouder: false) == snapshot)
}
