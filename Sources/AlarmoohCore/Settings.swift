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
}
