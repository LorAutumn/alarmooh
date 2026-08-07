import Foundation

/// Das Format der Kennung eines einzelnen Vorkommens — an einer Stelle
/// geschrieben und gelesen.
///
/// Aufbau: `"<eventIdentifier>|<ganze Sekunden seit 1970>"`.
///
/// Warum ueberhaupt der Startzeitpunkt darin steht, begruendet
/// `EventKitCalendarSource.occurrenceID(for:)`: der `eventIdentifier` gehoert
/// bei Serienterminen der ganzen Serie. Der Zeitpunkt wird als ganze Sekunden
/// geschrieben, damit die Kennung bei jedem erneuten Scan bitgleich ist und
/// nicht von Locale, Zeitzone oder Double-Formatierung abhaengt.
///
/// Warum das hier steht und nicht bei EventKit: der Zeitstempel wird an zwei
/// weiteren Stellen wieder gelesen — das Einstellungsfenster zeigt ihn an, und
/// `withoutExpired` raeumt damit alte Stummschaltungen weg. Zwei Parser
/// nebeneinander waeren die Stelle, an der beide Seiten spaeter auseinander
/// laufen.
public enum OccurrenceID {
    /// Trennt Grundteil und Zeitstempel.
    private static let separator: Character = "|"

    public static func make(eventIdentifier: String, start: Date) -> String {
        "\(eventIdentifier)\(separator)\(Int(start.timeIntervalSince1970))"
    }

    /// Der Startzeitpunkt aus einer Kennung.
    ///
    /// Bewusst das *letzte* Trennzeichen: der `eventIdentifier` ist eine fremde
    /// Zeichenkette, in der ein "|" vorkommen darf — der Zeitstempel steht
    /// immer hinten.
    ///
    /// Nil bedeutet: keine Kennung eines Vorkommens (oder eine aus einer
    /// aelteren Datei). Nil heisst ausdruecklich nicht "ungueltig, weg damit" —
    /// wer den Wert auswertet, muss den Eintrag stehen lassen.
    public static func startDate(from id: String) -> Date? {
        guard let separatorIndex = id.lastIndex(of: separator) else { return nil }
        let seconds = id[id.index(after: separatorIndex)...]
        guard !seconds.isEmpty, let value = TimeInterval(seconds) else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    /// Wie lange die Stummschaltung eines einzelnen Vorkommens aufgehoben wird,
    /// gerechnet ab dessen Beginn.
    ///
    /// Bewusst fest und nicht einstellbar: ein Vorkommen ist vorbei, seine
    /// Stummschaltung hat danach keine Wirkung mehr. Die Woche ist reine
    /// Kulanz, damit ein Eintrag im Einstellungsfenster nicht verschwindet,
    /// waehrend der Nutzer sich noch an den Termin erinnert.
    public static let mutedRetention: TimeInterval = 7 * 86_400

    /// Die Kennungen ohne die laengst abgelaufenen.
    ///
    /// Zwei Regeln, beide in die sichere Richtung:
    /// - Die Grenze gehoert noch dazu: ein Vorkommen, das genau
    ///   `mutedRetention` zurueckliegt, bleibt stumm. Dieselbe Lesart wie bei
    ///   `catchUpGrace` im `AlarmScheduler` — "hoechstens so alt", nicht
    ///   "juenger als".
    /// - Was sich nicht lesen laesst, bleibt. Eine unbekannte Kennung
    ///   wegzuwerfen hiesse, etwas wieder scharf zu schalten, das der Nutzer
    ///   ausdruecklich abgestellt hat.
    ///
    /// Nur fuer einzelne Vorkommen (`mutedEventIDs`). Stummgeschaltete Serien
    /// tragen keinen Zeitstempel und gelten auf Dauer — die gehoeren hier nie
    /// hinein.
    public static func withoutExpired(_ ids: Set<String>, now: Date) -> Set<String> {
        let cutoff = now.addingTimeInterval(-mutedRetention)
        return ids.filter { id in
            guard let start = startDate(from: id) else { return true }
            return start >= cutoff
        }
    }
}
