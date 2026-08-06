import Foundation

public enum SettingsStoreError: Error, Equatable, Sendable {
    /// Die Datei ist da, laesst sich aber nicht lesen. Sie zu ueberschreiben
    /// wuerde eine von Hand geschriebene Konfiguration vernichten.
    case refusesToOverwriteUnreadableFile(URL)
}

extension SettingsStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .refusesToOverwriteUnreadableFile(let url):
            return "Die Einstellungsdatei \(url.path) ist unlesbar und wird nicht ueberschrieben."
        }
    }
}

/// Liest und schreibt die Einstellungen als lesbares JSON.
public struct SettingsStore: Sendable {
    public let fileURL: URL

    /// Referenztyp, damit `load()` auf dem Value-Type-Store nicht `mutating`
    /// werden muss und alle Kopien des Stores denselben Stand sehen.
    private let loadState = LoadState()

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

    /// True, wenn der letzte `load()` auf eine vorhandene, aber defekte Datei
    /// gestossen ist. Fehlt die Datei schlicht, ist das kein Fehler.
    public var lastLoadFailed: Bool { loadState.failed }

    /// Defekte oder fehlende Datei ergibt Standardwerte — die App soll
    /// deswegen nicht stehenbleiben. Ob es sich um den einen oder den anderen
    /// Fall handelte, verraet `lastLoadFailed`; nur so kann der Aufrufer den
    /// Nutzer warnen, statt stillschweigend ohne Abos weiterzulaufen.
    public func load() -> Settings {
        switch read() {
        case .missing:
            loadState.failed = false
            return Settings()
        case .corrupt:
            loadState.failed = true
            return Settings()
        case .decoded(let settings):
            loadState.failed = false
            return settings
        }
    }

    public func save(_ settings: Settings) throws {
        // Frisch pruefen statt `lastLoadFailed` zu glauben: zwischen Laden und
        // Speichern kann der Nutzer die Datei editiert haben.
        if case .corrupt = read() {
            loadState.failed = true
            throw SettingsStoreError.refusesToOverwriteUnreadableFile(fileURL)
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }

    // MARK: - Intern

    enum ReadResult {
        case missing
        case corrupt
        case decoded(Settings)
    }

    func read() -> ReadResult {
        guard let data = try? Data(contentsOf: fileURL) else {
            // Nicht lesbar, obwohl vorhanden (Rechte, Verzeichnis): wie defekt
            // behandeln, damit nichts ueberschrieben wird.
            return FileManager.default.fileExists(atPath: fileURL.path) ? .corrupt : .missing
        }
        guard let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .corrupt
        }
        return .decoded(settings)
    }
}

/// Kleiner, threadsicherer Merker fuer den Ausgang des letzten Ladevorgangs.
private final class LoadState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var failed: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}
