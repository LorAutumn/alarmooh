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
