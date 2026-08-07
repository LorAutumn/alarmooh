import Foundation

public struct VolumeSnapshot: Codable, Equatable, Sendable {
    public let volume: Float
    public let muted: Bool
    /// Das Ausgabegeraet, zu dem `volume` und `muted` gehoeren — als stabile
    /// Kennung (`kAudioDevicePropertyDeviceUID`), nicht als `AudioObjectID`.
    /// Die numerischen IDs vergibt CoreAudio pro Systemstart neu und verwendet
    /// sie wieder; ein Snapshot, der einen Neustart ueberlebt, koennte damit
    /// auf ein voellig anderes Geraet passen.
    ///
    /// Optional aus zwei Gruenden: aeltere Dateien haben das Feld nicht, und
    /// die Kennung ist nicht in jedem Fall lesbar. Beides bedeutet dasselbe —
    /// das Geraet ist unbekannt.
    public let deviceUID: String?

    /// `deviceUID` hat einen Standardwert, damit ein Snapshot ohne bekanntes
    /// Geraet weiterhin ohne Umstand entsteht.
    public init(volume: Float, muted: Bool, deviceUID: String? = nil) {
        self.volume = volume
        self.muted = muted
        self.deviceUID = deviceUID
    }

    /// Eigener Decoder aus demselben Grund wie in `Settings`: die Datei kann
    /// aelter sein als der Code, der sie liest. Genau das ist hier der
    /// Regelfall — eine `volume-snapshot.json`, die eine aeltere Version beim
    /// Anheben geschrieben hat, kennt `deviceUID` nicht. Wuerde sie deshalb
    /// unlesbar, bliebe die Lautstaerke nach einem Absturz oben, und der
    /// Geraeteabgleich haette das Gegenteil dessen bewirkt, wofuer er da ist.
    ///
    /// `volume` und `muted` bleiben Pflicht: ohne sie gibt es nichts
    /// wiederherzustellen, ein Standardwert waere geraten.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decode(Float.self, forKey: .volume)
        muted = try container.decode(Bool.self, forKey: .muted)
        deviceUID = try container.decodeIfPresent(String.self, forKey: .deviceUID)
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
