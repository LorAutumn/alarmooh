import AlarmoohCore
import SwiftUI

/// Aufbereitung von Terminen und gespeicherten Kennungen fuer das
/// Einstellungsfenster. Steht getrennt von `SettingsView`, weil es reine
/// Textarbeit ist und ohne Oberflaeche zu lesen sein soll.
enum EventDisplay {
    /// "Fr., 08.08.2026, 10:00". Feste Vorlage statt `dateStyle`, damit
    /// Wochentag, Datum und Uhrzeit in einer Zeile stehen und ueberall gleich
    /// aussehen; die Oberflaeche ist ohnehin durchgehend deutsch.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EE, dd.MM.yyyy, HH:mm"
        return formatter
    }()

    static func timestamp(_ date: Date) -> String { formatter.string(from: date) }

    /// Der Startzeitpunkt aus der Kennung eines Vorkommens.
    ///
    /// Das Format legt `EventKitCalendarSource.occurrenceID(for:)` fest:
    /// "<eventIdentifier>|<ganze Sekunden seit 1970>". Bewusst das *letzte*
    /// "|": der eventIdentifier ist eine fremde Zeichenkette, in der ein
    /// Trennzeichen vorkommen darf — der Zeitstempel steht immer hinten.
    /// Nil bedeutet: keine Kennung eines Vorkommens (oder eine aus einer
    /// aelteren Datei), dann bleibt nur eine ehrliche Ersatzangabe.
    static func startDate(fromOccurrenceID id: String) -> Date? {
        guard let separator = id.lastIndex(of: "|") else { return nil }
        let seconds = id[id.index(after: separator)...]
        guard !seconds.isEmpty, let value = TimeInterval(seconds) else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}

/// Eine Zeile im Abschnitt "Stummgeschaltet", schon aufgeloest: nie die rohe
/// Kennung als Ueberschrift, sondern das, wonach der Nutzer entscheiden kann.
struct MutedEntry: Identifiable {
    enum Kind {
        case occurrence
        case series

        var label: String {
            switch self {
            case .occurrence: "Termin"
            case .series: "Serie"
            }
        }
    }

    /// Die Kennung, wie sie in den Einstellungen steht.
    let rawID: String
    let kind: Kind
    /// Vorkommen und Serie werden in einer Liste gezeigt; erst Art plus
    /// Kennung ist darin sicher eindeutig.
    var id: String { "\(kind.label)|\(rawID)" }
    /// Ueberschrift der Zeile.
    let title: String
    /// Zweite Zeile; nil, wenn es nichts Genaueres gibt.
    let detail: String?
    /// Nur wenn die Kennung nicht aufzuloesen war, bleibt sie als kleine
    /// Nebenzeile stehen — sonst waere gar nicht mehr zu sehen, welcher
    /// Eintrag da eigentlich in der Datei steht.
    let showsRawID: Bool
    /// Zum Sortieren: bekannte Zeitpunkte zuerst, in zeitlicher Reihenfolge.
    let sortDate: Date?

    /// Loest die gespeicherten Kennungen an den bekannten kommenden Terminen
    /// auf. Was dort nicht vorkommt, faellt auf den Zeitstempel in der Kennung
    /// zurueck; erst danach auf eine reine Kurzangabe.
    static func entries(
        settings: AlarmoohCore.Settings,
        upcoming: [CalendarEvent]
    ) -> [MutedEntry] {
        let series = settings.mutedSeriesIDs.map { id -> MutedEntry in
            guard let next = upcoming.first(where: { $0.seriesID == id }) else {
                return MutedEntry(
                    rawID: id, kind: .series,
                    title: "Serie (kein kommender Termin)",
                    detail: "Alle Wiederholungen bleiben stumm.",
                    showsRawID: true, sortDate: nil
                )
            }
            return MutedEntry(
                rawID: id, kind: .series,
                title: next.title,
                detail: "Ganze Serie · nächster Termin: \(EventDisplay.timestamp(next.start))"
                    + " · \(next.calendarTitle)",
                showsRawID: false, sortDate: next.start
            )
        }

        let occurrences = settings.mutedEventIDs.map { id -> MutedEntry in
            if let event = upcoming.first(where: { $0.id == id }) {
                return MutedEntry(
                    rawID: id, kind: .occurrence,
                    title: event.title,
                    detail: "\(EventDisplay.timestamp(event.start)) · \(event.calendarTitle)",
                    showsRawID: false, sortDate: event.start
                )
            }
            if let start = EventDisplay.startDate(fromOccurrenceID: id) {
                return MutedEntry(
                    rawID: id, kind: .occurrence,
                    title: "Termin am \(EventDisplay.timestamp(start))",
                    detail: nil, showsRawID: true, sortDate: start
                )
            }
            return MutedEntry(
                rawID: id, kind: .occurrence,
                title: "Termin (Zeitpunkt unbekannt)",
                detail: nil, showsRawID: true, sortDate: nil
            )
        }

        return (series + occurrences).sorted { lhs, rhs in
            switch (lhs.sortDate, rhs.sortDate) {
            case let (l?, r?): l == r ? lhs.title < rhs.title : l < r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.title < rhs.title
            }
        }
    }
}

/// Ein kommender Termin mit den Schaltern fuer Vorkommen und Serie.
///
/// Bewusst Schalter und kein Menue pro Zeile: In einer Liste von zehn Terminen
/// muss auf einen Blick zu sehen sein, was noch alarmiert — ein Menue verbirgt
/// genau das hinter einem Klick. Und weil der Unterschied zwischen "dieser
/// Termin" und "die ganze Serie" der eigentliche Fallstrick ist, steht er als
/// ausgeschriebene Beschriftung untereinander statt als zwei Menuepunkte, die
/// man verwechseln kann.
struct UpcomingEventRow: View {
    let event: CalendarEvent
    let isEventMuted: Bool
    let isSeriesMuted: Bool
    let setEventMuted: (Bool) -> Void
    let setSeriesMuted: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title).fontWeight(.medium)
            Text("\(EventDisplay.timestamp(event.start)) · \(event.calendarTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Alarm für diesen Termin", isOn: Binding(
                // Bei stummer Serie ist der Schalter des Vorkommens
                // bedeutungslos — dann zeigt er "aus" und laesst sich nicht
                // bedienen, statt ein "an" vorzugaukeln, das nichts bewirkt.
                get: { !isSeriesMuted && !isEventMuted },
                set: { setEventMuted(!$0) }
            ))
            .disabled(isSeriesMuted)

            if event.seriesID != nil {
                Toggle("Alarm für die ganze Serie (alle Wiederholungen)", isOn: Binding(
                    get: { !isSeriesMuted },
                    set: { setSeriesMuted(!$0) }
                ))
            }

            if isSeriesMuted {
                Text("Die ganze Serie ist stummgeschaltet — dieser Termin alarmiert nicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 2)
    }
}

/// Eine Zeile im Abschnitt "Stummgeschaltet".
struct MutedEntryRow: View {
    let entry: MutedEntry
    let unmute: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.label).font(.caption).foregroundStyle(.secondary)
                Text(entry.title).fontWeight(.medium)
                if let detail = entry.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if entry.showsRawID {
                    Text(entry.rawID)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button("Wieder alarmieren", action: unmute)
        }
    }
}
