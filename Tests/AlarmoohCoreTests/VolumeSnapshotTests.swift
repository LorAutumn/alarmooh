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
