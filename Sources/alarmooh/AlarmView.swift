import AlarmoohCore
import SwiftUI

struct AlarmView: View {
    let event: CalendarEvent
    let link: URL?
    let onJoin: (URL) -> Void
    let onDismiss: () -> Void
    /// Nur dieses eine Vorkommen; es gibt jeden Termin, auch den einmaligen.
    let onMuteEvent: () -> Void
    /// Alle kuenftigen Vorkommen; nil, wenn der Termin zu keiner Serie gehoert.
    let onMuteSeries: (() -> Void)?

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title)
                .font(.title2.bold())
                .lineLimit(2)
            Text("\(timeText) · \(event.calendarTitle)")
                .foregroundStyle(.secondary)

            // Knopf und Ziel gehoeren zusammen, darum enger gesetzt als der
            // Abstand des umgebenden Stacks.
            VStack(alignment: .leading, spacing: 6) {
                // Das Panel wird nie Key-Window (nonactivatingPanel, orderFrontRegardless),
                // darum ist .defaultAction rein dekorativ. Geschlossen wird per Klick.
                HStack {
                    if let link {
                        Button("Beitreten") { onJoin(link) }
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Stumm") { onDismiss() }
                }

                // Titel, Notizen und URL stammen aus einer Einladung, die jeder
                // schicken kann; der Link hinter "Beitreten" ist damit fremder
                // Text. Unter laufendem Alarmton wird der Knopf im Reflex
                // geklickt, also muss vorher sichtbar sein, wohin er fuehrt.
                // Nur der Host: die volle URL waere fuer 320 pt zu lang und
                // schoebe genau den beurteilbaren Teil aus dem Blick.
                if let link, let host = link.host {
                    Text("Ziel: \(host)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // Vorne kuerzen, denn die aussagekraeftigen Labels
                        // eines Hosts stehen hinten.
                        .truncationMode(.head)
                        .help(link.absoluteString)

                    // Ein unbekannter Host ist kein Beweis fuer einen Angriff:
                    // ein firmeninternes Meeting liegt zu Recht auf einer
                    // eigenen Domain. Darum nur ein Hinweis, kein Sperren des
                    // Knopfes. Die Warnung steht im Text, nicht in der Farbe
                    // allein, sonst traegt sie fuer Farbfehlsichtige nichts.
                    if !LinkExtractor.isKnownProvider(link) {
                        Text("Unbekannter Anbieter — prüfe die Adresse.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            // Eine Zeile bleibt eine Zeile: das Panel soll
                            // unter laufendem Ton nicht in die Hoehe wachsen.
                            .lineLimit(1)
                    }
                }
            }

            // Nebeneinander, damit der Unterschied "nur dieser" gegen "alle"
            // beim Lesen sofort da ist.
            HStack(spacing: 12) {
                Button("Diesen Termin nicht alarmieren", action: onMuteEvent)
                if let onMuteSeries {
                    Button("Diese Serie nie wieder", action: onMuteSeries)
                }
            }
            .buttonStyle(.link)
            .font(.footnote)
        }
        .padding(16)
        .frame(width: 320)
    }
}
