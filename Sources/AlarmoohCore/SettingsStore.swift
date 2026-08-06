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
