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

    /// Eigener Decoder statt der synthetisierten Variante: Swift ignoriert beim
    /// synthetisierten `Codable` die Standardwerte, jeder nicht-optionale
    /// Schluessel waere also Pflicht. Eine handgeschriebene oder aeltere Datei,
    /// der ein Schluessel fehlt, wuerde damit komplett unlesbar — und weil
    /// `subscribedCalendarIDs` dann leer ist, alarmiert nichts mehr.
    /// Deshalb: jeder Schluessel optional, fehlende fallen auf den Standardwert
    /// zurueck. Unbekannte Schluessel stoeren nicht.
    ///
    /// Hier ist auch die einzige Stelle, an der die Werte geklemmt werden. Die
    /// Datei ist ausdruecklich von Hand editierbar, ein negativer Vorlauf oder
    /// eine Lautstaerke von 8.0 darf nicht durchrutschen.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Einzige Quelle der Standardwerte sind die Property-Initialisierer oben.
        let defaults = Settings()

        subscribedCalendarIDs =
            try container.decodeIfPresent(Set<String>.self, forKey: .subscribedCalendarIDs)
            ?? defaults.subscribedCalendarIDs
        mutedEventIDs =
            try container.decodeIfPresent(Set<String>.self, forKey: .mutedEventIDs)
            ?? defaults.mutedEventIDs
        mutedSeriesIDs =
            try container.decodeIfPresent(Set<String>.self, forKey: .mutedSeriesIDs)
            ?? defaults.mutedSeriesIDs
        soundPath = try container.decodeIfPresent(String.self, forKey: .soundPath)
        launchAtLogin =
            try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
            ?? defaults.launchAtLogin

        // Negativer Vorlauf hiesse: Alarm nach Terminbeginn.
        leadTime = max(
            0,
            try container.decodeIfPresent(TimeInterval.self, forKey: .leadTime) ?? defaults.leadTime
        )
        // CoreAudio erwartet 0…1.
        minimumVolume = min(
            max(
                try container.decodeIfPresent(Float.self, forKey: .minimumVolume)
                    ?? defaults.minimumVolume, 0
            ),
            1
        )
        // Unter einer Minute waere der Sicherheitstakt reine Last.
        scanInterval = max(
            60,
            try container.decodeIfPresent(TimeInterval.self, forKey: .scanInterval)
                ?? defaults.scanInterval
        )
        catchUpGrace = max(
            0,
            try container.decodeIfPresent(TimeInterval.self, forKey: .catchUpGrace)
                ?? defaults.catchUpGrace
        )
    }
}
