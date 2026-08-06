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

            // Nebeneinander, damit der Unterschied "nur dieser" gegen "alle"
            // beim Lesen sofort da ist.
            HStack(spacing: 12) {
                Button("Diesen Termin nie wieder", action: onMuteEvent)
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
